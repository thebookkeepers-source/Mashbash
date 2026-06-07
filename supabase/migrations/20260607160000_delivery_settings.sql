create table if not exists public.app_settings (
  id text primary key,
  delivery_fee integer not null default 120 check (delivery_fee between 0 and 10000),
  updated_at timestamptz not null default now()
);

insert into public.app_settings (id, delivery_fee)
values ('main', 120)
on conflict (id) do nothing;

alter table public.app_settings enable row level security;

create policy "public read app settings" on public.app_settings
for select to anon, authenticated
using (id = 'main');

create policy "owners manage app settings" on public.app_settings
for all to authenticated
using (public.current_role() = 'owner')
with check (public.current_role() = 'owner');

create or replace function public.enforce_configured_delivery_fee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.delivery_fee := coalesce((select delivery_fee from public.app_settings where id = 'main'), 120);
  return new;
end;
$$;

drop trigger if exists enforce_configured_delivery_fee_before_insert on public.orders;
create trigger enforce_configured_delivery_fee_before_insert
before insert on public.orders
for each row execute procedure public.enforce_configured_delivery_fee();
