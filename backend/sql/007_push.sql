-- Push notifications: device tokens + DB triggers that call the send-push Edge Function.
-- NOTE: the real shared secret is NOT stored in this public repo. When applying, replace
-- <PUSH_HOOK_SECRET> with the value also saved as the Edge Function secret PUSH_HOOK_SECRET.
create extension if not exists pg_net with schema extensions;

create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens(user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

create or replace function public.save_push_token(p_token text, p_platform text default 'android')
returns void language sql security definer set search_path = public as $$
  insert into push_tokens(token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), now())
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
$$;
create or replace function public.drop_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from push_tokens where token = p_token and user_id = auth.uid();
$$;
revoke execute on function public.save_push_token(text, text) from public, anon;
revoke execute on function public.drop_push_token(text) from public, anon;
grant execute on function public.save_push_token(text, text) to authenticated;
grant execute on function public.drop_push_token(text) to authenticated;

select vault.create_secret('<PUSH_HOOK_SECRET>', 'push_hook_secret', 'DB trigger -> send-push edge function');

create or replace function public.notify_push() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_hook_secret' limit 1;
  if v_secret is null then return new; end if;
  perform net.http_post(
    url := 'https://pboelnbjgyllqqlkqaqm.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    body := jsonb_build_object('table', TG_TABLE_NAME, 'op', TG_OP,
              'record', to_jsonb(new) - 'delivery_location',
              'old', case when TG_OP = 'UPDATE' then to_jsonb(old) - 'delivery_location' else null end),
    timeout_milliseconds := 4000);
  return new;
exception when others then
  return new;   -- a push problem must never block an order
end $$;
revoke execute on function public.notify_push() from public, anon, authenticated;

drop trigger if exists push_offer_new on public.order_offers;
create trigger push_offer_new after insert on public.order_offers
  for each row execute function public.notify_push();
drop trigger if exists push_order_new on public.orders;
create trigger push_order_new after insert on public.orders
  for each row execute function public.notify_push();
drop trigger if exists push_order_status on public.orders;
create trigger push_order_status after update of status on public.orders
  for each row when (old.status is distinct from new.status) execute function public.notify_push();
