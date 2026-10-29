// Happy Food — push notifications (FCM HTTP v1), called by DB triggers via pg_net.
// Auth: header x-push-secret is checked against the vault secret "push_hook_secret" (never leaves the DB).
// Secret: FCM_SERVICE_ACCOUNT (Firebase service-account JSON, pasted by the owner in Supabase secrets),
//         or app_secrets key "fcm_service_account" typed in the admin API hub.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
let cached: { token: string; exp: number } | null = null;

const b64url = (data: Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = ""; bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function accessToken(sa: { client_email: string; private_key: string }) {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const unsigned = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" })) + "." + b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: unsigned + "." + b64url(sig) }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("google oauth failed: " + JSON.stringify(j).slice(0, 200));
  cached = { token: j.access_token, exp: Date.now() + (j.expires_in ?? 3600) * 1000 };
  return cached.token;
}

type Msg = { title: string; body: string; channel: "orders_ring" | "updates"; ttl?: string; data?: Record<string, string> };

async function saRaw(): Promise<string | null> {
  const env = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (env) return env;
  const { data } = await SB.from("app_secrets").select("value").eq("key", "fcm_service_account").maybeSingle();
  return data?.value ?? null;
}

async function sendTo(userIds: string[], msg: Msg) {
  const raw = await saRaw();
  if (!raw) return { skipped: "FCM_SERVICE_ACCOUNT not set" };
  const ids = userIds.filter(Boolean);
  if (!ids.length) return { sent: 0 };
  const { data: rows } = await SB.from("push_tokens").select("token").in("user_id", ids).eq("active", true);
  if (!rows?.length) return { sent: 0, note: "no tokens" };
  const sa = JSON.parse(raw);
  const at = await accessToken(sa);
  let sent = 0; const errs: string[] = [];
  for (const { token } of rows) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: "Bearer " + at, "Content-Type": "application/json" },
      body: JSON.stringify({ message: {
        token,
        notification: { title: msg.title, body: msg.body },
        data: msg.data ?? {},
        android: {
          priority: "high", ttl: msg.ttl ?? "300s",
          notification: { channel_id: msg.channel, sound: msg.channel === "orders_ring" ? "ring" : "default",
                          default_vibrate_timings: true, notification_priority: "PRIORITY_MAX" },
        },
      } }),
    });
    if (r.ok) sent++;
    else {
      const t = await r.text(); errs.push(t.slice(0, 160));
      if (/UNREGISTERED|NOT_FOUND/.test(t)) await SB.from("push_tokens").delete().eq("token", token);
    }
  }
  return errs.length ? { sent, errs } : { sent };
}

const STATUS: Record<string, [string, string]> = {
  accepted: ["🎉 पार्टनर मिल गया", "आपका ऑर्डर स्वीकार हो गया — पार्टनर जल्द निकल रहे हैं"],
  on_the_way: ["🛵 खाना रास्ते में है", "डिलीवरी पार्टनर आपके पास आ रहे हैं"],
  delivered: ["✅ डिलीवर हो गया", "आपका खाना पहुँच गया — Happy Food चुनने के लिए धन्यवाद 🙏"],
  no_rider: ["😔 पार्टनर नहीं मिला", "अभी आस-पास कोई पार्टनर नहीं है, थोड़ी देर बाद फिर कोशिश करें"],
};

Deno.serve(async (req) => {
  const given = req.headers.get("x-push-secret") ?? "";
  const { data: ok } = await SB.rpc("push_secret_ok", { p: given });
  if (!given || ok !== true) return new Response("forbidden", { status: 403 });
  const p = await req.json();
  if (p.check) {
    // health check: is the Firebase key present and does Google accept it? (no secret values returned)
    const raw = await saRaw();
    if (!raw) return Response.json({ fcm: "missing" });
    try {
      const sa = JSON.parse(raw);
      await accessToken(sa);
      const { count } = await SB.from("push_tokens").select("token", { count: "exact", head: true });
      return Response.json({ fcm: "ok", project_id: sa.project_id, devices: count ?? 0 });
    } catch (e) { return Response.json({ fcm: "invalid", error: String(e).slice(0, 160) }); }
  }
  if (p.test && p.user_id) {
    // test from the admin: one ring-style and one normal notification to every phone of this user
    const ring = await sendTo([String(p.user_id)], { title: "🔔 टेस्ट: नई डिलीवरी रिक्वेस्ट", body: "यह घंटी वाली टेस्ट सूचना है — Happy Food", channel: "orders_ring", ttl: "60s", data: { kind: "test" } });
    const upd = await sendTo([String(p.user_id)], { title: "✅ Happy Food नोटिफ़िकेशन चालू", body: "आपके फ़ोन पर ऑर्डर की हर ख़बर अब आएगी 🎉", channel: "updates", data: { kind: "test" } });
    return Response.json({ ring, upd });
  }
  const rec = p.record ?? {};
  let out: unknown = { ignored: true };
  try {
    if (p.table === "order_offers" && p.op === "INSERT" && rec.status === "pending") {
      const { data: o } = await SB.from("orders").select("total").eq("id", rec.order_id).single();
      const km = Math.round((rec.distance_m ?? 0) / 100) / 10;
      out = await sendTo([rec.rider_id], {
        title: "🔔 नई डिलीवरी रिक्वेस्ट",
        body: `₹${o?.total ?? ""} का ऑर्डर • ${km} km दूर — जल्दी स्वीकार करें`,
        channel: "orders_ring", ttl: "40s",
        data: { kind: "offer", order_id: String(rec.order_id), offer_id: String(rec.id) },
      });
    } else if (p.table === "orders" && p.op === "INSERT") {
      const { data: admins } = await SB.from("profiles").select("id").contains("roles", ["admin"]);
      out = await sendTo((admins ?? []).map((a: { id: string }) => a.id), {
        title: "🛎️ नया ऑर्डर आया", body: rec.delivery_address ? `पता: ${rec.delivery_address}` : "ऐप खोलकर देखें",
        channel: "updates", data: { kind: "admin_new", order_id: String(rec.id) },
      });
    } else if (p.table === "orders" && p.op === "UPDATE" && STATUS[rec.status]) {
      const [title, body] = STATUS[rec.status];
      out = await sendTo([rec.customer_id], { title, body, channel: "updates",
        data: { kind: "order", order_id: String(rec.id), status: String(rec.status) } });
    }
  } catch (e) {
    out = { error: String(e) };
  }
  return Response.json(out);
});
