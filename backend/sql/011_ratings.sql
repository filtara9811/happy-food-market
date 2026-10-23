-- Customer rating after delivery: happy / bad service + reason tags
create table if not exists public.order_ratings (
  order_id uuid primary key references public.orders(id) on delete cascade,
  customer_id uuid not null,
  rider_id uuid,
  mood text not null check (mood in ('happy', 'bad')),
  food_tags text[] not null default '{}',
  rider_tags text[] not null default '{}',
  comment text,
  callback boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.order_ratings enable row level security;

create or replace function public.rate_order(p_order_id uuid, p_mood text, p_food_tags text[], p_rider_tags text[], p_comment text, p_callback boolean)
returns boolean language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order_id and customer_id = auth.uid() and status = 'delivered';
  if not found then return false; end if;
  insert into order_ratings (order_id, customer_id, rider_id, mood, food_tags, rider_tags, comment, callback)
  values (o.id, o.customer_id, o.rider_id, p_mood, coalesce(p_food_tags, '{}'), coalesce(p_rider_tags, '{}'), left(nullif(trim(p_comment), ''), 500), coalesce(p_callback, false))
  on conflict (order_id) do update set mood = excluded.mood, food_tags = excluded.food_tags, rider_tags = excluded.rider_tags,
    comment = excluded.comment, callback = excluded.callback, created_at = now();
  return true;
end $$;

create or replace function public.admin_ratings(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_role('admin') then raise exception 'admin only'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object('order_id', r.order_id, 'mood', r.mood, 'food', r.food_tags, 'rider', r.rider_tags, 'comment', r.comment,
             'callback', r.callback, 'created_at', r.created_at, 'customer', cp.full_name, 'customer_phone', cp.phone, 'rider_name', rp.full_name) x
      from order_ratings r left join profiles cp on cp.id = r.customer_id left join profiles rp on rp.id = r.rider_id
     order by r.created_at desc limit p_limit) t);
end $$;

revoke execute on function public.rate_order(uuid, text, text[], text[], text, boolean) from public, anon;
grant execute on function public.rate_order(uuid, text, text[], text[], text, boolean) to authenticated;
revoke execute on function public.admin_ratings(int) from public, anon;
grant execute on function public.admin_ratings(int) to authenticated;
