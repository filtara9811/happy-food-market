-- 024: counter bill v2 (customer name + discount), shop settings (prep time, auto-accept),
-- public shop page data for the WhatsApp / QR link. Applied on the server 2026-10-30.
alter table shop_sales add column if not exists customer_name text;
alter table shop_sales add column if not exists discount numeric not null default 0;
alter table vendors add column if not exists prep_min int not null default 15;
alter table vendors add column if not exists auto_accept boolean not null default false;
-- functions (full bodies live on the server; dump with pg_get_functiondef):
--   vendor_bill(p_items jsonb, p_pay text, p_phone text, p_name text, p_discount numeric) → bill with discount, honours suspended + perms.pos
--   vendor_orders(p_days) → now also returns discount, customer_name
--   vendor_update(p jsonb) → also hours, prep_min, auto_accept, owner name
--   vendor_me() → also suspended, perms, extra_stores, prep_min, auto_accept, total_bills, month_bills, month_total
--   public_shop(p_id uuid) → granted to anon; shop name/address/phone + in-stock items for docs/s/index.html
