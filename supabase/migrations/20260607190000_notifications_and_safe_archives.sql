alter table public.categories add column if not exists archived_at timestamptz;
alter table public.products add column if not exists archived_at timestamptz;
alter table public.deals add column if not exists archived_at timestamptz;

alter table public.order_items add column if not exists deal_id text references public.deals(id) on delete set null;
alter table public.order_items add column if not exists item_type text not null default 'product' check (item_type in ('product', 'deal'));
alter table public.order_items add column if not exists image_url text not null default '';
alter table public.order_items add column if not exists category_name text not null default 'Deals / Other';
alter table public.order_items add column if not exists line_total integer not null default 0 check (line_total >= 0);
update public.order_items set line_total = price * quantity where line_total = 0;
update public.order_items as item
set image_url = product.image_url, category_name = category.name, item_type = 'product'
from public.products as product
join public.categories as category on category.id = product.category_id
where item.product_id = product.id;
update public.order_items as item
set deal_id = deal.id, image_url = deal.image_url, category_name = 'Deals', item_type = 'deal'
from public.deals as deal
where item.product_id is null and item.name = deal.name;

alter table public.app_settings add column if not exists new_order_notifications boolean not null default true;
alter table public.app_settings add column if not exists pending_alert_minutes integer not null default 15 check (pending_alert_minutes between 1 and 180);
alter table public.app_settings add column if not exists daily_sales_summary boolean not null default false;

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('customer', 'owner', 'manager', 'counter', 'rider')),
  token text not null unique,
  platform text not null default 'android',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_active_idx on public.device_tokens(user_id, is_active);
create index if not exists device_tokens_role_active_idx on public.device_tokens(role, is_active);
create index if not exists categories_archived_at_idx on public.categories(archived_at);
create index if not exists products_archived_at_idx on public.products(archived_at);
create index if not exists deals_archived_at_idx on public.deals(archived_at);

alter table public.device_tokens enable row level security;
create policy "users read own device tokens" on public.device_tokens for select to authenticated
using (user_id = auth.uid());
create policy "users update own device tokens" on public.device_tokens for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users delete own device tokens" on public.device_tokens for delete to authenticated
using (user_id = auth.uid());

create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
begin
  if auth.uid() is null or trim(p_token) = '' then raise exception 'A signed-in user and token are required.'; end if;
  select role into actor_role from public.profiles where id = auth.uid() and active = true;
  if actor_role is null then raise exception 'Active profile required.'; end if;

  insert into public.device_tokens (user_id, role, token, platform, is_active)
  values (auth.uid(), actor_role, p_token, coalesce(nullif(trim(p_platform), ''), 'android'), true)
  on conflict (token) do update set
    user_id = excluded.user_id,
    role = excluded.role,
    platform = excluded.platform,
    is_active = true,
    updated_at = now();
end;
$$;

create or replace function public.deactivate_device_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  update public.device_tokens
  set is_active = false, updated_at = now()
  where user_id = auth.uid() and token = p_token
$$;

drop policy if exists "read active categories" on public.categories;
drop policy if exists "read active products" on public.products;
drop policy if exists "read active deals" on public.deals;

create policy "read active categories" on public.categories for select to anon, authenticated
using ((active = true and archived_at is null) or public.has_permission('manage_menu'));
create policy "read active products" on public.products for select to anon, authenticated
using (
  (
    available = true
    and archived_at is null
    and exists (
      select 1 from public.categories
      where categories.id = products.category_id and categories.active = true and categories.archived_at is null
    )
  )
  or public.has_permission('manage_menu')
);
create policy "read active deals" on public.deals for select to anon, authenticated
using ((active = true and archived_at is null) or public.has_permission('manage_deals'));

create or replace function public.prevent_menu_hard_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Menu records must be archived instead of deleted.';
end;
$$;

drop trigger if exists prevent_category_hard_delete on public.categories;
drop trigger if exists prevent_product_hard_delete on public.products;
drop trigger if exists prevent_deal_hard_delete on public.deals;
create trigger prevent_category_hard_delete before delete on public.categories for each row execute procedure public.prevent_menu_hard_delete();
create trigger prevent_product_hard_delete before delete on public.products for each row execute procedure public.prevent_menu_hard_delete();
create trigger prevent_deal_hard_delete before delete on public.deals for each row execute procedure public.prevent_menu_hard_delete();

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
    from requested
    join public.products on products.id = requested.product_id and products.available = true and products.archived_at is null
    join public.categories on categories.id = products.category_id and categories.active = true and categories.archived_at is null
    union all
    select requested.product_id, requested.quantity, deals.deal_price
    from requested join public.deals on requested.product_id = 'deal:' || deals.id and deals.active = true and deals.archived_at is null
  )
  select coalesce(sum(price * quantity), 0)::integer into order_subtotal from priced;

  if order_subtotal <= 0 then raise exception 'No available products were selected.'; end if;

  insert into public.orders (customer_id, customer_name, phone, address, payment_method, subtotal, delivery_fee)
  values (auth.uid(), customer_name, p_phone, p_address, p_payment_method, order_subtotal, greatest(p_delivery_fee, 0))
  returning id into new_order_id;

  insert into public.order_items (order_id, product_id, item_type, name, price, quantity, image_url, category_name, line_total)
  select new_order_id, products.id, 'product', products.name, products.price, requested.quantity, products.image_url, categories.name, products.price * requested.quantity
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.products on products.id = requested.product_id and products.available = true and products.archived_at is null
  join public.categories on categories.id = products.category_id and categories.active = true and categories.archived_at is null
  where requested.quantity > 0;

  insert into public.order_items (order_id, deal_id, item_type, name, price, quantity, image_url, category_name, line_total)
  select new_order_id, deals.id, 'deal', deals.name, deals.deal_price, requested.quantity, deals.image_url, 'Deals', deals.deal_price * requested.quantity
  from jsonb_to_recordset(p_items) as requested(product_id text, quantity integer)
  join public.deals on requested.product_id = 'deal:' || deals.id and deals.active = true and deals.archived_at is null
  where requested.quantity > 0;

  insert into public.order_status_history (order_id, status, changed_by) values (new_order_id, 'received', auth.uid());
  return new_order_id;
end;
$$;

grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.deactivate_device_token(text) to authenticated;
grant execute on function public.place_order(text, text, text, integer, jsonb) to authenticated;
