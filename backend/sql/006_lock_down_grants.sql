-- internal dispatch helpers: never callable from the app
revoke execute on function dispatch_next(uuid) from public, anon, authenticated;
revoke execute on function sweep_expired_offers() from public, anon, authenticated;
-- customer actions: logged-in users only
revoke execute on function place_order(jsonb, double precision, double precision, text) from public, anon;
grant  execute on function place_order(jsonb, double precision, double precision, text) to authenticated;
revoke execute on function cancel_order(uuid) from public, anon;
grant  execute on function cancel_order(uuid) to authenticated;
