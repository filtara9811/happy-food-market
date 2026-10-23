-- 005: what the customer app needs (profile on first login, live order view, my orders)

-- First login: make sure a profile row exists and store the name the person typed.
create or replace function ensure_profile(p_name text default null, p_city text default null)
returns jsonb language plpgsql security definer as $$
declare v_phone text;
begin
  select phone into v_phone from auth.users where id = auth.uid();
  insert into profiles(id, phone) values (auth.uid(), v_phone)
    on conflict (id) do update set phone = coalesce(profiles.phone, excluded.phone);
  if p_name is not null and length(trim(p_name)) > 0 then
    update profiles set full_name = trim(p_name) where id = auth.uid();
  end if;
  return (select jsonb_build_object('name', full_name, 'phone', phone, 'roles', roles)
            from profiles where id = auth.uid());
end $$;

create or replace function my_profile() returns jsonb
language sql stable security definer as $$
  select jsonb_build_object('name', full_name, 'phone', phone, 'roles', roles)
    from profiles where id = auth.uid()
$$;

-- One order, everything the customer screen needs (own orders only).
create or replace function order_view(p_order_id uuid) returns jsonb
language sql stable security definer as $$
  select jsonb_build_object(
    'id', o.id, 'status', o.status, 'total', o.total, 'address', o.delivery_address,
    'created_at', o.created_at, 'accepted_at', o.accepted_at, 'delivered_at', o.delivered_at,
    'otp', (select s.otp from order_secrets s where s.order_id = o.id),
    'lat', st_y(o.delivery_location::geometry), 'lng', st_x(o.delivery_location::geometry),
    'offers_sent', (select count(*) from order_offers f where f.order_id = o.id),
    'items', (select coalesce(jsonb_agg(jsonb_build_object(
                'product_id', oi.product_id, 'name', p.name, 'name_hi', p.name_hi,
                'qty', oi.qty, 'price', oi.price)), '[]'::jsonb)
                from order_items oi join products p on p.id = oi.product_id
               where oi.order_id = o.id),
    'rider', case when o.rider_id is null then null else (
        select jsonb_build_object(
                 'name', coalesce(pr.full_name, 'डिलीवरी पार्टनर'), 'vehicle', r.vehicle,
                 'phone', pr.phone,
                 'lat', case when r.location is null then null else st_y(r.location::geometry) end,
                 'lng', case when r.location is null then null else st_x(r.location::geometry) end)
          from riders r join profiles pr on pr.id = r.id where r.id = o.rider_id) end)
    from orders o where o.id = p_order_id and o.customer_id = auth.uid()
$$;

create or replace function my_orders(p_limit int default 20) returns jsonb
language sql stable security definer as $$
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', o.id, 'status', o.status, 'total', o.total, 'created_at', o.created_at,
      'address', o.delivery_address,
      'items', (select string_agg(oi.qty || 'x ' || p.name, ', ')
                  from order_items oi join products p on p.id = oi.product_id
                 where oi.order_id = o.id)) x
      from orders o where o.customer_id = auth.uid()
     order by o.created_at desc limit p_limit) t
$$;

grant execute on function ensure_profile(text, text), my_profile(), order_view(uuid), my_orders(int) to authenticated;
