-- Customer order details: recorded rider route, item photos, partner photo, step times
alter table public.orders add column if not exists picked_at timestamptz;
alter table public.profiles add column if not exists avatar text;

create table if not exists public.order_track (
  id bigserial primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  at timestamptz not null default now()
);
create index if not exists order_track_order_idx on public.order_track(order_id, at);
alter table public.order_track enable row level security;
revoke all on public.order_track from anon, authenticated;

-- every location ping from a rider on an active order is also saved on that order's route
create or replace function public.update_rider_location(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
declare v_order uuid;
begin
  update riders set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography, location_updated_at = now()
   where id = auth.uid();
  select id into v_order from orders where rider_id = auth.uid() and status in ('accepted', 'on_the_way')
   order by accepted_at desc nulls last limit 1;
  if v_order is not null then
    insert into order_track(order_id, lat, lng) values (v_order, p_lat, p_lng);
  end if;
end $$;

create or replace function public.rider_start_trip(p_order_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update orders set status = 'on_the_way', picked_at = now()
   where id = p_order_id and rider_id = auth.uid() and status = 'accepted';
  return found;
end $$;

create or replace function public.set_my_avatar(p_data text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_data is not null and (length(p_data) > 150000 or p_data not like 'data:image/%') then
    raise exception 'bad image';
  end if;
  update profiles set avatar = p_data where id = auth.uid();
end $$;

create or replace function public.order_detail(p_order_id uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', o.id, 'status', o.status, 'total', o.total, 'address', o.delivery_address,
    'created_at', o.created_at, 'accepted_at', o.accepted_at, 'picked_at', o.picked_at, 'delivered_at', o.delivered_at,
    'lat', st_y(o.delivery_location::geometry), 'lng', st_x(o.delivery_location::geometry),
    'otp', case when o.status in ('accepted', 'on_the_way') then (select s.otp from order_secrets s where s.order_id = o.id) end,
    'items', (select coalesce(jsonb_agg(jsonb_build_object('name', p.name, 'name_hi', p.name_hi, 'qty', oi.qty, 'price', oi.price, 'image_url', p.image_url)), '[]'::jsonb)
                from order_items oi join products p on p.id = oi.product_id where oi.order_id = o.id),
    'rider', case when o.rider_id is null then null else (
        select jsonb_build_object('name', coalesce(pr.full_name, 'डिलीवरी पार्टनर'), 'phone', pr.phone, 'vehicle', r.vehicle, 'avatar', pr.avatar)
          from riders r join profiles pr on pr.id = r.id where r.id = o.rider_id) end,
    'track', (select coalesce(jsonb_agg(jsonb_build_array(t.lat, t.lng) order by t.at), '[]'::jsonb)
                from order_track t where t.order_id = o.id))
  from orders o where o.id = p_order_id and o.customer_id = auth.uid()
$$;

-- rider screen also needs the photo
create or replace function public.rider_avatar() returns text
language sql stable security definer set search_path = public as $$ select avatar from profiles where id = auth.uid() $$;

do $$ declare f text; begin
  foreach f in array array['set_my_avatar(text)', 'order_detail(uuid)', 'rider_avatar()',
                           'update_rider_location(double precision, double precision)', 'rider_start_trip(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
