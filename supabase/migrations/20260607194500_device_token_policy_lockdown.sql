drop policy if exists "users update own device tokens" on public.device_tokens;
drop policy if exists "users delete own device tokens" on public.device_tokens;

revoke insert, update, delete on public.device_tokens from anon, authenticated;
