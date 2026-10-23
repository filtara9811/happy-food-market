// Supabase "Send SMS" auth hook -> Fast2SMS (DLT route).
// Supabase calls this instead of sending the OTP itself.
// Secrets (Supabase > Edge Functions > Secrets):
//   SEND_SMS_HOOK_SECRET   the "v1,whsec_..." value shown when you create the hook
//   FAST2SMS_API_KEY       Fast2SMS > Dev API > API key
//   FAST2SMS_SENDER_ID     your DLT-approved sender ID (3-6 letters)
//   FAST2SMS_TEMPLATE_ID   your approved DLT template (message) ID, template has one {#var#} for the OTP
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

function fail(status: number, message: string) {
  return new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const payload = await req.text();
  const headers = Object.fromEntries(req.headers);
  const secret = (Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "").replace("v1,whsec_", "");

  let data: { user?: { phone?: string }; sms?: { otp?: string } };
  try {
    data = new Webhook(secret).verify(payload, headers) as typeof data;
  } catch (_e) {
    return fail(401, "Invalid hook signature");
  }

  const phone = String(data.user?.phone ?? "").replace(/\D/g, "").slice(-10);
  const otp = String(data.sms?.otp ?? "");
  if (phone.length !== 10 || !otp) return fail(400, "Missing phone or otp");

  const key = Deno.env.get("FAST2SMS_API_KEY");
  const sender = Deno.env.get("FAST2SMS_SENDER_ID");
  const template = Deno.env.get("FAST2SMS_TEMPLATE_ID");
  if (!key || !sender || !template) return fail(500, "SMS provider is not configured");

  const url = new URL("https://www.fast2sms.com/dev/bulkV2");
  url.searchParams.set("route", "dlt");
  url.searchParams.set("sender_id", sender);
  url.searchParams.set("message", template);
  url.searchParams.set("variables_values", otp);
  url.searchParams.set("numbers", phone);

  try {
    const r = await fetch(url, { headers: { Authorization: key } });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || j.return !== true) {
      console.error("Fast2SMS rejected the request", r.status, JSON.stringify(j));
      return fail(502, "SMS could not be sent");
    }
  } catch (e) {
    console.error("Fast2SMS call failed", String(e));
    return fail(502, "SMS service unreachable");
  }
  return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
});
