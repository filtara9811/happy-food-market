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

-- place_order now takes the coins the customer wants to use (server caps it)
drop function if exists public.place_order(jsonb, double precision, double precision, text);
create or replace function public.place_order(p_items jsonb, p_lat double precision, p_lng double precision, p_address text, p_coins int default 0)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_order uuid; v_total numeric := 0; it jsonb; v_price numeric; v_store text; v_n int; v_bal int; v_use int := 0;
begin
  if setting('dispatch_mode')::text <> '"rider_stock"' then
    raise exception 'dispatch_mode % not built yet', setting('dispatch_mode');
  end if;
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

-- honest numbers for the store strip: orders today and share of happy ratings
create or replace function public.store_stats(p_store text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'today', (select count(*) from orders where store = p_store and created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'rated', (select count(*) from order_ratings r join orders o on o.id = r.order_id where o.store = p_store),
    'happy', (select count(*) from order_ratings r join orders o on o.id = r.order_id where o.store = p_store and r.mood = 'happy'));
$$;
grant execute on function public.store_stats(text) to anon, authenticated;
