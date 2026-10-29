package com.happyfood.ring;

import androidx.annotation.NonNull;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

/** Wraps Capacitor's push service: a new-request message rings like a call, everything else works as before. */
public class RingMessagingService extends com.capacitorjs.plugins.pushnotifications.MessagingService {
    @Override
    public void onMessageReceived(@NonNull RemoteMessage msg) {
        Map<String, String> d = msg.getData();
        if (d != null && "offer".equals(d.get("kind"))) {
            // app open on screen = the in-app request sheet rings; otherwise ring like a call
            boolean onScreen = false;
            try {
                android.app.ActivityManager.RunningAppProcessInfo s = new android.app.ActivityManager.RunningAppProcessInfo();
                android.app.ActivityManager.getMyMemoryState(s);
                android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
                onScreen = s.importance == android.app.ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND && pm != null && pm.isInteractive();
            } catch (Throwable t) { }
            if (!onScreen) {
                try { OfferRing.show(getApplicationContext(), d, false); } catch (Throwable t) { /* never crash on a push */ }
            }
        } else if (d != null && "offer_gone".equals(d.get("kind"))) {
            try { OfferRing.cancel(getApplicationContext(), d.get("offer_id")); } catch (Throwable t) { }
        }
        super.onMessageReceived(msg);
    }
}
