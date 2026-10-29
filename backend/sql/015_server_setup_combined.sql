-- Happy Food — server setup (run once in Supabase → SQL Editor → New query → paste → Run)
-- Adds: VIP coins, honest store numbers, service zones + waitlist, API-key vault, and the final place_order.

begin;
-- VIP coins: 5% of every delivered order comes back as coins (1 coin = ₹1);
-- up to 20% of a new order can be paid with coins. Cancelled orders give the coins back.
create table if not exists coin_ledger (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta int not null,
  reason text not null check (reason in ('earn','redeem','refund','bonus')),
  order_id uuid references orders(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists coin_ledger_once on coin_ledger(order_id, reason) where order_id is not null;
create index if not exists coin_ledger_user on coin_ledger(user_id, created_at desc);
alter table coin_ledger enable row level security;
drop policy if exists coin_ledger_own on coin_ledger;
create policy coin_ledger_own on coin_ledger for select using (user_id = auth.uid());

alter table orders add column if not exists coins_used int not null default 0;

create or replace function public.my_coins()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'balance', coalesce((select sum(delta) from coin_ledger where user_id = auth.uid()), 0),
    'history', coalesce((select jsonb_agg(jsonb_build_object('delta', delta, 'reason', reason, 'at', created_at) order by created_at desc)
                           from (select * from coin_ledger where user_id = auth.uid() order by created_at desc limit 15) h), '[]'::jsonb));
$$;
grant execute on function public.my_coins() to authenticated;

create or replace function public.coins_on_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'delivered' and old.status is distinct from 'delivered' and new.customer_id is not null then
    insert into coin_ledger(user_id, delta, reason, order_id)
    values (new.customer_id, greatest(1, floor((new.total + new.coins_used) * 0.05))::int, 'earn', new.id)
    on conflict do nothing;
  elsif new.status in ('cancelled','no_rider') and old.status is distinct from new.status and new.coins_used > 0 then
    insert into coin_ledger(user_id, delta, reason, order_id)
    values (new.customer_id, new.coins_used, 'refund', new.id)
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists orders_coins on orders;
create trigger orders_coins after update of status on orders for each row execute function coins_on_status();


-- honest numbers for the store strip: orders today and share of happy ratings
create or replace function public.store_stats(p_store text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'today', (select count(*) from orders where store = p_store and created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'rated', (select count(*) from order_ratings r join orders o on o.id = r.order_id where o.store = p_store),
    'happy', (select count(*) from order_ratings r join orders o on o.id = r.order_id where o.store = p_store and r.mood = 'happy'));
$$;
grant execute on function public.store_stats(text) to anon, authenticated;

-- Service zones (city / area where orders are allowed), waitlist from outside, and API keys kept only on the server.
create table if not exists service_zones (
  id text primary key,
  city text not null,
  name text not null,
  parent text references service_zones(id) on delete cascade,
  center_lat double precision not null,
  center_lng double precision not null,
  radius_m int not null default 2500,
  status text not null default 'soon' check (status in ('live','soon','off')),
  stores text[] not null default '{food}',
  min_order int not null default 99,
  fee int not null default 25,
  free_above int not null default 199,
  open_from time not null default '07:00',
  open_to time not null default '23:00',
  closed_dow int[] not null default '{}',
  paused boolean not null default false,
  pause_msg text,
  rain_mode boolean not null default false,
  rain_fee int not null default 10,
  updated_at timestamptz not null default now()
);
alter table service_zones enable row level security;
drop policy if exists zones_read on service_zones;
create policy zones_read on service_zones for select using (true);

create table if not exists zone_waitlist (
  id bigserial primary key,
  user_id uuid default auth.uid(),
  phone text,
  lat double precision not null,
  lng double precision not null,
  area text,
  created_at timestamptz not null default now()
);
alter table zone_waitlist enable row level security;
drop policy if exists waitlist_insert on zone_waitlist;
create policy waitlist_insert on zone_waitlist for insert with check (user_id is null or user_id = auth.uid());

-- which live zone covers this point (main zones only); null when outside everywhere
create or replace function public.zone_at(p_lat double precision, p_lng double precision)
returns service_zones language sql stable security definer set search_path = public as $$
  select z.* from service_zones z
   where z.parent is null and z.status <> 'off'
     and st_dwithin(st_setsrid(st_makepoint(z.center_lng, z.center_lat), 4326)::geography, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, z.radius_m)
   order by (z.status = 'live') desc limit 1;
$$;

create or replace function public.zone_check(p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare z service_zones; t time := (now() at time zone 'Asia/Kolkata')::time; d int := extract(dow from now() at time zone 'Asia/Kolkata');
begin
  if not exists (select 1 from service_zones) then return jsonb_build_object('ok', true, 'reason', 'no_zones'); end if;
  z := zone_at(p_lat, p_lng);
  if z.id is null then return jsonb_build_object('ok', false, 'reason', 'outside'); end if;
  if z.status = 'soon' then return jsonb_build_object('ok', false, 'reason', 'soon', 'zone', z.name); end if;
  if z.paused then return jsonb_build_object('ok', false, 'reason', 'paused', 'zone', z.name, 'msg', z.pause_msg); end if;
  if d = any(z.closed_dow) then return jsonb_build_object('ok', false, 'reason', 'closed_day', 'zone', z.name); end if;
  if t < z.open_from or t > z.open_to then return jsonb_build_object('ok', false, 'reason', 'closed_time', 'zone', z.name, 'from', z.open_from, 'to', z.open_to); end if;
  return jsonb_build_object('ok', true, 'zone', z.name, 'id', z.id, 'stores', z.stores, 'min_order', z.min_order, 'fee', z.fee + case when z.rain_mode then z.rain_fee else 0 end, 'free_above', z.free_above);
end $$;
grant execute on function public.zone_check(double precision, double precision) to anon, authenticated;

create or replace function public.admin_upsert_zone(p jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  insert into service_zones(id, city, name, parent, center_lat, center_lng, radius_m, status, stores, min_order, fee, free_above, open_from, open_to, closed_dow, paused, pause_msg, rain_mode, rain_fee, updated_at)
  values (p->>'id', p->>'city', p->>'name', nullif(p->>'parent',''), (p->>'lat')::float8, (p->>'lng')::float8, (p->>'radius_m')::int, p->>'status',
          coalesce((select array_agg(x) from jsonb_array_elements_text(p->'stores') x), '{food}'), (p->>'min_order')::int, (p->>'fee')::int, (p->>'free_above')::int,
          (p->>'open_from')::time, (p->>'open_to')::time, coalesce((select array_agg(x::int) from jsonb_array_elements_text(p->'closed_dow') x), '{}'),
          coalesce((p->>'paused')::boolean, false), p->>'pause_msg', coalesce((p->>'rain_mode')::boolean, false), coalesce((p->>'rain_fee')::int, 10), now())
  on conflict (id) do update set city = excluded.city, name = excluded.name, parent = excluded.parent, center_lat = excluded.center_lat, center_lng = excluded.center_lng,
    radius_m = excluded.radius_m, status = excluded.status, stores = excluded.stores, min_order = excluded.min_order, fee = excluded.fee, free_above = excluded.free_above,
    open_from = excluded.open_from, open_to = excluded.open_to, closed_dow = excluded.closed_dow, paused = excluded.paused, pause_msg = excluded.pause_msg,
    rain_mode = excluded.rain_mode, rain_fee = excluded.rain_fee, updated_at = now();
end $$;

create or replace function public.admin_waitlist()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('lat', round(lat::numeric, 3), 'lng', round(lng::numeric, 3), 'n', n)) from
    (select round(lat::numeric, 3) lat, round(lng::numeric, 3) lng, count(*) n from zone_waitlist group by 1, 2 order by 3 desc limit 100) t), '[]'::jsonb);
end $$;


-- API keys typed in the admin panel: write-only, never readable by any app
create table if not exists app_secrets (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table app_secrets enable row level security;   -- no policies: apps cannot read; server functions use the service role

create or replace function public.admin_set_secret(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  if p_key !~ '^[a-z0-9_.]{2,80}$' then raise exception 'bad key'; end if;
  if coalesce(p_value, '') = '' then delete from app_secrets where key = p_key; return; end if;
  insert into app_secrets(key, value, updated_at, updated_by) values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
end $$;

create or replace function public.admin_secret_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  return coalesce((select jsonb_object_agg(key, jsonb_build_object('set', true, 'at', updated_at, 'tail', right(value, 4))) from app_secrets), '{}'::jsonb);
end $$;
revoke all on function public.admin_set_secret(text, text) from anon;
revoke all on function public.admin_secret_status() from anon;

-- ===== one place_order: one store per order + zone check + coins =====
drop function if exists public.place_order(jsonb, double precision, double precision, text);
drop function if exists public.place_order(jsonb, double precision, double precision, text, int);
create function public.place_order(p_items jsonb, p_lat double precision, p_lng double precision, p_address text, p_coins int default 0)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_order uuid; v_total numeric := 0; it jsonb; v_price numeric; v_store text; v_n int; zc jsonb; v_bal int; v_use int := 0;
begin
  if setting('dispatch_mode')::text <> '"rider_stock"' then
    raise exception 'dispatch_mode % not built yet', setting('dispatch_mode');
  end if;
  zc := zone_check(p_lat, p_lng);
  if not (zc->>'ok')::boolean then raise exception 'outside_zone:%', zc->>'reason'; end if;
  select count(distinct p.store), min(p.store) into v_n, v_store
    from jsonb_array_elements(p_items) e join products p on p.id = (e->>'product_id')::uuid;
  if v_n > 1 then raise exception 'one order can hold items of one store only'; end if;
  insert into orders(customer_id, delivery_location, delivery_address, store)
  values (auth.uid(), st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, p_address, coalesce(v_store, 'food'))
  returning id into v_order;
  insert into order_secrets(order_id, otp) values (v_order, lpad((floor(random()*10000))::int::text, 4, '0'));
  for it in select * from jsonb_array_elements(p_items) loop
    select price into v_price from products where id = (it->>'product_id')::uuid and is_active;
    if v_price is null then raise exception 'product not available'; end if;
    insert into order_items(order_id, product_id, qty, price) values (v_order, (it->>'product_id')::uuid, (it->>'qty')::int, v_price);
    v_total := v_total + v_price * (it->>'qty')::int;
  end loop;
  if coalesce(p_coins, 0) > 0 then
    perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
    select coalesce(sum(delta), 0) into v_bal from coin_ledger where user_id = auth.uid();
    v_use := least(p_coins, v_bal, floor(v_total * 0.2))::int;
    if v_use > 0 then insert into coin_ledger(user_id, delta, reason, order_id) values (auth.uid(), -v_use, 'redeem', v_order); end if;
  end if;
  update orders set total = v_total - v_use, coins_used = v_use where id = v_order;
  perform dispatch_next(v_order);
  return v_order;
end $$;
grant execute on function public.place_order(jsonb, double precision, double precision, text, int) to authenticated;

commit;
