-- Own 4-digit phone OTP (used by the "otp" Edge Function with the service role only)
create table if not exists public.phone_otps (
  phone text primary key,
  code_hash text,
  expires_at timestamptz,
  attempts int not null default 0,
  window_start timestamptz not null default now(),
  win_count int not null default 0,
  day_start timestamptz not null default now(),
  day_count int not null default 0
);
alter table public.phone_otps enable row level security;
revoke all on public.phone_otps from anon, authenticated;
