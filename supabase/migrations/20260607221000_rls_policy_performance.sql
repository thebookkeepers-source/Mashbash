drop policy if exists "customers manage own cart" on public.carts;
create policy "customers manage own cart" on public.carts
for all to authenticated
using (customer_id = (select auth.uid()))
with check (customer_id = (select auth.uid()));

drop policy if exists "customers manage own cart items" on public.cart_items;
create policy "customers manage own cart items" on public.cart_items
for all to authenticated
using (
  exists (
    select 1 from public.carts
    where carts.id = cart_items.cart_id
      and carts.customer_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.carts
    where carts.id = cart_items.cart_id
      and carts.customer_id = (select auth.uid())
  )
);

drop policy if exists "customers read own order items" on public.order_items;
create policy "customers read own order items" on public.order_items
for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_items.order_id
      and orders.customer_id = (select auth.uid())
  )
);

drop policy if exists "staff read permitted orders" on public.orders;
create policy "staff read permitted orders" on public.orders
for select to authenticated
using (
  (select public.current_role()) = 'owner'
  or (
    (select public.current_role()) in ('manager', 'counter')
    and ((select public.has_permission('view_orders')) or (select public.has_permission('view_reports')))
  )
  or ((select public.current_role()) = 'rider' and assigned_rider_id = (select auth.uid()))
);

drop policy if exists "staff read permitted order items" on public.order_items;
create policy "staff read permitted order items" on public.order_items
for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_items.order_id
      and (
        (select public.current_role()) = 'owner'
        or (
          (select public.current_role()) in ('manager', 'counter')
          and ((select public.has_permission('view_orders')) or (select public.has_permission('view_reports')))
        )
        or ((select public.current_role()) = 'rider' and orders.assigned_rider_id = (select auth.uid()))
      )
  )
);

drop policy if exists "customers read own status history" on public.order_status_history;
create policy "customers read own status history" on public.order_status_history
for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_status_history.order_id
      and orders.customer_id = (select auth.uid())
  )
);

drop policy if exists "staff read permitted status history" on public.order_status_history;
create policy "staff read permitted status history" on public.order_status_history
for select to authenticated
using (
  exists (
    select 1 from public.orders
    where orders.id = order_status_history.order_id
      and (
        (select public.current_role()) = 'owner'
        or (
          (select public.current_role()) in ('manager', 'counter')
          and (select public.has_permission('view_orders'))
        )
        or ((select public.current_role()) = 'rider' and orders.assigned_rider_id = (select auth.uid()))
      )
  )
);
