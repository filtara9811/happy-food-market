-- 023: admin "people" console — shops, riders, customers with full details, edit, suspend, payouts.
alter table vendors add column if not exists suspended boolean not null default false;
alter table vendors add column if not exists extra_stores text[] not null default '{}';
alter table vendors add column if not exists multi_cat boolean not null default false;
alter table vendors add column if not exists radius_km numeric not null default 3;
alter table vendors add column if not exists commission_pct numeric not null default 0;
alter table vendors add column if not exists perms jsonb not null default '{"pos":true,"app_orders":true,"qr":true,"wholesale":false}';
alter table vendors add column if not exists hours text;
alter table vendors add column if not exists admin_note text;
alter table riders add column if not exists suspended boolean not null default false;
alter table riders add column if not exists admin_note text;
alter table profiles add column if not exists suspended boolean not null default false;
alter table profiles add column if not exists admin_note text;

create table if not exists payouts (
  id bigserial primary key,
  kind text not null check (kind in ('vendor','rider')),
  party_id uuid not null,
  amount numeric not null,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
alter table payouts enable row level security;

insert into app_settings(key, value) values ('rider_pay_per_delivery', '30'::jsonb) on conflict (key) do nothing;

-- suspension is enforced on the server, not only in the UI
create or replace function enforce_suspension_vendor() returns trigger language plpgsql as $$
begin
  if new.suspended then new.is_open := false; end if;
  return new;
end $$;
create or replace trigger vendors_suspension before insert or update on vendors for each row execute function enforce_suspension_vendor();

create or replace function enforce_suspension_rider() returns trigger language plpgsql as $$
begin
  if new.suspended then new.is_online := false; end if;
  return new;
end $$;
create or replace trigger riders_suspension before insert or update on riders for each row execute function enforce_suspension_rider();

create or replace function enforce_suspension_customer() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from profiles where id = new.customer_id and suspended) then
    raise exception 'account_suspended';
  end if;
  return new;
end $$;
create or replace trigger orders_customer_suspension before insert on orders for each row execute function enforce_suspension_customer();

-- multi-category shops see products of the extra categories too
create or replace function vendor_catalog() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('product_id', pr.id, 'name', pr.name, 'name_hi', pr.name_hi, 'price', pr.price, 'image_url', pr.image_url, 'store', pr.store,
           'qty', coalesce(s.qty, 0), 'shop_price', s.shop_price, 'active', coalesce(s.active, false)) order by pr.sort_order nulls last, pr.name), '[]'::jsonb)
    from products pr join vendors v on v.owner_id = auth.uid() and (pr.store = v.store or (v.multi_cat and pr.store = any(v.extra_stores)))
    left join vendor_stock s on s.vendor_id = v.id and s.product_id = pr.id
   where pr.is_active
$$;

