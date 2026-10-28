-- One basket = one store. Every product belongs to a store; an order holds items of one store only.
alter table products add column if not exists store text not null default 'food'
  check (store in ('food','fruits','dry','kirana','veg','dairy','meat'));
alter table orders add column if not exists store text not null default 'food'
  check (store in ('food','fruits','dry','kirana','veg','dairy','meat'));
create index if not exists orders_store_idx on orders(store);

create or replace function public.place_order(p_items jsonb, p_lat double precision, p_lng double precision, p_address text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_order uuid; v_total numeric := 0; it jsonb; v_price numeric; v_store text; v_n int;
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

  update orders set total = v_total where id = v_order;
  perform dispatch_next(v_order);
  return v_order;
end $$;

create or replace function public.my_orders(p_limit integer default 20)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', o.id, 'status', o.status, 'total', o.total, 'created_at', o.created_at,
      'address', o.delivery_address, 'store', o.store,
      'items', (select string_agg(oi.qty || 'x ' || p.name, ', ')
                  from order_items oi join products p on p.id = oi.product_id
                 where oi.order_id = o.id)) x
      from orders o where o.customer_id = auth.uid()
     order by o.created_at desc limit p_limit) t
$$;
