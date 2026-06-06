create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  phone text not null default '',
  address text not null default '',
  email text not null default '',
  role text not null default 'customer' check (role in ('customer', 'owner', 'manager', 'counter')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.products (
  id text primary key,
  category_id uuid not null references public.categories(id),
  name text not null,
  description text not null,
  price integer not null check (price >= 0),
  image_url text not null default '',
  available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.deals (
  id text primary key,
  name text not null,
  item_names text[] not null default '{}',
  original_price integer not null check (original_price >= 0),
  deal_price integer not null check (deal_price >= 0),
  image_url text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.cart_items (
  cart_id uuid not null references public.carts(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity > 0),
  primary key (cart_id, product_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  customer_name text not null,
  phone text not null,
  address text not null,
  payment_method text not null,
  subtotal integer not null check (subtotal >= 0),
  delivery_fee integer not null default 0 check (delivery_fee >= 0),
  status text not null default 'received' check (status in ('received', 'processing', 'outForDelivery', 'delivered')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text references public.products(id) on delete set null,
  name text not null,
  price integer not null check (price >= 0),
  quantity integer not null check (quantity > 0)
);

create table public.staff_permissions (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  view_orders boolean not null default false,
  update_order_status boolean not null default false,
  manage_menu boolean not null default false,
  manage_deals boolean not null default false,
  view_reports boolean not null default false,
  updated_at timestamptz not null default now()
);

create index orders_customer_id_created_at_idx on public.orders(customer_id, created_at desc);
create index orders_assigned_to_idx on public.orders(assigned_to);
create index products_category_id_idx on public.products(category_id);
create index order_items_order_id_idx on public.order_items(order_id);

create or replace function public.current_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and active = true
$$;

create or replace function public.has_permission(permission_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role() = 'owner' or coalesce(
    (
      select case permission_name
        when 'view_orders' then view_orders
        when 'update_order_status' then update_order_status
        when 'manage_menu' then manage_menu
        when 'manage_deals' then manage_deals
        when 'view_reports' then view_reports
        else false
      end
      from public.staff_permissions
      where profile_id = auth.uid()
    ),
    false
  )
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, phone, address, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'address', ''),
    coalesce(new.email, '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.protect_profile_access()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.uid() is not null and public.current_role() <> 'owner' then
    new.role := old.role;
    new.active := old.active;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger protect_profile_access_before_update
before update on public.profiles
for each row execute procedure public.protect_profile_access();

create or replace function public.enforce_counter_permissions()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (select role from public.profiles where id = new.profile_id) = 'counter' then
    new.view_orders := true;
    new.update_order_status := true;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger enforce_counter_permissions_before_write
before insert or update on public.staff_permissions
for each row execute procedure public.enforce_counter_permissions();

create or replace function public.place_order(
  p_address text,
  p_phone text,
  p_payment_method text,
  p_delivery_fee integer,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_order_id uuid;
  order_subtotal integer;
  customer_name text;
  assigned_counter uuid;
begin
  if auth.uid() is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A signed-in customer and at least one item are required.';
  end if;

  select name into customer_name
  from public.profiles
  where id = auth.uid() and role = 'customer' and active = true;

  if customer_name is null then
    raise exception 'Customer account is unavailable.';
  end if;

  select coalesce(sum(p.price * requested.quantity), 0)::integer into order_subtotal
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.products p on p.id = requested.product_id and p.available = true
  where requested.quantity > 0;

  if order_subtotal <= 0 then
    raise exception 'No available products were selected.';
  end if;

  select id into assigned_counter
  from public.profiles
  where role = 'counter' and active = true
  order by created_at
  limit 1;

  insert into public.orders (customer_id, customer_name, phone, address, payment_method, subtotal, delivery_fee, assigned_to)
  values (auth.uid(), customer_name, p_phone, p_address, p_payment_method, order_subtotal, greatest(p_delivery_fee, 0), assigned_counter)
  returning id into new_order_id;

  insert into public.order_items (order_id, product_id, name, price, quantity)
  select new_order_id, p.id, p.name, p.price, requested.quantity
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.products p on p.id = requested.product_id and p.available = true
  where requested.quantity > 0;

  return new_order_id;
end;
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.deals enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.staff_permissions enable row level security;

create policy "profiles read own" on public.profiles for select to authenticated using (id = auth.uid());
create policy "profiles update own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "owners manage profiles" on public.profiles for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy "read active categories" on public.categories for select to anon, authenticated using (active = true or public.has_permission('manage_menu'));
create policy "menu staff manage categories" on public.categories for all to authenticated using (public.has_permission('manage_menu')) with check (public.has_permission('manage_menu'));

create policy "read active products" on public.products for select to anon, authenticated using (available = true or public.has_permission('manage_menu'));
create policy "menu staff manage products" on public.products for all to authenticated using (public.has_permission('manage_menu')) with check (public.has_permission('manage_menu'));

create policy "read active deals" on public.deals for select to anon, authenticated using (active = true or public.has_permission('manage_deals'));
create policy "deal staff manage deals" on public.deals for all to authenticated using (public.has_permission('manage_deals')) with check (public.has_permission('manage_deals'));

create policy "customers manage own cart" on public.carts for all to authenticated using (customer_id = auth.uid()) with check (customer_id = auth.uid());
create policy "owners manage carts" on public.carts for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');
create policy "customers manage own cart items" on public.cart_items for all to authenticated
using (exists (select 1 from public.carts where carts.id = cart_items.cart_id and carts.customer_id = auth.uid()))
with check (exists (select 1 from public.carts where carts.id = cart_items.cart_id and carts.customer_id = auth.uid()));
create policy "owners manage cart items" on public.cart_items for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

create policy "customers read own orders" on public.orders for select to authenticated using (customer_id = auth.uid());
create policy "owners manage orders" on public.orders for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');
create policy "staff read permitted orders" on public.orders for select to authenticated
using (
  public.current_role() = 'owner'
  or (public.current_role() = 'manager' and (public.has_permission('view_orders') or public.has_permission('view_reports')))
  or (public.current_role() = 'counter' and public.has_permission('view_orders') and assigned_to = auth.uid())
);
create policy "staff update permitted orders" on public.orders for update to authenticated
using (
  public.current_role() = 'owner'
  or (public.current_role() = 'manager' and public.has_permission('update_order_status'))
  or (public.current_role() = 'counter' and public.has_permission('update_order_status') and assigned_to = auth.uid())
)
with check (
  public.current_role() = 'owner'
  or (public.current_role() = 'manager' and public.has_permission('update_order_status'))
  or (public.current_role() = 'counter' and public.has_permission('update_order_status') and assigned_to = auth.uid())
);

create policy "customers read own order items" on public.order_items for select to authenticated
using (exists (select 1 from public.orders where orders.id = order_items.order_id and orders.customer_id = auth.uid()));
create policy "owners manage order items" on public.order_items for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');
create policy "staff read permitted order items" on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_items.order_id
      and (
        public.current_role() = 'owner'
        or (public.current_role() = 'manager' and (public.has_permission('view_orders') or public.has_permission('view_reports')))
        or (public.current_role() = 'counter' and public.has_permission('view_orders') and orders.assigned_to = auth.uid())
      )
  )
);

create policy "staff read own permissions" on public.staff_permissions for select to authenticated using (profile_id = auth.uid());
create policy "owners manage permissions" on public.staff_permissions for all to authenticated using (public.current_role() = 'owner') with check (public.current_role() = 'owner');

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = excluded.public;

create policy "public product images" on storage.objects for select to public using (bucket_id = 'product-images');
create policy "menu staff upload product images" on storage.objects for insert to authenticated
with check (bucket_id = 'product-images' and public.has_permission('manage_menu'));
create policy "menu staff update product images" on storage.objects for update to authenticated
using (bucket_id = 'product-images' and public.has_permission('manage_menu'))
with check (bucket_id = 'product-images' and public.has_permission('manage_menu'));
create policy "menu staff delete product images" on storage.objects for delete to authenticated
using (bucket_id = 'product-images' and public.has_permission('manage_menu'));

grant execute on function public.current_role() to anon, authenticated;
grant execute on function public.has_permission(text) to anon, authenticated;
grant execute on function public.place_order(text, text, text, integer, jsonb) to authenticated;

insert into public.categories (name, sort_order) values
  ('Beefbash', 1),
  ('Chickbash', 2),
  ('Wrapsters', 3),
  ('Fryworks', 4),
  ('Mashmeal', 5),
  ('Extras', 6),
  ('Dips', 7)
on conflict (name) do update set sort_order = excluded.sort_order, active = true;

insert into public.products (id, category_id, name, description, price, image_url) values
  ('sada-wala', (select id from public.categories where name = 'Beefbash'), 'Sada Wala', 'Single beef patty, cheese, burger dressing, iceberg, tomato, onion and pickles', 550, 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=900&q=80'),
  ('bara-wala', (select id from public.categories where name = 'Beefbash'), 'Bara Wala', 'Double beef patty, cheese, burger dressing, iceberg, tomato, onion and pickles', 700, 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=900&q=80'),
  ('angethi-wala', (select id from public.categories where name = 'Beefbash'), 'Angethi Wala', 'Heavy grilled beef patty, extra burger dressing, cheese, iceberg, tomato, onion and pickles', 650, 'https://images.unsplash.com/photo-1571091718767-18b5b1457add?auto=format&fit=crop&w=900&q=80'),
  ('murgh-masti', (select id from public.categories where name = 'Chickbash'), 'Murgh Masti', 'Single chicken patty, cheese, burger dressing, iceberg, tomato, onion and pickles', 500, 'https://images.unsplash.com/photo-1606755962773-d324e0a13086?auto=format&fit=crop&w=900&q=80'),
  ('murgh-supreme', (select id from public.categories where name = 'Chickbash'), 'Murgh Supreme', 'Double chicken patty, cheese, burger dressing, iceberg, tomato, onion and pickles', 700, 'https://images.unsplash.com/photo-1615297928064-24977384d0da?auto=format&fit=crop&w=900&q=80'),
  ('beast-wrap', (select id from public.categories where name = 'Wrapsters'), 'Beast Wrap', 'Tortilla, beef, dressing, iceberg, cucumber, tomato, chips, onion and pickles', 600, 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?auto=format&fit=crop&w=900&q=80'),
  ('cluckistan', (select id from public.categories where name = 'Wrapsters'), 'Cluckistan', 'Tortilla, chicken, dressing, iceberg, cucumber, tomato, chips and onion', 500, 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?auto=format&fit=crop&w=900&q=80'),
  ('fancy-fries', (select id from public.categories where name = 'Fryworks'), 'Fancy Fries', 'Sauce, fries, onion and jalapeno', 250, 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=900&q=80'),
  ('classy-fries', (select id from public.categories where name = 'Fryworks'), 'Classy Fries', 'Classic golden french fries', 150, 'https://images.unsplash.com/photo-1630384060421-cb20d0e0649d?auto=format&fit=crop&w=900&q=80'),
  ('messy-fries', (select id from public.categories where name = 'Fryworks'), 'Messy Fries', 'Chicken, sauce, fries and jalapeno', 300, 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=900&q=80'),
  ('meal-drink', (select id from public.categories where name = 'Mashmeal'), 'Meal + Drink Combo', 'Add a chilled drink and fries to complete your meal', 200, 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=900&q=80'),
  ('beef-patty', (select id from public.categories where name = 'Extras'), 'Beef Patty', 'Fresh grilled beef patty', 300, 'https://images.unsplash.com/photo-1603360946369-dc9bb6258143?auto=format&fit=crop&w=900&q=80'),
  ('chicken-patty', (select id from public.categories where name = 'Extras'), 'Chicken Patty', 'Fresh grilled chicken patty', 250, 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?auto=format&fit=crop&w=900&q=80'),
  ('fried-egg', (select id from public.categories where name = 'Extras'), 'Fried Egg', 'Freshly fried egg', 100, 'https://images.unsplash.com/photo-1525351484163-7529414344d8?auto=format&fit=crop&w=900&q=80'),
  ('cheese', (select id from public.categories where name = 'Extras'), 'Cheese', 'Melted cheese slice', 55, 'https://images.unsplash.com/photo-1486297678162-eb2a19b0a32d?auto=format&fit=crop&w=900&q=80'),
  ('chicken-100gm', (select id from public.categories where name = 'Extras'), 'Chicken 100gm', 'Seasoned chicken serving', 150, 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?auto=format&fit=crop&w=900&q=80'),
  ('white-dip', (select id from public.categories where name = 'Dips'), 'White Dip', 'Creamy signature white dip', 70, 'https://images.unsplash.com/photo-1472476443507-c7a5948772fc?auto=format&fit=crop&w=900&q=80'),
  ('burger-dip', (select id from public.categories where name = 'Dips'), 'Burger Dip', 'Mashbash signature burger dip', 50, 'https://images.unsplash.com/photo-1472476443507-c7a5948772fc?auto=format&fit=crop&w=900&q=80'),
  ('red-chutney', (select id from public.categories where name = 'Dips'), 'Red Chutney Spicy', 'Bold and spicy red chutney', 50, 'https://images.unsplash.com/photo-1472476443507-c7a5948772fc?auto=format&fit=crop&w=900&q=80')
on conflict (id) do update set
  category_id = excluded.category_id,
  name = excluded.name,
  description = excluded.description,
  price = excluded.price,
  image_url = excluded.image_url,
  available = true;

insert into public.deals (id, name, item_names, original_price, deal_price, image_url)
values (
  'meet-eat-repeat-deal',
  'Meet.Eat.Repeat Deal',
  array['Sada Wala', 'Classy Fries', 'Drink'],
  900,
  749,
  'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=900&q=80'
)
on conflict (id) do update set active = true;
