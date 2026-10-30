-- 025: app orders can go to a SHOP. Shop accepts → packs → "ready" (pickup code / QR on the slip) →
-- a rider is found → rider scans the QR at the shop → only then the order is picked up (on the way).
alter table orders add column if not exists route text not null default 'rider';
alter table orders add column if not exists vendor_id uuid references vendors(id);
alter table orders add column if not exists pickup_code text;
alter table orders add column if not exists ready_at timestamptz;
alter table shop_sales add column if not exists order_id uuid;
alter table shop_sales add column if not exists picked_at timestamptz;
alter table shop_sales add column if not exists customer_address text;
create index if not exists shop_sales_order_idx on shop_sales(order_id);
insert into app_settings(key, value) values ('shop_route_enabled', 'true'::jsonb) on conflict (key) do nothing;
insert into app_settings(key, value) values ('shop_accept_seconds', '120'::jsonb) on conflict (key) do nothing;
-- testing: shops that never set their map location still get orders (turn off before go-live)
insert into app_settings(key, value) values ('shop_route_ignore_distance', 'true'::jsonb) on conflict (key) do nothing;

create or replace function vendor_set_location(p_lat double precision, p_lng double precision, p_text text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update vendors set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, location_text = coalesce(p_text, location_text) where owner_id = auth.uid();
end $$;

-- pick where a new order goes: a rider who carries everything, else the nearest open shop that has it, else any rider
create or replace function route_order(p_order_id uuid) returns text language plpgsql security definer set search_path = public as $$
declare o orders; v uuid; rider_ok boolean; ign boolean := coalesce(setting('shop_route_ignore_distance')::text, 'false') = 'true';
begin
  select * into o from orders where id = p_order_id for update;
  if o.id is null or o.status <> 'searching' then return 'skip'; end if;
  select exists (select 1 from riders r
     where r.id is distinct from o.customer_id and r.is_online and r.approved and not r.suspended and r.location is not null
       and r.location_updated_at > now() - make_interval(mins => coalesce((setting('location_fresh_minutes')::text)::int, 15))
       and st_dwithin(r.location, o.delivery_location, (setting('search_radius_km')::text::numeric) * 1000)
       and not exists (select 1 from orders x where x.rider_id = r.id and x.status in ('accepted','on_the_way'))
       and not exists (select 1 from order_items oi where oi.order_id = o.id
                        and not exists (select 1 from rider_stock s where s.rider_id = r.id and s.product_id = oi.product_id and s.qty - s.reserved >= oi.qty))) into rider_ok;
  if not rider_ok and coalesce(setting('shop_route_enabled')::text, 'true') = 'true' then
    select vd.id into v from vendors vd
     where vd.approved and not vd.suspended and vd.is_open and coalesce((vd.perms->>'app_orders')::boolean, true)
       and vd.owner_id is distinct from o.customer_id
       and (vd.store = o.store or (vd.multi_cat and o.store = any(vd.extra_stores)))
       and ((vd.location is not null and st_dwithin(vd.location, o.delivery_location, greatest(vd.radius_km, 0.5) * 1000)) or (ign and vd.location is null))
       and not exists (select 1 from shop_sales x where x.order_id = o.id and x.vendor_id = vd.id)
       and not exists (select 1 from order_items oi where oi.order_id = o.id
                        and not exists (select 1 from vendor_stock s where s.vendor_id = vd.id and s.product_id = oi.product_id and s.active and s.qty >= oi.qty))
     order by vd.location is null, st_distance(vd.location, o.delivery_location) nulls last
     limit 1;
    if v is not null then
      update orders set route = 'shop', vendor_id = v where id = o.id;
      insert into shop_sales(vendor_id, bill_no, items, total, pay_mode, customer_phone, customer_name, customer_address, source, status, order_id)
      select v, coalesce((select max(bill_no) from shop_sales where vendor_id = v), 0) + 1,
             (select coalesce(jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name, 'name_hi', pr.name_hi, 'qty', oi.qty, 'price', oi.price, 'image_url', pr.image_url)), '[]'::jsonb)
                from order_items oi join products pr on pr.id = oi.product_id where oi.order_id = o.id),
             o.total, 'cash', p.phone, p.full_name, o.delivery_address, 'app', 'new', o.id
        from profiles p where p.id = o.customer_id;
      return 'shop';
    end if;
  end if;
  update orders set route = 'rider', vendor_id = null where id = o.id;
  perform dispatch_next(o.id);
  return 'rider';
end $$;

