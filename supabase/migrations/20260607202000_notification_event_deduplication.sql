create table if not exists public.notification_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  event_key text not null,
  created_at timestamptz not null default now(),
  unique (order_id, event_key)
);

alter table public.notification_events enable row level security;
revoke all on public.notification_events from anon, authenticated;
