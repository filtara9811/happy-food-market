-- 026: admin can choose auto / manual approval for new shops and riders (applied 2026-10-30).
insert into app_settings(key, value) values ('vendor_auto_approve', 'false'::jsonb) on conflict (key) do nothing;
insert into app_settings(key, value) values ('rider_auto_approve', 'false'::jsonb) on conflict (key) do nothing;
-- trigger auto_approve_partner() on insert into vendors / riders sets approved = true when the setting is on.
-- admin_approval_settings() → {vendors, riders}; admin_set_auto_approve(p_kind, p_on, p_approve_pending).
-- otp edge function v4: in demo mode (no FAST2SMS_API_KEY) every number uses OTP 1234 and send limits are off.
