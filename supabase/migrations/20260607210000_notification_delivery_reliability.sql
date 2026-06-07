alter table public.app_settings
  add column if not exists order_status_notifications boolean not null default true;

update public.app_settings
set new_order_notifications = coalesce(new_order_notifications, true),
    order_status_notifications = coalesce(order_status_notifications, true)
where id = 'main';

update public.device_tokens as token
set role = profile.role,
    updated_at = now()
from public.profiles as profile
where token.user_id = profile.id and token.role <> profile.role;

create or replace function public.register_device_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
begin
  if auth.uid() is null or trim(p_token) = '' then
    raise exception 'A signed-in user and token are required.';
  end if;

  select role into actor_role
  from public.profiles
  where id = auth.uid() and active = true;

  if actor_role is null then raise exception 'Active profile required.'; end if;

  insert into public.device_tokens (user_id, role, token, platform, is_active, updated_at)
  values (auth.uid(), actor_role, p_token, coalesce(nullif(trim(p_platform), ''), 'android'), true, now())
  on conflict (token) do update set
    user_id = excluded.user_id,
    role = excluded.role,
    platform = excluded.platform,
    is_active = true,
    updated_at = now();
end;
$$;

revoke execute on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;
