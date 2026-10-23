-- Rider (delivery partner) app + admin approval of riders
create or replace function public.rider_me() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'registered', r.id is not null,
    'approved', coalesce(r.approved, false),
    'online', coalesce(r.is_online, false),
    'vehicle', r.vehicle,
    'name', p.full_name, 'phone', p.phone,
    'loc_at', r.location_updated_at,
    'stock', (select coalesce(jsonb_agg(jsonb_build_object('product_id', s.product_id, 'qty', s.qty, 'reserved', s.reserved)), '[]'::jsonb)
                from rider_stock s where s.rider_id = p.id),
    'offer', (select jsonb_build_object('id', f.id, 'order_id', f.order_id, 'distance_m', f.distance_m,
                       'seconds_left', greatest(0, extract(epoch from f.expires_at - now()))::int, 'total', o.total,
                       'items', (select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', pr.name, 'name_hi', pr.name_hi, 'qty', oi.qty, 'price', oi.price)), '[]'::jsonb)
                                   from order_items oi join products pr on pr.id = oi.product_id where oi.order_id = o.id))
                from order_offers f join orders o on o.id = f.order_id
               where f.rider_id = p.id and f.status = 'pending' and f.expires_at > now() and o.status = 'searching'
               order by f.created_at desc limit 1),
    'active', (select jsonb_build_object('id', o.id, 'status', o.status, 'total', o.total, 'address', o.delivery_address,
                       'lat', st_y(o.delivery_location::geometry), 'lng', st_x(o.delivery_location::geometry),
                       'customer', cp.full_name, 'customer_phone', cp.phone, 'accepted_at', o.accepted_at,
                       'items', (select coalesce(jsonb_agg(jsonb_build_object('product_id', oi.product_id, 'name', pr.name, 'name_hi', pr.name_hi, 'qty', oi.qty, 'price', oi.price)), '[]'::jsonb)
                                   from order_items oi join products pr on pr.id = oi.product_id where oi.order_id = o.id))
                 from orders o left join profiles cp on cp.id = o.customer_id
                where o.rider_id = p.id and o.status in ('accepted', 'on_the_way')
                order by o.accepted_at desc nulls last limit 1),
    'today', (select jsonb_build_object('count', count(*), 'total', coalesce(sum(o.total), 0))
                from orders o where o.rider_id = p.id and o.status = 'delivered'
                 and o.delivered_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')))
  from profiles p left join riders r on r.id = p.id
  where p.id = auth.uid()
$$;

create or replace function public.rider_register(p_name text, p_vehicle text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not logged in'; end if;
  perform choose_role('rider');
  update profiles set full_name = coalesce(nullif(trim(p_name), ''), full_name) where id = auth.uid();
  update riders set vehicle = coalesce(nullif(upper(trim(p_vehicle)), ''), vehicle) where id = auth.uid();
  return rider_me();
end $$;

create or replace function public.rider_set_online(p_online boolean, p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from riders where id = auth.uid() and approved) then
    return jsonb_build_object('ok', false, 'code', 'not_approved');
  end if;
  if p_lat is not null and p_lng is not null then
    update riders set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, location_updated_at = now() where id = auth.uid();
  end if;
  update riders set is_online = p_online where id = auth.uid();
  return jsonb_build_object('ok', true, 'online', p_online);
end $$;

create or replace function public.rider_start_trip(p_order_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update orders set status = 'on_the_way' where id = p_order_id and rider_id = auth.uid() and status = 'accepted';
  return found;
end $$;

create or replace function public.admin_riders() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  return (select coalesce(jsonb_agg(x order by (x->>'approved')::boolean, x->>'name'), '[]'::jsonb) from (
    select jsonb_build_object('id', r.id, 'name', p.full_name, 'phone', p.phone, 'vehicle', r.vehicle,
             'approved', r.approved, 'online', r.is_online,
             'loc_fresh', r.location_updated_at > now() - interval '2 minutes',
             'stock_units', (select coalesce(sum(qty), 0) from rider_stock s where s.rider_id = r.id),
             'delivered', (select count(*) from orders o where o.rider_id = r.id and o.status = 'delivered')) x
      from riders r join profiles p on p.id = r.id) t);
end $$;

create or replace function public.admin_set_rider(p_rider uuid, p_approved boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  update riders set approved = p_approved, is_online = case when p_approved then is_online else false end where id = p_rider;
end $$;

do $$ declare f text; begin
  foreach f in array array['rider_me()', 'rider_register(text, text)', 'rider_set_online(boolean, double precision, double precision)',
                           'rider_start_trip(uuid)', 'admin_riders()', 'admin_set_rider(uuid, boolean)',
                           'respond_offer(uuid, boolean)', 'set_stock(uuid, integer, numeric)', 'update_rider_location(double precision, double precision)',
                           'complete_delivery(uuid, text)', 'offer_details(uuid)', 'choose_role(text)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
