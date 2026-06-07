alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('customer', 'owner', 'manager', 'counter', 'rider'));
alter table public.profiles add column if not exists rider_available boolean not null default false;

alter table public.categories add column if not exists image_url text not null default '';
alter table public.products add column if not exists sort_order integer not null default 0;
alter table public.staff_permissions add column if not exists assign_riders boolean not null default false;
alter table public.staff_permissions add column if not exists manage_slides boolean not null default false;

alter table public.orders drop constraint if exists orders_status_check;
update public.orders set status = 'preparing' where status = 'processing';
update public.orders set status = 'out_for_delivery' where status = 'outForDelivery';
alter table public.orders add constraint orders_status_check check (
  status in ('received', 'accepted', 'preparing', 'ready_for_delivery', 'assigned_to_rider', 'out_for_delivery', 'delivered', 'cancelled')
);
alter table public.orders add column if not exists assigned_rider_id uuid references public.profiles(id) on delete set null;
alter table public.orders add column if not exists accepted_by uuid references public.profiles(id) on delete set null;
alter table public.orders add column if not exists assigned_at timestamptz;
alter table public.orders add column if not exists delivered_at timestamptz;
create index if not exists orders_assigned_rider_id_idx on public.orders(assigned_rider_id);

create table if not exists public.home_slides (
  id text primary key,
  title text not null,
  subtitle text not null default '',
  image_url text not null,
  link_type text not null default 'none' check (link_type in ('none', 'deal', 'product', 'category')),
  link_id text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_status_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists order_status_history_order_id_idx on public.order_status_history(order_id, created_at);

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
        when 'assign_riders' then assign_riders
        when 'manage_menu' then manage_menu
        when 'manage_deals' then manage_deals
        when 'manage_slides' then manage_slides
        when 'view_reports' then view_reports
        else false
      end
      from public.staff_permissions
      where profile_id = auth.uid()
    ),
    false
  )
$$;

create or replace function public.enforce_counter_permissions()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (select role from public.profiles where id = new.profile_id) = 'counter' then
    new.view_orders := true;
    new.update_order_status := true;
    new.assign_riders := true;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

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
begin
  if auth.uid() is null or jsonb_array_length(p_items) = 0 then
    raise exception 'A signed-in customer and at least one item are required.';
  end if;

  select name into customer_name from public.profiles where id = auth.uid() and role = 'customer' and active = true;
  if customer_name is null then raise exception 'Customer account is unavailable.'; end if;

  with requested as (
    select product_id, quantity from jsonb_to_recordset(p_items) as item(product_id text, quantity integer) where quantity > 0
  ),
  priced as (
    select requested.product_id, requested.quantity, products.price
    from requested join public.products on products.id = requested.product_id and products.available = true
    union all
    select requested.product_id, requested.quantity, deals.deal_price
    from requested join public.deals on requested.product_id = 'deal:' || deals.id and deals.active = true
  )
  select coalesce(sum(price * quantity), 0)::integer into order_subtotal from priced;

  if order_subtotal <= 0 then raise exception 'No available products were selected.'; end if;

  insert into public.orders (customer_id, customer_name, phone, address, payment_method, subtotal, delivery_fee)
  values (auth.uid(), customer_name, p_phone, p_address, p_payment_method, order_subtotal, greatest(p_delivery_fee, 0))
  returning id into new_order_id;

  insert into public.order_items (order_id, product_id, name, price, quantity)
  select new_order_id, products.id, products.name, products.price, requested.quantity
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.products on products.id = requested.product_id and products.available = true
  where requested.quantity > 0;

  insert into public.order_items (order_id, product_id, name, price, quantity)
  select new_order_id, null, deals.name, deals.deal_price, requested.quantity
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.deals on requested.product_id = 'deal:' || deals.id and deals.active = true
  where requested.quantity > 0;

  insert into public.order_status_history (order_id, status, changed_by) values (new_order_id, 'received', auth.uid());
  return new_order_id;
end;
$$;