-- shop actions on an app order: accept / reject / ready (packed, call a rider)
create or replace function vendor_order_act(p_sale uuid, p_act text) returns jsonb language plpgsql security definer set search_path = public as $$
declare s shop_sales; o orders; code text;
begin
  select * into s from shop_sales where id = p_sale and vendor_id = my_vendor_id() for update;
  if s.id is null or s.order_id is null then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  select * into o from orders where id = s.order_id for update;
  if o.status in ('cancelled', 'delivered') then
    update shop_sales set status = case when o.status = 'delivered' then 'done' else 'cancelled' end where id = s.id;
    return jsonb_build_object('ok', false, 'code', 'gone');
  end if;
  if p_act = 'accept' then
    if s.status <> 'new' then return jsonb_build_object('ok', false, 'code', 'not_new'); end if;
    update vendor_stock vs set qty = greatest(0, vs.qty - oi.qty), updated_at = now()
      from order_items oi where oi.order_id = o.id and vs.vendor_id = s.vendor_id and vs.product_id = oi.product_id;
    update shop_sales set status = 'packing', accepted_at = now() where id = s.id;
    return jsonb_build_object('ok', true, 'status', 'packing');
  elsif p_act = 'reject' then
    if s.status not in ('new', 'packing') then return jsonb_build_object('ok', false, 'code', 'too_late'); end if;
    if s.status = 'packing' then
      update vendor_stock vs set qty = vs.qty + oi.qty, updated_at = now()
        from order_items oi where oi.order_id = o.id and vs.vendor_id = s.vendor_id and vs.product_id = oi.product_id;
    end if;
    update shop_sales set status = 'cancelled' where id = s.id;
    update orders set route = 'rider', vendor_id = null where id = o.id;
    perform route_order(o.id);
    return jsonb_build_object('ok', true, 'status', 'cancelled');
  elsif p_act = 'ready' then
    if s.status not in ('packing', 'ready') then return jsonb_build_object('ok', false, 'code', 'accept_first'); end if;
    code := coalesce(o.pickup_code, lpad((floor(random() * 1000000))::int::text, 6, '0'));
    update orders set pickup_code = code, ready_at = coalesce(ready_at, now()) where id = o.id;
    update shop_sales set status = 'ready', packed_at = coalesce(packed_at, now()) where id = s.id;
    if o.rider_id is null and o.status = 'searching' then perform dispatch_next(o.id); end if;
    return jsonb_build_object('ok', true, 'status', 'ready', 'code', code);
  end if;
  return jsonb_build_object('ok', false, 'code', 'bad_action');
end $$;

-- shops that do not answer in time: the order moves on
create or replace function sweep_shop_orders() returns void language plpgsql security definer set search_path = public as $$
declare r record; secs int := coalesce((setting('shop_accept_seconds')::text)::int, 120);
begin
  for r in select s.id, s.order_id from shop_sales s join orders o on o.id = s.order_id
            where s.status = 'new' and s.source = 'app' and s.created_at < now() - make_interval(secs => secs) and o.status = 'searching' and o.vendor_id = s.vendor_id loop
    update shop_sales set status = 'cancelled' where id = r.id;
    update orders set route = 'rider', vendor_id = null where id = r.order_id;
    perform route_order(r.order_id);
  end loop;
end $$;

create or replace function sweep_expired_offers() returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select distinct order_id from order_offers where status = 'pending' and expires_at <= now() loop
    update order_offers set status = 'expired' where order_id = r.order_id and status = 'pending' and expires_at <= now();
    perform dispatch_next(r.order_id);
  end loop;
  perform sweep_shop_orders();
end $$;

-- riders: for shop orders the distance is to the shop, and nobody needs stock
create or replace function next_rider_for(p_order_id uuid) returns table(rider_id uuid, distance_m integer) language sql security definer set search_path = public as $$
  with o as (select o.*, case when o.route = 'shop' then coalesce(v.location, o.delivery_location) else o.delivery_location end as pt
               from orders o left join vendors v on v.id = o.vendor_id where o.id = p_order_id),
  cand as (
    select r.id, st_distance(r.location, o.pt)::int dist,
           (o.route = 'shop' or not exists (select 1 from order_items oi where oi.order_id = o.id
                        and not exists (select 1 from rider_stock s where s.rider_id = r.id and s.product_id = oi.product_id and s.qty - s.reserved >= oi.qty))) has_stock
      from o join riders r on true
     where r.id is distinct from o.customer_id
       and r.is_online and r.approved and not r.suspended and r.location is not null
       and r.location_updated_at > now() - make_interval(mins => coalesce((setting('location_fresh_minutes')::text)::int, 15))
       and st_dwithin(r.location, o.pt, (setting('search_radius_km')::text::numeric) * 1000)
       and not exists (select 1 from orders x where x.rider_id = r.id and x.status in ('accepted','on_the_way'))
       and not exists (select 1 from order_offers f where f.order_id = o.id and f.rider_id = r.id))
  select id, dist from cand
   where has_stock or coalesce(setting('allow_no_stock_riders')::text, 'false') = 'true'
   order by has_stock desc, dist
   limit 1
