package com.happyfood.ring;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import java.util.HashMap;
import java.util.Map;

/** "आवाज़ बंद": same request stays on screen with its timer and buttons, without the ring. */
public class MuteReceiver extends BroadcastReceiver {
    @Override
    @SuppressWarnings("unchecked")
    public void onReceive(Context c, Intent i) {
        try {
            Map<String, String> d = (HashMap<String, String>) i.getSerializableExtra("data");
            if (d == null) return;
            OfferRing.cancel(c, d.get("offer_id"));
            OfferRing.show(c, d, true);
        } catch (Throwable t) { }
    }
}
