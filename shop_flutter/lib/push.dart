import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api.dart';
import 'fb_opts.dart';

/// Push + "incoming call" style ring for new app orders sent to this shop.
/// The server sends a data-only FCM message (kind=shop_order) to tokens saved as platform "android:vendor".
class Push {
  static final fln = FlutterLocalNotificationsPlugin();
  static final actions = StreamController<(String, String)>.broadcast(); // (accept|reject|open, offerId)
  static bool ready = false;
  static (String, String)? launch;

  static FirebaseOptions? get options => fbOk
      ? const FirebaseOptions(apiKey: fbApiKey, appId: fbAppId, messagingSenderId: fbSender, projectId: fbProject)
      : null;

  static Future<void> init() async {
    try {
      if (options == null) return;
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(pushBackground);
      await _initLocal();
      FirebaseMessaging.onMessage.listen((m) => _handle(m.data, foreground: true));
      final l = await fln.getNotificationAppLaunchDetails();
      final r = l?.notificationResponse;
      if (l?.didNotificationLaunchApp == true && r != null && (r.payload ?? '').isNotEmpty) launch = (r.actionId ?? 'open', r.payload!);
      ready = true;
    } catch (_) {}
  }

  static Future<void> _initLocal() async {
    await fln.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) { if ((r.payload ?? '').isNotEmpty) actions.add((r.actionId ?? 'open', r.payload!)); },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  /// Ask for notification + full-screen permission and save this phone's push token for the rider app.
  static Future<void> register() async {
    if (!ready) return;
    try {
      await FirebaseMessaging.instance.requestPermission(alert: true, sound: true, badge: true);
      final a = fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await a?.requestNotificationsPermission();
      try { await a?.requestFullScreenIntentPermission(); } catch (_) {}
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await Api.rpc('save_push_token', {'p_token': t, 'p_platform': 'android:vendor'});
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => Api.rpc('save_push_token', {'p_token': t, 'p_platform': 'android:vendor'}));
    } catch (_) {}
  }

  static Future<void> unregister() async {
    try { final t = await FirebaseMessaging.instance.getToken(); if (t != null) await Api.rpc('drop_push_token', {'p_token': t}); } catch (_) {}
  }

  static int nid(String offerId) => (offerId.codeUnits.fold<int>(0, (h, c) => (h * 31 + c) & 0x3fffffff)) + 1000;

  static Future<void> _handle(Map<String, dynamic> d, {bool foreground = false}) async {
    final kind = d['kind']?.toString();
    final offer = d['sale_id']?.toString() ?? '';
    if (kind != 'shop_order' || offer.isEmpty) return;
    if (foreground) return; // the app shows its own big request screen
    await showOffer(d);
  }

  static Future<void> showOffer(Map<String, dynamic> d) async {
    final offer = d['sale_id'].toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final exp = int.tryParse('${d['expires_at_ms']}') ?? now + 60000;
    if (exp <= now + 1000) return;
    final details = AndroidNotificationDetails(
      'shop_order_v1', 'दुकान के नए ऑर्डर',
      channelDescription: 'कॉल जैसी घंटी — फ़ोन लॉक हो तब भी',
      importance: Importance.max, priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true, ongoing: true, autoCancel: true,
      visibility: NotificationVisibility.public,
      playSound: true, sound: const RawResourceAndroidNotificationSound('ring'),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      enableVibration: true, vibrationPattern: Int64List.fromList([0, 700, 400, 700, 400, 700]),
      additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: keeps ringing until answered
      timeoutAfter: exp - now,
      color: const Color(0xFFE2A92C), colorized: true,
      styleInformation: BigTextStyleInformation(d['body']?.toString() ?? ''),
      actions: const [
        AndroidNotificationAction('reject', '✖  मना करें', titleColor: Color(0xFFDC2626), showsUserInterface: true, cancelNotification: true),
        AndroidNotificationAction('accept', '✔  स्वीकार करें', titleColor: Color(0xFF16A34A), showsUserInterface: true, cancelNotification: true),
      ],
    );
    await fln.show(nid(offer), d['title']?.toString() ?? '🔔 नया ऑर्डर आया', d['body']?.toString() ?? 'जल्दी जवाब दें', NotificationDetails(android: details), payload: offer);
  }

  static Future<void> clear(String offer) async { try { await fln.cancel(nid(offer)); } catch (_) {} }
}

@pragma('vm:entry-point')
Future<void> pushBackground(RemoteMessage m) async {
  try {
    if (Push.options != null) await Firebase.initializeApp(options: Push.options);
    await Push._initLocal();
    await Push._handle(m.data);
  } catch (_) {}
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse r) {}