$$;

create or replace function respond_offer(p_offer_id uuid, p_accept boolean) returns text language plpgsql security definer set search_path = public as $$
declare o order_offers; ord orders; v_full boolean;
begin
  select * into o from order_offers where id = p_offer_id for update;
  if o.rider_id <> auth.uid() or o.status <> 'pending' then return 'invalid'; end if;
  select * into ord from orders where id = o.order_id for update;
  if o.expires_at <= now() or ord.status <> 'searching' then
    update order_offers set status = 'expired' where id = o.id; perform dispatch_next(o.order_id); return 'expired';
  end if;
  if not p_accept then
    update order_offers set status = 'rejected' where id = o.id; perform dispatch_next(o.order_id); return 'rejected';
  end if;
  if ord.route <> 'shop' then
    perform 1 from rider_stock s join order_items oi on oi.product_id = s.product_id
      where s.rider_id = o.rider_id and oi.order_id = o.order_id for update of s;
    v_full := not exists (select 1 from order_items oi where oi.order_id = o.order_id
               and not exists (select 1 from rider_stock s where s.rider_id = o.rider_id and s.product_id = oi.product_id and s.qty - s.reserved >= oi.qty));
    if not v_full and coalesce(setting('allow_no_stock_riders')::text, 'false') <> 'true' then
      update order_offers set status = 'expired' where id = o.id; perform dispatch_next(o.order_id); return 'stock_gone';
    end if;
    update rider_stock s set reserved = s.reserved + least(oi.qty, greatest(0, s.qty - s.reserved)), updated_at = now()
      from order_items oi where oi.order_id = o.order_id and s.rider_id = o.rider_id and s.product_id = oi.product_id;
  end if;
  update orders set status = 'accepted', rider_id = o.rider_id, accepted_at = now() where id = o.order_id;
  update order_offers set status = 'accepted' where id = o.id;
  return 'accepted';
end $$;

create or replace function release_rider_stock(p_order_id uuid, p_rider uuid) returns void language sql security definer set search_path = public as $$
  update rider_stock s set reserved = greatest(0, s.reserved - oi.qty), updated_at = now()
    from order_items oi where oi.order_id = p_order_id and s.rider_id = p_rider and s.product_id = oi.product_id
     and not exists (select 1 from orders x where x.id = p_order_id and x.route = 'shop');
$$;

-- shop orders cannot start "on the way" without the pickup scan
create or replace function start_delivery(p_order_id uuid) returns void language sql security definer set search_path = public as $$
  update orders set status = 'on_the_way'
   where id = p_order_id and rider_id = auth.uid() and status = 'accepted' and (route <> 'shop' or picked_at is not null);
$$;

create or replace function complete_delivery(p_order_id uuid, p_otp text) returns boolean language plpgsql security definer set search_path = public as $$
declare ord orders; v_otp text;
begin
  select * into ord from orders where id = p_order_id for update;
  select otp into v_otp from order_secrets where order_id = p_order_id;
  if ord.rider_id is distinct from auth.uid() or ord.status not in ('accepted','on_the_way') or v_otp is distinct from p_otp then return false; end if;
  if ord.route = 'shop' and ord.picked_at is null then return false; end if;
  if ord.route <> 'shop' then
    update rider_stock s set qty = greatest(0, s.qty - oi.qty), reserved = greatest(0, s.reserved - oi.qty), updated_at = now()
      from order_items oi where oi.order_id = ord.id and s.rider_id = ord.rider_id and s.product_id = oi.product_id;
  end if;
  update orders set status = 'delivered', delivered_at = now() where id = ord.id;
  return true;
end $$;

-- rider scans the QR on the shop slip (or types the 6-digit code)
create or replace function rider_pickup(p_order_id uuid, p_code text) returns jsonb language plpgsql security definer set search_path = public as $$
declare o orders; c text := regexp_replace(coalesce(p_code, ''), '\D', '', 'g');
begin
  select * into o from orders where id = p_order_id and rider_id = auth.uid() for update;
  if o.id is null or o.status not in ('accepted', 'on_the_way') then return jsonb_build_object('ok', false, 'code', 'not_active'); end if;
  if o.route <> 'shop' then return jsonb_build_object('ok', false, 'code', 'not_shop'); end if;
  if o.picked_at is not null then return jsonb_build_object('ok', true, 'already', true); end if;
  if o.ready_at is null or o.pickup_code is null then return jsonb_build_object('ok', false, 'code', 'not_ready'); end if;
  if right(c, 6) <> o.pickup_code then return jsonb_build_object('ok', false, 'code', 'wrong_code'); end if;
  update orders set picked_at = now(), status = 'on_the_way' where id = o.id;
  update shop_sales set picked_at = now() where order_id = o.id and status <> 'cancelled';
  return jsonb_build_object('ok', true);
