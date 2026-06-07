create index if not exists orders_status_created_at_idx
  on public.orders(status, created_at desc);
create index if not exists orders_created_at_idx
  on public.orders(created_at desc);
create index if not exists orders_assigned_rider_status_created_at_idx
  on public.orders(assigned_rider_id, status, created_at desc);
create index if not exists orders_accepted_by_idx
  on public.orders(accepted_by);
create index if not exists products_category_availability_sort_idx
  on public.products(category_id, available, sort_order)
  where archived_at is null;
create index if not exists products_availability_sort_idx
  on public.products(available, sort_order)
  where archived_at is null;
create index if not exists categories_customer_sort_idx
  on public.categories(active, sort_order)
  where archived_at is null;
create index if not exists deals_active_idx
  on public.deals(active)
  where archived_at is null;
create index if not exists home_slides_active_sort_idx
  on public.home_slides(active, sort_order);
create index if not exists cart_items_product_id_idx
  on public.cart_items(product_id);
create index if not exists order_status_history_changed_by_idx
  on public.order_status_history(changed_by);

revoke execute on function public.current_role() from public, anon;
revoke execute on function public.has_permission(text) from public, anon;
grant execute on function public.current_role() to authenticated, service_role;
grant execute on function public.has_permission(text) to authenticated, service_role;

revoke all on function public.rls_auto_enable() from public, anon, authenticated;
revoke all on function public.enforce_counter_permissions() from public, anon, authenticated;
revoke all on function public.protect_profile_access() from public, anon, authenticated;

drop policy if exists "read active categories" on public.categories;
create policy "anonymous read active categories" on public.categories
for select to anon
using (active = true and archived_at is null);
create policy "authenticated read active categories" on public.categories
for select to authenticated
using (active = true and archived_at is null);

drop policy if exists "read active products" on public.products;
create policy "anonymous read active products" on public.products
for select to anon
using (
  available = true
  and archived_at is null
  and exists (
    select 1 from public.categories
    where categories.id = products.category_id
      and categories.active = true
      and categories.archived_at is null
  )
);
create policy "authenticated read active products" on public.products
for select to authenticated
using (
  available = true
  and archived_at is null
  and exists (
    select 1 from public.categories
    where categories.id = products.category_id
      and categories.active = true
      and categories.archived_at is null
  )
);

drop policy if exists "read active deals" on public.deals;
create policy "anonymous read active deals" on public.deals
for select to anon
using (active = true and archived_at is null);
create policy "authenticated read active deals" on public.deals
for select to authenticated
using (active = true and archived_at is null);

drop policy if exists "read active home slides" on public.home_slides;
create policy "anonymous read active home slides" on public.home_slides
for select to anon
using (active = true);
create policy "authenticated read active home slides" on public.home_slides
for select to authenticated
using (active = true);

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles
for select to authenticated
using (id = (select auth.uid()));

drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists "customers read own orders" on public.orders;
create policy "customers read own orders" on public.orders
for select to authenticated
using (customer_id = (select auth.uid()));

drop policy if exists "staff read own permissions" on public.staff_permissions;
create policy "staff read own permissions" on public.staff_permissions
for select to authenticated
using (profile_id = (select auth.uid()));

drop policy if exists "public product images" on storage.objects;
drop policy if exists "menu staff read product images" on storage.objects;
create policy "menu staff read product images" on storage.objects
for select to authenticated
using (bucket_id = 'product-images' and (select public.has_permission('manage_menu')));
