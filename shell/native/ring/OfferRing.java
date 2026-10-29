package com.happyfood.ring;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import java.util.HashMap;
import java.util.Map;

/** "Incoming call" style request: heads-up / lock-screen, rings until answered, countdown, Accept / Reject / Mute. */
public class OfferRing {
    static final String CH_RING = "offer_call_v1";
    static final String CH_QUIET = "offer_quiet_v1";

    static int nid(String offerId) { return offerId == null ? 7001 : (offerId.hashCode() & 0x3fffffff) + 1000; }

    static void channels(Context c, NotificationManager nm) {
        if (Build.VERSION.SDK_INT < 26) return;
        if (nm.getNotificationChannel(CH_RING) == null) {
            NotificationChannel ch = new NotificationChannel(CH_RING, "नई रिक्वेस्ट (कॉल जैसी घंटी)", NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("राइडर/दुकान को नई डिलीवरी रिक्वेस्ट — फ़ोन लॉक हो तब भी");
            Uri snd = Uri.parse("android.resource://" + c.getPackageName() + "/raw/ring");
            ch.setSound(snd, new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            ch.enableVibration(true);
            ch.setVibrationPattern(new long[]{0, 700, 400, 700, 400, 700});
            ch.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            ch.setBypassDnd(true);
            nm.createNotificationChannel(ch);
        }
        if (nm.getNotificationChannel(CH_QUIET) == null) {
            NotificationChannel q = new NotificationChannel(CH_QUIET, "नई रिक्वेस्ट (बिना आवाज़)", NotificationManager.IMPORTANCE_HIGH);
            q.setSound(null, null);
            q.enableVibration(false);
            q.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
            nm.createNotificationChannel(q);
        }
    }

    static PendingIntent link(Context c, String offerId, String act, int code) {
        Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse("happyfood://offer?id=" + Uri.encode(offerId == null ? "" : offerId) + "&act=" + act));
        i.setPackage(c.getPackageName());
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(c, code, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    public static void show(Context c, Map<String, String> d, boolean quiet) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        channels(c, nm);
        String offerId = d.get("offer_id");
        int id = nid(offerId);
        long now = System.currentTimeMillis();
        long exp = now + 60000;
        try { exp = Long.parseLong(d.get("expires_at_ms")); } catch (Exception e) { }
        if (exp <= now + 1000) return; // already over
        String title = d.get("title") != null ? d.get("title") : "🔔 नई डिलीवरी रिक्वेस्ट";
        String body = d.get("body") != null ? d.get("body") : "जल्दी स्वीकार करें";

        PendingIntent open = link(c, offerId, "open", id);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, quiet ? CH_QUIET : CH_RING)
                .setSmallIcon(c.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(0xFFE2A92C)
                .setColorized(true)
                .setOngoing(true)
                .setAutoCancel(true)
                .setContentIntent(open)
                .setFullScreenIntent(open, true)
                .setWhen(exp).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
                .setTimeoutAfter(exp - now)
                .addAction(0, "✅ स्वीकार करें", link(c, offerId, "accept", id + 1))
                .addAction(0, "❌ मना करें", link(c, offerId, "reject", id + 2));
        if (quiet) b.setSilent(true);
        else {
            Intent m = new Intent(c, MuteReceiver.class);
            HashMap<String, String> copy = new HashMap<>(d);
            m.putExtra("data", copy);
            b.addAction(0, "🔕 आवाज़ बंद", PendingIntent.getBroadcast(c, id + 3, m, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        }
        Notification n = b.build();
        if (!quiet) n.flags |= Notification.FLAG_INSISTENT; // keeps ringing until answered, muted or timed out
        nm.notify(id, n);
    }

    public static void cancel(Context c, String offerId) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(nid(offerId));
    }
}