end $$;

-- what the rider app needs to know about the shop for its offer / active order
create or replace function rider_shop_task() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'active', (select jsonb_build_object('order_id', o.id, 'route', o.route, 'ready', o.ready_at is not null, 'picked', o.picked_at is not null,
                 'shop', jsonb_build_object('name', v.shop_name, 'address', v.address, 'phone', p.phone, 'lat', st_y(v.location::geometry), 'lng', st_x(v.location::geometry)))
                 from orders o join vendors v on v.id = o.vendor_id left join profiles p on p.id = v.owner_id
                where o.rider_id = auth.uid() and o.status in ('accepted','on_the_way') and o.route = 'shop' limit 1),
    'offer', (select jsonb_build_object('order_id', o.id, 'shop', jsonb_build_object('name', v.shop_name, 'address', v.address))
                from order_offers f join orders o on o.id = f.order_id join vendors v on v.id = o.vendor_id
               where f.rider_id = auth.uid() and f.status = 'pending' and f.expires_at > now() and o.route = 'shop' limit 1))
$$;

-- keep the shop's copy in step with the order
create or replace function sync_shop_sale() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.route <> 'shop' or new.status = old.status then return new; end if;
  if new.status = 'delivered' then
    update shop_sales set status = 'done', done_at = now() where order_id = new.id and status <> 'cancelled';
  elsif new.status in ('cancelled', 'no_rider') then
    update vendor_stock vs set qty = vs.qty + oi.qty, updated_at = now()
      from order_items oi, shop_sales s
     where s.order_id = new.id and s.status in ('packing', 'ready') and s.picked_at is null
       and oi.order_id = new.id and vs.vendor_id = s.vendor_id and vs.product_id = oi.product_id;
    update shop_sales set status = 'cancelled' where order_id = new.id and status in ('new', 'packing', 'ready') and picked_at is null;
  end if;
  return new;
end $$;
create or replace trigger orders_sync_shop_sale after update of status on orders for each row execute function sync_shop_sale();

create or replace function vendor_orders(p_days integer default 31) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'bill_no', s.bill_no, 'items', s.items, 'total', s.total, 'discount', s.discount, 'pay_mode', s.pay_mode, 'source', s.source,
           'status', s.status, 'customer_phone', s.customer_phone, 'customer_name', s.customer_name, 'customer_address', s.customer_address,
           'created_at', s.created_at, 'accepted_at', s.accepted_at, 'packed_at', s.packed_at, 'picked_at', s.picked_at, 'done_at', s.done_at,
           'order_id', s.order_id, 'order_status', o.status, 'pickup_code', case when s.status in ('ready', 'done') then o.pickup_code end,
           'rider_name', rp.full_name, 'rider_phone', rp.phone)
           order by s.created_at desc), '[]'::jsonb)
    from shop_sales s left join orders o on o.id = s.order_id left join profiles rp on rp.id = o.rider_id
   where s.vendor_id = my_vendor_id() and s.created_at > now() - make_interval(days => greatest(1, least(p_days, 93)))
$$;

grant execute on function vendor_set_location(double precision, double precision, text), vendor_order_act(uuid, text), rider_pickup(uuid, text), rider_shop_task() to authenticated;

-- place_order now routes (rider with stock → shop → any rider) instead of always asking riders
create or replace function place_order(p_items jsonb, p_lat double precision, p_lng double precision, p_address text, p_coins integer) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_order uuid; v_total numeric := 0; it jsonb; v_price numeric; v_store text; v_n int; zc jsonb; v_bal int; v_use int := 0; r coin_rules;
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
  r := coin_rule_for(coalesce(v_store, 'food'));
  if coalesce(p_coins, 0) > 0 and coalesce(setting('coins_enabled')::text, 'true') = 'true' and r.store is not null and r.enabled then
    perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
    select coalesce(sum(delta), 0) into v_bal from coin_ledger where user_id = auth.uid();
    v_use := greatest(0, least(p_coins, v_bal, floor(v_total * r.max_redeem_pct / 100)))::int;
    if v_use > 0 then insert into coin_ledger(user_id, delta, reason, order_id) values (auth.uid(), -v_use, 'redeem', v_order); end if;
  end if;
  update orders set total = v_total - v_use, coins_used = v_use where id = v_order;
  perform route_order(v_order);
  return v_order;
end $$;

-- later the same day: dispatch_next waits for the shop to pack ("ready") before asking riders and, for a packed
-- shop order, keeps searching instead of giving up at once; sweep_shop_orders re-asks every 10 s and gives up after 30 min.