create or replace function admin_people(p_kind text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ist timestamptz := date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
        rate numeric := coalesce((select (value #>> '{}')::numeric from app_settings where key = 'rider_pay_per_delivery'), 30);
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  if p_kind = 'vendors' then
    return coalesce((select jsonb_agg(x order by (x->>'status') = 'pending' desc, x->>'joined' desc) from (
      select jsonb_build_object('id', v.id, 'user_id', v.owner_id, 'name', v.shop_name, 'owner', p.full_name, 'phone', p.phone, 'avatar', coalesce(v.photo, p.avatar),
        'address', v.address, 'location_text', v.location_text, 'store', v.store, 'extra_stores', v.extra_stores, 'multi_cat', v.multi_cat,
        'radius_km', v.radius_km, 'commission_pct', v.commission_pct, 'perms', v.perms, 'hours', v.hours, 'note', v.admin_note,
        'upi', v.upi, 'fssai', v.fssai, 'gstin', v.gstin, 'open', v.is_open, 'approved', v.approved, 'suspended', v.suspended,
        'status', case when v.suspended then 'suspended' when v.approved then 'approved' else 'pending' end,
        'joined', v.created_at,
        'lat', st_y(v.location::geometry), 'lng', st_x(v.location::geometry),
        'sales_total', (select coalesce(sum(total), 0) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled'),
        'sales_month', (select coalesce(sum(total), 0) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled' and s.created_at >= ist),
        'sales_today', (select coalesce(sum(total), 0) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled' and s.created_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
        'bills', (select count(*) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled'),
        'app_orders', (select count(*) from shop_sales s where s.vendor_id = v.id and s.source = 'app' and s.status <> 'cancelled'),
        'app_sales', (select coalesce(sum(total), 0) from shop_sales s where s.vendor_id = v.id and s.source = 'app' and s.status <> 'cancelled'),
        'products', (select count(*) from vendor_stock s where s.vendor_id = v.id and s.active),
        'stock_units', (select coalesce(sum(qty), 0) from vendor_stock s where s.vendor_id = v.id and s.active),
        'paid', (select coalesce(sum(amount), 0) from payouts y where y.kind = 'vendor' and y.party_id = v.id),
        'payouts', (select coalesce(jsonb_agg(jsonb_build_object('amount', amount, 'note', note, 'at', created_at) order by created_at desc), '[]'::jsonb) from (select * from payouts y where y.kind = 'vendor' and y.party_id = v.id order by created_at desc limit 10) y)
      ) x from vendors v left join profiles p on p.id = v.owner_id) t), '[]'::jsonb);
  elsif p_kind = 'riders' then
    return coalesce((select jsonb_agg(x order by (x->>'status') = 'pending' desc, x->>'name') from (
      select jsonb_build_object('id', r.id, 'user_id', r.id, 'name', p.full_name, 'phone', p.phone, 'avatar', p.avatar, 'vehicle', r.vehicle, 'note', r.admin_note,
        'approved', r.approved, 'suspended', r.suspended, 'online', r.is_online, 'loc_fresh', r.location_updated_at > now() - interval '2 minutes',
        'loc_at', r.location_updated_at,
        'status', case when r.suspended then 'suspended' when r.approved then 'approved' else 'pending' end,
        'joined', p.created_at,
        'stock_units', (select coalesce(sum(qty), 0) from rider_stock s where s.rider_id = r.id),
        'delivered', (select count(*) from orders o where o.rider_id = r.id and o.status = 'delivered'),
        'delivered_month', (select count(*) from orders o where o.rider_id = r.id and o.status = 'delivered' and o.delivered_at >= ist),
        'cancels', (select count(*) from orders o where o.rider_id = r.id and o.cancelled_by = 'rider'),
        'fines', (select coalesce(sum(amount), 0) from penalties f where f.user_id = r.id and f.status <> 'waived'),
        'rate', rate,
        'earned', rate * (select count(*) from orders o where o.rider_id = r.id and o.status = 'delivered'),
        'paid', (select coalesce(sum(amount), 0) from payouts y where y.kind = 'rider' and y.party_id = r.id),
        'cash_collected', (select coalesce(sum(total), 0) from orders o where o.rider_id = r.id and o.status = 'delivered'),
        'payouts', (select coalesce(jsonb_agg(jsonb_build_object('amount', amount, 'note', note, 'at', created_at) order by created_at desc), '[]'::jsonb) from (select * from payouts y where y.kind = 'rider' and y.party_id = r.id order by created_at desc limit 10) y)
      ) x from riders r join profiles p on p.id = r.id) t), '[]'::jsonb);
  else
    return coalesce((select jsonb_agg(x order by x->>'last_order' desc nulls last, x->>'joined' desc) from (
      select jsonb_build_object('id', p.id, 'user_id', p.id, 'name', p.full_name, 'phone', p.phone, 'avatar', p.avatar, 'roles', p.roles, 'note', p.admin_note,
        'suspended', p.suspended, 'status', case when p.suspended then 'suspended' else 'approved' end,
        'joined', p.created_at,
        'orders', (select count(*) from orders o where o.customer_id = p.id),
        'delivered', (select count(*) from orders o where o.customer_id = p.id and o.status = 'delivered'),
        'cancelled', (select count(*) from orders o where o.customer_id = p.id and o.status = 'cancelled'),
        'spent', (select coalesce(sum(total), 0) from orders o where o.customer_id = p.id and o.status = 'delivered'),
        'spent_month', (select coalesce(sum(total), 0) from orders o where o.customer_id = p.id and o.status = 'delivered' and o.created_at >= ist),
        'items', (select coalesce(sum(oi.qty), 0) from orders o join order_items oi on oi.order_id = o.id where o.customer_id = p.id and o.status = 'delivered'),
        'coins', (select coalesce(sum(delta), 0) from coin_ledger c where c.user_id = p.id),
        'cancel_fees', (select coalesce(sum(cancel_fee), 0) from orders o where o.customer_id = p.id),
        'last_order', (select max(created_at) from orders o where o.customer_id = p.id),
        'last_address', (select delivery_address from orders o where o.customer_id = p.id order by created_at desc limit 1),
        'recent', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'total', o.total, 'status', o.status, 'at', o.created_at) order by o.created_at desc), '[]'::jsonb) from (select * from orders o where o.customer_id = p.id order by created_at desc limit 8) o)
      ) x from profiles p) t), '[]'::jsonb);
  end if;
end $$;

create or replace function admin_person_update(p_kind text, p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  if p_kind = 'vendors' then
    update vendors set
      shop_name = coalesce(p->>'name', shop_name),
      address = coalesce(p->>'address', address),
      store = coalesce(p->>'store', store),
      extra_stores = coalesce((select array_agg(e) from jsonb_array_elements_text(p->'extra_stores') e), case when p ? 'extra_stores' then '{}'::text[] else extra_stores end),
      multi_cat = coalesce((p->>'multi_cat')::boolean, multi_cat),
      radius_km = coalesce((p->>'radius_km')::numeric, radius_km),
      commission_pct = coalesce((p->>'commission_pct')::numeric, commission_pct),
      perms = coalesce(p->'perms', perms),
      hours = coalesce(p->>'hours', hours),
      upi = coalesce(p->>'upi', upi), fssai = coalesce(p->>'fssai', fssai), gstin = coalesce(p->>'gstin', gstin),
      admin_note = coalesce(p->>'note', admin_note),
      approved = coalesce((p->>'approved')::boolean, approved),
      suspended = coalesce((p->>'suspended')::boolean, suspended),
      is_open = case when coalesce((p->>'approved')::boolean, approved) then is_open else false end
    where id = p_id returning owner_id into uid;
  elsif p_kind = 'riders' then
    update riders set
      vehicle = coalesce(p->>'vehicle', vehicle),
      admin_note = coalesce(p->>'note', admin_note),
      approved = coalesce((p->>'approved')::boolean, approved),
      suspended = coalesce((p->>'suspended')::boolean, suspended),
      is_online = case when coalesce((p->>'approved')::boolean, approved) then is_online else false end
    where id = p_id returning id into uid;
  else
    uid := p_id;
    update profiles set suspended = coalesce((p->>'suspended')::boolean, suspended), admin_note = coalesce(p->>'note', admin_note) where id = p_id;
  end if;
  if uid is not null and (p ? 'owner' or p ? 'person_name') then
    update profiles set full_name = coalesce(p->>'person_name', p->>'owner') where id = uid;
  end if;
  return jsonb_build_object('ok', uid is not null);
end $$;

create or replace function admin_add_payout(p_kind text, p_id uuid, p_amount numeric, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare k text := case when p_kind in ('vendors','vendor') then 'vendor' else 'rider' end;
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'amount_required'; end if;
  insert into payouts(kind, party_id, amount, note) values (k, p_id, p_amount, nullif(trim(p_note), ''));
  return jsonb_build_object('ok', true);
end $$;

create or replace function admin_set_rider_rate(p_rate numeric) returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  insert into app_settings(key, value) values ('rider_pay_per_delivery', to_jsonb(p_rate)) on conflict (key) do update set value = excluded.value;
end $$;

-- vendor_me also tells the shop if it is suspended and which extra categories it has
create or replace function vendor_me() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'registered', v.id is not null, 'id', v.id, 'approved', coalesce(v.approved, false), 'open', coalesce(v.is_open, false), 'suspended', coalesce(v.suspended, false),
    'shop_name', v.shop_name, 'address', v.address, 'store', v.store, 'extra_stores', v.extra_stores, 'multi_cat', v.multi_cat, 'perms', v.perms, 'hours', v.hours,
    'photo', v.photo, 'upi', v.upi, 'fssai', v.fssai, 'gstin', v.gstin, 'created_at', v.created_at,
    'owner', p.full_name, 'phone', p.phone, 'avatar', p.avatar,
    'today', (select jsonb_build_object('count', count(*), 'total', coalesce(sum(s.total), 0)) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled'
               and s.created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')),
    'total_bills', (select count(*) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled'),
    'month_bills', (select count(*) from shop_sales s where s.vendor_id = v.id and s.status <> 'cancelled' and s.created_at >= date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'))
  from profiles p left join vendors v on v.owner_id = p.id where p.id = auth.uid()
$$;

grant execute on function admin_people(text), admin_person_update(text, uuid, jsonb), admin_add_payout(text, uuid, numeric, text), admin_set_rider_rate(numeric) to authenticated;
