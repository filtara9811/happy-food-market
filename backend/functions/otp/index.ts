// Happy Food — own 4-digit phone OTP login (Fast2SMS DLT route).
// POST {action:"send", phone:"9876543210"}            -> {ok:true} | {ok:false, code}
// POST {action:"verify", phone:"9876543210", code:"1234"} -> {ok:true, token_hash} (client: auth.verifyOtp({token_hash, type:"magiclink"}))
// Secrets: FAST2SMS_API_KEY, FAST2SMS_SENDER_ID, FAST2SMS_TEMPLATE_ID, optional OTP_TEST_NUMBERS ("9540068380:1234,9999999999:4321")
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const PEPPER = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { ...CORS, "Content-Type": "application/json" } });

const TTL_MS = 5 * 60_000, MAX_TRIES = 5, WIN_MS = 10 * 60_000, MAX_PER_WIN = 3, MAX_PER_DAY = 10;

async function hash(phone: string, code: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(PEPPER), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(phone + ":" + code)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}
function testCode(phone: string) {
  for (const p of (Deno.env.get("OTP_TEST_NUMBERS") ?? "").split(",")) {
    const [n, c] = p.trim().split(":");
    if (n && c && n.replace(/\D/g, "").slice(-10) === phone) return c.trim();
  }
  return null;
}
async function sendSms(phone: string, code: string) {
  const key = Deno.env.get("FAST2SMS_API_KEY"), sender = Deno.env.get("FAST2SMS_SENDER_ID"), tpl = Deno.env.get("FAST2SMS_TEMPLATE_ID");
  if (!key || !sender || !tpl) throw new Error("Fast2SMS secrets missing");
  const url = new URL("https://www.fast2sms.com/dev/bulkV2");
  url.searchParams.set("route", "dlt"); url.searchParams.set("sender_id", sender); url.searchParams.set("message", tpl);
  url.searchParams.set("variables_values", code); url.searchParams.set("numbers", phone); url.searchParams.set("flash", "0");
  const r = await fetch(url, { headers: { authorization: key } });
  const j = await r.json().catch(() => ({}));
  if (j.return !== true) throw new Error("fast2sms: " + JSON.stringify(j).slice(0, 160));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  let b: { action?: string; phone?: string; code?: string } = {};
  try { b = await req.json(); } catch { return json({ ok: false, code: "bad_request" }); }
  const phone = String(b.phone ?? "").replace(/\D/g, "").slice(-10);
  if (!/^[6-9]\d{9}$/.test(phone)) return json({ ok: false, code: "bad_phone" });
  const now = Date.now();
  const { data: row } = await SB.from("phone_otps").select("*").eq("phone", phone).maybeSingle();

  if (b.action === "send") {
    let win = row ? new Date(row.window_start).getTime() : now, inWin = row?.win_count ?? 0, day = row?.day_count ?? 0;
    const dayStart = row ? new Date(row.day_start).getTime() : now;
    if (now - win > WIN_MS) { win = now; inWin = 0; }
    const dayReset = now - dayStart > 24 * 3600_000;
    if (dayReset) day = 0;
    if (inWin >= MAX_PER_WIN || day >= MAX_PER_DAY) return json({ ok: false, code: "rate_limited" });
    const test = testCode(phone);
    const code = test ?? String(crypto.getRandomValues(new Uint32Array(1))[0] % 10000).padStart(4, "0");
    if (!test) { try { await sendSms(phone, code); } catch (e) { return json({ ok: false, code: "sms_failed", detail: String(e).slice(0, 180) }); } }
    await SB.from("phone_otps").upsert({
      phone, code_hash: await hash(phone, code), expires_at: new Date(now + TTL_MS).toISOString(), attempts: 0,
      window_start: new Date(win).toISOString(), win_count: inWin + 1,
      day_start: new Date(dayReset || !row ? now : dayStart).toISOString(), day_count: day + 1,
    });
    return json({ ok: true, length: 4 });
  }

  if (b.action === "verify") {
    const code = String(b.code ?? "").replace(/\D/g, "");
    if (!row || !row.code_hash) return json({ ok: false, code: "no_otp" });
    if (new Date(row.expires_at).getTime() < now) return json({ ok: false, code: "expired" });
    if (row.attempts >= MAX_TRIES) return json({ ok: false, code: "too_many_tries" });
    if ((await hash(phone, code)) !== row.code_hash) {
      await SB.from("phone_otps").update({ attempts: row.attempts + 1 }).eq("phone", phone);
      return json({ ok: false, code: "wrong_code", left: MAX_TRIES - row.attempts - 1 });
    }
    await SB.from("phone_otps").update({ code_hash: null, attempts: 0 }).eq("phone", phone);
    // the phone number is proven -> sign in (create the account the first time)
    const email = `91${phone}@phone.happyfood.app`;
    const c1 = await SB.auth.admin.createUser({ email, phone: "91" + phone, email_confirm: true, phone_confirm: true });
    if (c1.error && (/phone/i.test(c1.error.message) || !/already|registered|exists/i.test(c1.error.message))) {
      const c2 = await SB.auth.admin.createUser({ email, email_confirm: true });
      if (c2.error && !/already|registered|exists/i.test(c2.error.message)) return json({ ok: false, code: "account_failed", detail: c2.error.message });
    }
    const { data, error } = await SB.auth.admin.generateLink({ type: "magiclink", email });
    if (error || !data?.properties?.hashed_token) return json({ ok: false, code: "session_failed", detail: error?.message });
    return json({ ok: true, token_hash: data.properties.hashed_token });
  }
  return json({ ok: false, code: "bad_action" });
});