create or replace function public.update_order_status(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text := public.current_role();
  current_status text;
  assigned_rider uuid;
  valid_transition boolean := false;
begin
  select status, assigned_rider_id into current_status, assigned_rider from public.orders where id = p_order_id for update;
  if current_status is null then raise exception 'Order not found.'; end if;

  if actor_role = 'rider' then
    if assigned_rider <> auth.uid() then raise exception 'This delivery is not assigned to you.'; end if;
    valid_transition := (current_status = 'assigned_to_rider' and p_status = 'out_for_delivery')
      or (current_status = 'out_for_delivery' and p_status = 'delivered');
  elsif actor_role = 'owner' or (actor_role in ('manager', 'counter') and public.has_permission('update_order_status')) then
    valid_transition := (p_status = 'cancelled' and current_status not in ('delivered', 'cancelled'))
      or (current_status = 'received' and p_status = 'accepted')
      or (current_status = 'accepted' and p_status = 'preparing')
      or (current_status = 'preparing' and p_status = 'ready_for_delivery')
      or (current_status = 'ready_for_delivery' and p_status = 'assigned_to_rider')
      or (current_status = 'assigned_to_rider' and p_status = 'out_for_delivery')
      or (current_status = 'out_for_delivery' and p_status = 'delivered');
  end if;

  if not valid_transition then raise exception 'That status change is not allowed.'; end if;
  if p_status = 'assigned_to_rider' and assigned_rider is null then raise exception 'Assign an available rider first.'; end if;

  update public.orders set
    status = p_status,
    accepted_by = case when p_status = 'accepted' then auth.uid() else accepted_by end,
    delivered_at = case when p_status = 'delivered' then now() else delivered_at end,
    updated_at = now()
  where id = p_order_id;

  if p_status = 'delivered' and assigned_rider is not null then
    update public.profiles set rider_available = true where id = assigned_rider;
  end if;
  insert into public.order_status_history (order_id, status, changed_by) values (p_order_id, p_status, auth.uid());
end;
$$;

create or replace function public.assign_order_rider(p_order_id uuid, p_rider_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status text;
begin
  if not (public.current_role() = 'owner' or (public.current_role() in ('manager', 'counter') and public.has_permission('assign_riders'))) then
    raise exception 'You do not have permission to assign riders.';
  end if;
  if not exists (select 1 from public.profiles where id = p_rider_id and role = 'rider' and active = true and rider_available = true) then
    raise exception 'The selected rider is not available.';
  end if;
  select status into current_status from public.orders where id = p_order_id for update;
  if current_status <> 'ready_for_delivery' then raise exception 'The order must be ready for delivery before rider assignment.'; end if;

  update public.orders
  set assigned_rider_id = p_rider_id, assigned_at = now(), status = 'assigned_to_rider', updated_at = now()
  where id = p_order_id;
  update public.profiles set rider_available = false where id = p_rider_id;
  insert into public.order_status_history (order_id, status, changed_by) values (p_order_id, 'assigned_to_rider', auth.uid());
end;
$$;

create or replace function public.set_rider_availability(p_available boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_role() <> 'rider' then raise exception 'Rider access required.'; end if;
  update public.profiles set rider_available = p_available, updated_at = now() where id = auth.uid();
end;
$$;

alter table public.home_slides enable row level security;
alter table public.order_status_history enable row level security;

drop policy if exists "staff read permitted orders" on public.orders;
drop policy if exists "staff update permitted orders" on public.orders;
drop policy if exists "staff read permitted order items" on public.order_items;

create policy "staff read permitted orders" on public.orders for select to authenticated
using (
  public.current_role() = 'owner'
  or (public.current_role() in ('manager', 'counter') and (public.has_permission('view_orders') or public.has_permission('view_reports')))
  or (public.current_role() = 'rider' and assigned_rider_id = auth.uid())
);
create policy "staff read permitted order items" on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_items.order_id
      and (
        public.current_role() = 'owner'
        or (public.current_role() in ('manager', 'counter') and (public.has_permission('view_orders') or public.has_permission('view_reports')))
        or (public.current_role() = 'rider' and orders.assigned_rider_id = auth.uid())
      )
  )
);

create policy "staff read active riders" on public.profiles for select to authenticated
using (role = 'rider' and active = true and (public.current_role() = 'owner' or public.has_permission('assign_riders')));

create policy "read active home slides" on public.home_slides for select to anon, authenticated
using (active = true or public.has_permission('manage_slides'));
create policy "slide staff manage home slides" on public.home_slides for all to authenticated
using (public.has_permission('manage_slides')) with check (public.has_permission('manage_slides'));

create policy "customers read own status history" on public.order_status_history for select to authenticated
using (exists (select 1 from public.orders where orders.id = order_status_history.order_id and orders.customer_id = auth.uid()));
create policy "staff read permitted status history" on public.order_status_history for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_status_history.order_id
      and (
        public.current_role() = 'owner'
        or (public.current_role() in ('manager', 'counter') and public.has_permission('view_orders'))
        or (public.current_role() = 'rider' and orders.assigned_rider_id = auth.uid())
      )
  )
);

grant execute on function public.update_order_status(uuid, text) to authenticated;
grant execute on function public.assign_order_rider(uuid, uuid) to authenticated;
grant execute on function public.set_rider_availability(boolean) to authenticated;

update public.categories set image_url = case name
  when 'Beefbash' then 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=300&q=80'
  when 'Chickbash' then 'https://images.unsplash.com/photo-1606755962773-d324e0a13086?auto=format&fit=crop&w=300&q=80'
  when 'Wrapsters' then 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?auto=format&fit=crop&w=300&q=80'
  when 'Fryworks' then 'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?auto=format&fit=crop&w=300&q=80'
  when 'Mashmeal' then 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=300&q=80'
  when 'Extras' then 'https://images.unsplash.com/photo-1532550907401-a500c9a57435?auto=format&fit=crop&w=300&q=80'
  else 'https://images.unsplash.com/photo-1472476443507-c7a5948772fc?auto=format&fit=crop&w=300&q=80'
end where image_url = '';

insert into public.home_slides (id, title, subtitle, image_url, link_type, link_id, sort_order) values
  ('meet-eat-repeat', 'Meet. Eat. Repeat.', 'Bold burgers, serious flavor.', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1200&q=85', 'category', (select id::text from public.categories where name = 'Beefbash'), 1),
  ('wrapsters', 'Wrapsters are here', 'Big wraps packed with Mashbash flavor.', 'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?auto=format&fit=crop&w=1200&q=85', 'category', (select id::text from public.categories where name = 'Wrapsters'), 2),
  ('launch-deal', 'The Mashbash Deal', 'Sada Wala, fries and a drink.', 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=1200&q=85', 'deal', 'meet-eat-repeat-deal', 3)
on conflict (id) do update set title = excluded.title, subtitle = excluded.subtitle, image_url = excluded.image_url, link_type = excluded.link_type, link_id = excluded.link_id, active = true;
