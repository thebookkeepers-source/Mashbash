revoke execute on function public.place_order(text, text, text, integer, jsonb) from public, anon;
revoke execute on function public.update_order_status(uuid, text) from public, anon;
revoke execute on function public.assign_order_rider(uuid, uuid) from public, anon;
revoke execute on function public.set_rider_availability(boolean) from public, anon;
revoke execute on function public.register_device_token(text, text) from public, anon;
revoke execute on function public.deactivate_device_token(text) from public, anon;
revoke execute on function public.handle_new_user() from public;
revoke execute on function public.enforce_configured_delivery_fee() from public;
revoke execute on function public.prevent_menu_hard_delete() from public;

grant execute on function public.place_order(text, text, text, integer, jsonb) to authenticated;
grant execute on function public.update_order_status(uuid, text) to authenticated;
grant execute on function public.assign_order_rider(uuid, uuid) to authenticated;
grant execute on function public.set_rider_availability(boolean) to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.deactivate_device_token(text) to authenticated;

drop policy if exists "users read own device tokens" on public.device_tokens;
drop policy if exists "users update own device tokens" on public.device_tokens;
drop policy if exists "users delete own device tokens" on public.device_tokens;
create policy "users read own device tokens" on public.device_tokens for select to authenticated
using (user_id = (select auth.uid()));
create policy "users update own device tokens" on public.device_tokens for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "users delete own device tokens" on public.device_tokens for delete to authenticated
using (user_id = (select auth.uid()));

create index if not exists order_items_product_id_idx on public.order_items(product_id);
create index if not exists order_items_deal_id_idx on public.order_items(deal_id);
