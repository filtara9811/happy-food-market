import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../main.dart';
import '../push.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/route_map.dart';

/// Rider app connected to the server: go online, get requests (call-style ring), pick up (scan shop QR),
/// deliver with OTP, cancel with a reason, see today's deliveries and stock.
class RiderLive extends StatefulWidget {
  const RiderLive({super.key});
  @override
  State<RiderLive> createState() => _RiderLiveState();
}

class _RiderLiveState extends State<RiderLive> with WidgetsBindingObserver {
  Map<String, dynamic> me = {}, task = {};
  List<Map<String, dynamic>> hist = [];
  String err = '', avatar = '';
  bool loading = true, busy = false, offerOpen = false;
  int nav = 0;
  Timer? poll, locT;
  StreamSubscription? actSub;
  final shownOffers = <String>{};
  DateTime lastLoc = DateTime(2000);
  String locMsg = '';
  LatLng? myPos;
  bool batteryOk = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    Api.loadProducts().then((_) { if (mounted) setState(() {}); }).catchError((_) {});
    poll = Timer.periodic(const Duration(seconds: 3), (_) => load(quiet: true));
    locT = Timer.periodic(const Duration(seconds: 15), (_) => sendLoc());
    Push.register();
    checkBattery();
    actSub = Push.actions.stream.listen((a) => onAction(a.$1, a.$2));
    if (Push.launch != null) { final l = Push.launch!; Push.launch = null; Future.delayed(const Duration(milliseconds: 900), () => onAction(l.$1, l.$2)); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    locT?.cancel();
    actSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) { load(quiet: true); sendLoc(force: true); } }

  Future<void> load({bool quiet = false}) async {
    try {
      final m = await Api.me();
      final t = await Api.shopTask().catchError((_) => <String, dynamic>{});
      if (!mounted) return;
      final first = me.isEmpty;
      setState(() { me = m; task = t; err = ''; loading = false; });
      if (first) { loadHist(); loadAvatar(); if (m['online'] == true) sendLoc(force: true); }
      final o = m['offer'];
      if (o is Map && !offerOpen && !shownOffers.contains(o['id'].toString())) openOffer(Map<String, dynamic>.from(o));
    } catch (e) {
      if (mounted && !quiet) setState(() { err = errText(e); loading = false; });
    }
  }

  Future<void> loadHist() async {
    try { final h = await Api.history(31); final l = (h['orders'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? []; if (mounted) setState(() => hist = l); } catch (_) {}
  }

  Future<void> loadAvatar() async {
    try { final a = await Api.rpc('rider_avatar'); if (mounted && a is String) setState(() => avatar = a); } catch (_) {}
  }

  // ---------- location ----------
  Future<Position?> pos() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) { locMsg = 'फ़ोन की लोकेशन (GPS) चालू करें'; return null; }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) { locMsg = 'लोकेशन की अनुमति दीजिए'; return null; }
      locMsg = '';
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    } catch (_) { locMsg = 'लोकेशन नहीं मिली'; return null; }
  }

  Future<void> sendLoc({bool force = false}) async {
    if (me['online'] != true) return;
    if (!force && DateTime.now().difference(lastLoc).inSeconds < 14) return;
    final p = await pos();
    if (p == null) { if (mounted) setState(() {}); return; }
    myPos = LatLng(p.latitude, p.longitude);
    try { await Api.rpc('update_rider_location', {'p_lat': p.latitude, 'p_lng': p.longitude}); lastLoc = DateTime.now(); if (mounted) setState(() {}); } catch (_) {}
  }

  Future<void> toggleOnline() async {
    final on = me['online'] != true;
    if (on && me['has_avatar'] == false && avatar.length < 50) { hfToast(context, '📸 पहले अपनी प्रोफ़ाइल फ़ोटो लगाएँ — ग्राहक को दिखती है'); pickPhoto(); return; }
    setState(() => busy = true);
    try {
      final p = on ? await pos() : null;
      if (on && p == null) { if (mounted) hfToast(context, locMsg.isEmpty ? 'लोकेशन नहीं मिली' : locMsg); return; }
      final r = await Api.rpc('rider_set_online', {'p_online': on, 'p_lat': p?.latitude, 'p_lng': p?.longitude});
      if (r is Map && r['ok'] == false) {
        if (mounted) hfToast(context, r['code'] == 'photo_required' ? '📸 पहले प्रोफ़ाइल फ़ोटो लगाएँ' : (r['code'] == 'not_approved' ? '⏳ एडमिन की मंज़ूरी बाकी है' : 'नहीं हो पाया'));
        if (r['code'] == 'photo_required') pickPhoto();
        return;
      }
      HapticFeedback.mediumImpact();
      if (on) Sound.ding();
      await load(quiet: true);
      if (mounted) hfToast(context, on ? '🟢 आप ऑनलाइन हैं — रिक्वेस्ट आएँगी' : 'आप ऑफ़लाइन हैं');
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickPhoto() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front, maxWidth: 480, imageQuality: 70);
      if (f == null) return;
      final b = await f.readAsBytes();
      final data = 'data:image/jpeg;base64,${base64Encode(b)}';
      await Api.rpc('set_my_avatar', {'p_data': data});
      if (mounted) { setState(() => avatar = data); hfToast(context, 'फ़ोटो लग गई ✅'); }
      load(quiet: true);
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  // ---------- requests ----------
  void onAction(String act, String offerId) {
    if (act == 'accept') { respond(offerId, true); }
    else if (act == 'reject') { askReject(offerId); }
    else { load(quiet: true); }
  }

  Future<void> openOffer(Map<String, dynamic> o) async {
    shownOffers.add(o['id'].toString());
    offerOpen = true;
    Push.clear(o['id'].toString());
    var ringing = true;
    () async { while (ringing && mounted) { await Sound.ring3(); await Future.delayed(const Duration(milliseconds: 600)); } }();
    Map<String, dynamic>? route;
    try { final r = await Api.rpc('offer_route', {'p_offer_id': o['id']}).timeout(const Duration(seconds: 4)); if (r is Map) route = Map<String, dynamic>.from(r); } catch (_) {}
    if (!mounted) return;
    final res = await Navigator.of(context).push<String>(PageRouteBuilder(opaque: false, pageBuilder: (_, __, ___) => OfferScreen(offer: o, route: route), transitionsBuilder: (_, a, __, w) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: w)));
    ringing = false;
    Sound.stop();
    offerOpen = false;
    if (res == 'accept') { await respond(o['id'].toString(), true); }
    else if (res == 'reject') { await askReject(o['id'].toString()); }
  }

  Future<void> respond(String id, bool ok, {String? reason}) async {
    try {
      final r = ok ? await Api.rpc('respond_offer', {'p_offer_id': id, 'p_accept': true}) : await Api.rpc('reject_offer', {'p_offer_id': id, 'p_reason': reason ?? ''});
      Push.clear(id);
      if (!mounted) return;
      final m = {'accepted': '✅ ऑर्डर आपका — चलिए!', 'rejected': 'रिक्वेस्ट छोड़ी', 'expired': '⏱️ समय निकल गया', 'stock_gone': 'स्टॉक कम पड़ गया', 'invalid': 'यह रिक्वेस्ट अब नहीं है'}[r] ?? '$r';
      hfToast(context, m);
      if (r == 'accepted') { HapticFeedback.heavyImpact(); Sound.ding(); setState(() => nav = 0); }
      await load(quiet: true);
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  Future<void> askReject(String id) async {
    const reasons = [['far', '📍', 'बहुत दूर है'], ['vehicle', '🛵', 'गाड़ी में दिक्कत'], ['busy', '📦', 'दूसरा ऑर्डर चल रहा है'], ['break', '☕', 'अभी ब्रेक पर हूँ'], ['stock', '🍱', 'यह सामान मेरे पास नहीं'], ['other', '✍️', 'कुछ और']];
    final why = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: HF.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('रिक्वेस्ट क्यों छोड़ रहे हैं?', style: HF.num(20)),
            Text('वजह चुनें — ऑर्डर तुरंत अगले पार्टनर को चला जाएगा', style: HF.hi(12.5, color: HF.mut)),
            const SizedBox(height: 14),
            GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 3.1, children: [
              for (final r in reasons)
                GestureDetector(onTap: () => Navigator.pop(c, r[0]), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)), child: Row(children: [Text(r[1], style: const TextStyle(fontSize: 18)), const SizedBox(width: 8), Expanded(child: Text(r[2], style: HF.hi(13.5, w: FontWeight.w800)))]))),
            ]),
            const SizedBox(height: 12),
            GestureDetector(onTap: () => Navigator.pop(c, 'back'), child: Container(height: 52, alignment: Alignment.center, decoration: BoxDecoration(color: HF.ok, borderRadius: BorderRadius.circular(16)), child: Text('वापस — स्वीकार करना है', style: HF.hi(15, color: Colors.white, w: FontWeight.w800)))),
          ]),
        ),
      ),
    );
    if (why == null) return;
    if (why == 'back') { await respond(id, true); return; }
    await respond(id, false, reason: why);
  }

  // ---------- active delivery ----------
  Future<void> act(String fn, Map<String, dynamic> p, String okMsg) async {
    setState(() => busy = true);
    try {
      final r = await Api.rpc(fn, p);
      if (!mounted) return;
      if (r == false) { hfToast(context, fn == 'complete_delivery' ? '❌ OTP गलत है' : 'नहीं हो पाया'); Sound.stop(); }
      else { HapticFeedback.mediumImpact(); hfToast(context, okMsg); if (fn == 'complete_delivery') { Sound.ding(); loadHist(); otp.clear(); } }
      await load(quiet: true);
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final otp = TextEditingController();

  Future<void> scan(String orderId) async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (raw == null) return;
    await pickup(orderId, raw);
  }

  Future<void> pickup(String orderId, String raw) async {
    final m = RegExp(r'^HFPICK:([0-9a-fA-F-]{36}):(\d{6})$').firstMatch(raw.trim());
    String code;
    if (m != null) {
      if (m.group(1)!.toLowerCase() != orderId.toLowerCase()) { hfToast(context, 'यह स्लिप किसी दूसरे ऑर्डर की है'); return; }
      code = m.group(2)!;
    } else {
      final d = raw.replaceAll(RegExp(r'\D'), '');
      if (d.length < 6) { hfToast(context, 'यह Happy Food की स्लिप नहीं लगती'); return; }
      code = d.substring(d.length - 6);
    }
    try {
      final r = await Api.rpc('rider_pickup', {'p_order_id': orderId, 'p_code': code});
      if (!mounted) return;
      if (r is Map && r['ok'] == true) { Sound.ding(); HapticFeedback.heavyImpact(); hfToast(context, '✅ पिकअप हो गया — अब ग्राहक की ओर 🛵'); }
      else { hfToast(context, {'wrong_code': 'कोड मेल नहीं खाया', 'not_ready': 'दुकान ने अभी पैक नहीं किया', 'not_active': 'यह ऑर्डर अब आपके पास नहीं'}[r is Map ? r['code'] : ''] ?? 'पिकअप नहीं हुआ'); }
      await load(quiet: true);
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  Future<void> manualCode(String orderId) async {
    final c = TextEditingController();
    final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(
          title: Text('पिकअप कोड डालें', style: HF.hi(18, w: FontWeight.w800)),
          content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: HF.num(26).copyWith(letterSpacing: 8), decoration: const InputDecoration(counterText: '', hintText: '••••••')),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('रहने दें')), TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('पिकअप करें'))],
        ));
    if (v != null && v.trim().isNotEmpty) await pickup(orderId, v);
  }

  Future<void> cancelFlow(Map a) async {
    const rs = [['vehicle', '🛵', 'गाड़ी ख़राब हो गई'], ['accident', '🤕', 'दुर्घटना / तबियत'], ['item', '📦', 'सामान ख़राब / ख़त्म'], ['no_customer', '🚪', 'ग्राहक नहीं मिला'], ['refused', '🙅', 'ग्राहक ने मना किया'], ['other', '✍️', 'कुछ और']];
    final arrived = a['arrived_at'] != null;
    final note = TextEditingController();
    final why = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, backgroundColor: HF.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('डिलीवर नहीं हो पा रहा?', style: HF.num(20)),
          Text('ग्राहक न मिले या मना करे तो ऑर्डर बंद होगा; बाकी वजहों में अगले राइडर को जाएगा', style: HF.hi(12.5, color: HF.mut)),
          const SizedBox(height: 12),
          for (final r in rs)
            Opacity(
              opacity: (r[0] == 'no_customer' || r[0] == 'refused') && !arrived ? .45 : 1,
              child: ListTile(contentPadding: EdgeInsets.zero, leading: Text(r[1], style: const TextStyle(fontSize: 22)), title: Text(r[2], style: HF.hi(15, w: FontWeight.w800)), subtitle: (r[0] == 'no_customer' || r[0] == 'refused') && !arrived ? Text('पहले "पहुँच गया" दबाएँ', style: HF.hi(11.5, color: HF.mut)) : null,
                  onTap: (r[0] == 'no_customer' || r[0] == 'refused') && !arrived ? null : () => Navigator.pop(c, r[0])),
            ),
          TextField(controller: note, decoration: InputDecoration(hintText: 'थोड़ा लिखें (ज़रूरी नहीं)', filled: true, fillColor: HF.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
        ]),
      ),
    );
    if (why == null) return;
    try {
      final r = await Api.rpc('rider_cancel', {'p_order_id': a['id'], 'p_reason': why, 'p_note': note.text.trim()});
      if (!mounted) return;
      if (r is Map && r['ok'] == true) { hfToast(context, r['result'] == 'closed' ? 'ऑर्डर बंद किया — ग्राहक को सूचना गई' : 'ऑर्डर अगले राइडर को गया'); }
      else { hfToast(context, r is Map && r['code'] == 'wait' ? 'अभी ${((r['seconds_left'] ?? 0) / 60).ceil()} मिनट और इंतज़ार करें' : 'नहीं हो पाया'); }
      await load(quiet: true); loadHist();
    } catch (e) { if (mounted) hfToast(context, errText(e)); }
  }

  // ---------- ring while the phone is locked: battery optimisation must be off ----------
  Future<void> checkBattery() async {
    try { final ok = await Permission.ignoreBatteryOptimizations.isGranted; if (mounted) setState(() => batteryOk = ok); } catch (_) {}
  }

  Future<void> fixBattery() async {
    try {
      final r = await Permission.ignoreBatteryOptimizations.request();
      if (!r.isGranted) await openAppSettings();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));
    checkBattery();
  }

  // ---------- center button: scan any shop slip and take that order ----------
  Future<void> claimScan() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage(manual: true)));
    if (raw == null || !mounted) return;
    if (raw == 'MANUAL') { await manualClaim(); return; }
    await claim(raw, null);
  }

  Future<void> manualClaim() async {
    final a = TextEditingController(), c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('⌨️ स्लिप से नंबर डालें', style: HF.hi(18, w: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('स्लिप पर लिखा ऑर्डर नंबर (जैसे HF-0BF8) और 6 अंक का पिकअप कोड', style: HF.hi(12.5, color: HF.mut)),
            const SizedBox(height: 10),
            TextField(controller: a, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'ऑर्डर नंबर', hintText: 'HF-0BF8', filled: true, fillColor: HF.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
            const SizedBox(height: 10),
            TextField(controller: c, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: HF.num(22).copyWith(letterSpacing: 8), decoration: InputDecoration(counterText: '', labelText: 'पिकअप कोड', hintText: '••••••', filled: true, fillColor: HF.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('रहने दें')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('पिकअप करें'))],
        ));
    if (ok == true) await claim(a.text, c.text);
  }

  Future<void> claim(String raw, String? code) async {
    final a = me['active'];
    // my own active shop order: plain pickup
    final m = RegExp(r'HFPICK:([0-9a-fA-F-]{36}):(\d{4,8})').firstMatch(raw);
    if (a is Map && m != null && m.group(1)!.toLowerCase() == '${a['id']}'.toLowerCase()) { await pickup('${a['id']}', raw); return; }
    try {
      final r = await Api.rpc('rider_claim_pickup', {'p_raw': raw, 'p_code': code});
      if (!mounted) return;
      if (r is Map && r['ok'] == true) {
        Sound.ding(); HapticFeedback.heavyImpact();
        hfToast(context, r['claimed'] == true ? '✅ ऑर्डर आपका — पैकेट लिया, अब ग्राहक की ओर 🛵' : '✅ पिकअप हो गया');
        setState(() { nav = 0; seg = 0; });
      } else {
        hfToast(context, {
              'wrong_code': 'कोड / QR मेल नहीं खाया', 'not_ready': 'दुकान ने अभी "तैयार" नहीं दबाया', 'taken': 'यह ऑर्डर दूसरा पार्टनर ले चुका',
              'busy': 'पहले अपनी चालू डिलीवरी पूरी करें', 'not_open': 'यह ऑर्डर अब खुला नहीं है', 'bad_input': 'ऑर्डर नंबर और 6 अंक का कोड डालें',
              'not_allowed': 'आपका अकाउंट अभी मंज़ूर नहीं है', 'not_rider': 'पहले पार्टनर रजिस्ट्रेशन करें', 'not_found': 'ऑर्डर नहीं मिला'
            }[r is Map ? r['code'] : ''] ?? 'पिकअप नहीं हुआ');
      }
      await load(quiet: true); loadHist();
    } catch (e) { if (mounted) hfToast(context, errText(e)); }
  }

  // ---------- cash order but the customer pays by UPI: show the QR set by admin ----------
  Future<void> showUpiQr(Map a) async {
    Map? u;
    try { final r = await Api.rpc('delivery_upi', {'p_order_id': a['id']}); if (r is Map) u = r; } catch (e) { if (mounted) hfToast(context, errText(e)); return; }
    if (!mounted) return;
    if (u == null || '${u['vpa'] ?? ''}'.isEmpty) { hfToast(context, 'UPI ID अभी सेट नहीं है — एडमिन से कहें, अभी कैश लें'); return; }
    final amt = (u['amount'] ?? a['total'] ?? 0) as num;
    final url = 'upi://pay?pa=${Uri.encodeComponent('${u['vpa']}')}&pn=${Uri.encodeComponent('${u['payee'] ?? 'Happy Food'}')}&am=${amt.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent('Happy Food ${u['ref'] ?? ''}')}';
    final paid = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (c) => Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(c).padding.bottom),
        decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 5, decoration: BoxDecoration(color: HF.line, borderRadius: BorderRadius.circular(9))),
          const SizedBox(height: 14),
          Text('ग्राहक यह QR स्कैन करे', style: HF.hi(18, w: FontWeight.w800)),
          Text('${u!['payee']} • ${u['vpa']}', style: HF.hi(12.5, color: HF.mut)),
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.gold, width: 2)), child: QrImageView(data: url, size: 230, backgroundColor: Colors.white)),
          const SizedBox(height: 12),
          Text(rupee(amt), style: HF.num(34, color: HF.goldDeep)),
          Text('GPay • PhonePe • Paytm • कोई भी UPI ऐप', style: HF.hi(12, color: HF.mut)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => Navigator.pop(c, true),
            child: Container(height: 56, alignment: Alignment.center, decoration: BoxDecoration(color: HF.ok, borderRadius: BorderRadius.circular(18)), child: Text('✅ पेमेंट मिल गया', style: HF.hi(16, color: Colors.white, w: FontWeight.w800))),
          ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('वापस — कैश ही लूँगा', style: HF.hi(13.5, color: HF.mut))),
        ]),
      ),
    );
    if (paid == true) {
      try { await Api.rpc('rider_mark_upi', {'p_order_id': a['id']}); if (mounted) hfToast(context, '💳 UPI दर्ज — अब OTP लेकर डिलीवर करें'); } catch (e) { if (mounted) hfToast(context, errText(e)); }
      await load(quiet: true);
    }
  }

  Future<void> setMyUpi() async {
    final c = TextEditingController(text: '${me['upi_vpa'] ?? ''}');
    final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(
          title: Text('मेरी UPI ID', style: HF.hi(18, w: FontWeight.w800)),
          content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(hintText: 'naam@okaxis')),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('रहने दें')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('सेव'))],
        ));
    if (v == null) return;
    try { await Api.rpc('set_my_upi', {'p_kind': 'rider', 'p_vpa': v}); if (mounted) hfToast(context, '✅ UPI ID सेव'); await load(quiet: true); } catch (e) { if (mounted) hfToast(context, 'UPI ID सही नहीं लगती'); }
  }

  // ---------- UI (same layout as the prototype's partner panel) ----------
  int dayIdx = 0, seg = 0;
  String filter = 'all';
  final openCards = <String>{};
  final sc = ScrollController();
  bool mini = false;

  DateTime? _t(Map o, String k) => o[k] == null ? null : DateTime.tryParse(o[k].toString())?.toLocal();
  DateTime _d0(DateTime d) => DateTime(d.year, d.month, d.day);
  num _amt(Map o) => (o['total'] ?? 0) as num;
  bool _done(Map o) => o['status'] == 'delivered';

  List<Map<String, dynamic>> get _period {
    final now = DateTime.now();
    if (dayIdx == 7) return hist.where((o) { final t = _t(o, 'created_at'); return t != null && t.year == now.year && t.month == now.month; }).toList();
    final d0 = _d0(now).subtract(Duration(days: dayIdx));
    return hist.where((o) { final t = _t(o, 'created_at'); return t != null && _d0(t) == d0; }).toList();
  }

  String _dayLabel(int i) { final d = DateTime.now().subtract(Duration(days: i)); return i == 0 ? 'आज ${d.day}' : '${hiDays[d.weekday - 1]} ${d.day}'; }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: HF.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: HF.goldDeep,
          onRefresh: () async { await load(); await loadHist(); },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) { final m = n.metrics.pixels > 260; if (m != mini) setState(() => mini = m); return false; },
            child: ListView(controller: sc, padding: EdgeInsets.only(bottom: 110 + pad.bottom), children: nav == 2 ? _profile(pad.top) : _main(pad.top)),
          ),
        ),
        AnimatedPositioned(duration: const Duration(milliseconds: 260), left: 0, right: 0, top: mini && nav != 2 ? 0 : -140, child: _miniHeader(pad.top)),
        Positioned(left: 0, right: 0, bottom: 0, child: _nav(pad.bottom)),
      ]),
    );
  }

  List<Widget> _main(double top) {
    final a = me['active'] is Map ? Map<String, dynamic>.from(me['active']) : null;
    final stockLines = ((me['stock'] as List?) ?? []).whereType<Map>().where((x) => ((x['qty'] ?? 0) as num) > 0).toList();
    return [
      _hero(top),
      if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
      if (err.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('⚠️ $err', style: HF.hi(13, color: HF.bad))),
      if (!loading && me['approved'] == false) _banner('⏳ एडमिन की मंज़ूरी का इंतज़ार है। मंज़ूरी मिलते ही ऑनलाइन हो सकेंगे।', const Color(0xFFFFF7E6), const Color(0xFFFDBA74)),
      if (!loading && me['has_avatar'] == false && avatar.length < 50) GestureDetector(onTap: pickPhoto, child: _banner('📸 अपनी प्रोफ़ाइल फ़ोटो लगाएँ — इसके बिना ऑनलाइन नहीं हो सकते। यहाँ दबाएँ।', const Color(0xFFFEF2F2), const Color(0xFFFCA5A5))),
      if (!batteryOk) GestureDetector(onTap: fixBattery, child: _banner('🔔 फ़ोन लॉक होने पर भी घंटी बजे — यहाँ दबाकर "Allow / अनुमति दें" चुनें (बैटरी सेटिंग)', const Color(0xFFFFF7E6), const Color(0xFFFDBA74))),
      if (me['online'] == true && locMsg.isNotEmpty) _banner('📍 $locMsg', const Color(0xFFFEF2F2), const Color(0xFFFCA5A5)),
      if (a != null) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: _active(a)),
      if (a == null && !loading && me['online'] == true)
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF86EFAC))),
          child: Row(children: [const Text('📡', style: TextStyle(fontSize: 22)), const SizedBox(width: 10), Expanded(child: Text('नई रिक्वेस्ट का इंतज़ार — आते ही घंटी बजेगी, फ़ोन लॉक हो तब भी', style: HF.hi(12.5, color: const Color(0xFF166534), w: FontWeight.w700)))]),
        )),
      const SizedBox(height: 16),
      _days(),
      const SizedBox(height: 12),
      _tabs(stockLines.length),
      if (seg == 1) ..._stockList(stockLines) else ..._orderList(),
    ];
  }

  Widget _banner(String t, Color bg, Color br) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: HFCard(color: bg, border: br, child: Text(t, style: HF.hi(13.5, w: FontWeight.w700))));

  Widget _avImg(double s) {
    if (avatar.startsWith('data:image')) {
      try { return Image.memory(base64Decode(avatar.split(',').last), width: s, height: s, fit: BoxFit.cover); } catch (_) {}
    }
    final n = '${me['name'] ?? 'R'}'.trim();
    return Center(child: Text(n.isEmpty ? 'R' : n.characters.first.toUpperCase(), style: HF.num(s * .38, color: HF.ink)));
  }

  Widget _av(double s, {bool badge = true}) {
    final c = Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, gradient: HF.avGrad, border: Border.all(color: Colors.white.withValues(alpha: .85), width: s > 44 ? 3 : 2)), child: ClipOval(child: _avImg(s)));
    return GestureDetector(onTap: pickPhoto, child: badge ? withFlutterBadge(Stack(clipBehavior: Clip.none, children: [c, Positioned(right: -2, bottom: -2, child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: HF.gold, shape: BoxShape.circle), child: const Icon(Icons.photo_camera, size: 11, color: HF.ink)))]), s) : c);
  }

  Widget _duty({bool compact = false}) {
    final on = me['online'] == true;
    return GestureDetector(
      onTap: busy ? null : toggleOnline,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withValues(alpha: .18))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(duration: const Duration(milliseconds: 250), width: 42, height: 24, padding: const EdgeInsets.all(3), alignment: on ? Alignment.centerRight : Alignment.centerLeft, decoration: BoxDecoration(color: on ? HF.okBright : Colors.white24, borderRadius: BorderRadius.circular(99)), child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
          const SizedBox(width: 8),
          if (compact) Text(on ? 'ऑनलाइन' : 'ऑफ़', style: HF.hi(13, color: Colors.white, w: FontWeight.w800))
          else Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(busy ? '…' : (on ? 'ऑनलाइन' : 'ऑफ़लाइन'), style: HF.hi(13, color: Colors.white, w: FontWeight.w800)),
            Text(on ? (lastLoc.year > 2000 ? 'लोकेशन ${DateTime.now().difference(lastLoc).inSeconds} सेकंड पहले भेजी' : 'लोकेशन भेज रहे…') : 'ऑनलाइन होने को दबाएँ', style: HF.hi(10, color: Colors.white60, w: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  Widget _hero(double top) {
    final p = _period, del = p.where(_done).toList();
    final coll = del.fold<num>(0, (s, o) => s + _amt(o));
    final stock = ((me['stock'] as List?) ?? []).fold<num>(0, (s, x) => s + ((x['qty'] ?? 0) as num));
    final todayCash = hist.where((o) { final t = _t(o, 'delivered_at'); return _done(o) && t != null && _d0(t) == _d0(DateTime.now()); }).fold<num>(0, (s, o) => s + _amt(o));
    final label = dayIdx == 0 ? 'आज' : (dayIdx == 7 ? 'इस महीने' : _dayLabel(dayIdx));
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 18, 16, 18),
      decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)), gradient: HF.heroGrad, boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, 14))]),
      foregroundDecoration: BoxDecoration(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)), gradient: RadialGradient(center: const Alignment(.6, -1), radius: 1.2, colors: [HF.gold.withValues(alpha: .16), Colors.transparent], stops: const [0, .6])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _av(56),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${me['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(18, color: Colors.white, w: FontWeight.w800)),
            Text('डिलीवरी पार्टनर · ${me['vehicle'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: Colors.white60, w: FontWeight.w600)),
          ])),
          const SizedBox(width: 8),
          _duty(),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withValues(alpha: .07), border: Border.all(color: Colors.white.withValues(alpha: .14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('💰 मेरी कमाई · $label', style: HF.hi(12.5, color: Colors.white.withValues(alpha: .85), w: FontWeight.w600))),
              GestureDetector(onTap: _earnSheet, child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)), child: Text('हिसाब ›', style: HF.hi(12, color: const Color(0xFF86EFAC), w: FontWeight.w600)))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: GestureDetector(onTap: _earnSheet, child: Row(children: [
                Flexible(child: Text(rupee(coll), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(32, color: Colors.white, w: FontWeight.w700))),
                const SizedBox(width: 8),
                Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), shape: BoxShape.circle), child: const Icon(Icons.chevron_right, size: 14, color: Colors.white70)),
              ]))),
              GestureDetector(
                onTap: () => hfToast(context, 'पैसे निकालना जल्द आएगा — अभी कैश एडमिन के पास जमा करें'),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x4DF2B632), blurRadius: 14, offset: Offset(0, 6))]),
                    child: Row(children: [const Icon(Icons.arrow_downward, size: 14, color: HF.ink), const SizedBox(width: 6), Text('निकालें', style: HF.hi(12.5, color: HF.ink, w: FontWeight.w800))])),
              ),
            ]),
            Text('${del.length} डिलीवरी · ${p.length} ऑर्डर', style: HF.hi(11.5, color: Colors.white.withValues(alpha: .62), w: FontWeight.w500)),
            Container(
              margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .12)))),
              child: Row(children: [_stat('डिलीवरी', '${del.length}', first: true), _stat('कलेक्शन', rupee(coll)), _stat('स्टॉक बचा', '$stock नग')]),
            ),
          ]),
        ),
        if (todayCash > 0)
          Container(
            margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .25), borderRadius: BorderRadius.circular(16)),
            child: Text('💵 ${rupee(todayCash)} कैश आपके पास · जमा करना है', style: HF.hi(13, color: Colors.white, w: FontWeight.w700)),
          ),
      ]),
    );
  }

  Widget _stat(String l, String v, {bool first = false}) => Expanded(
        child: Container(
          padding: EdgeInsets.only(left: first ? 0 : 6, right: 6),
          decoration: BoxDecoration(border: first ? null : Border(left: BorderSide(color: Colors.white.withValues(alpha: .12)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HF.hi(10.5, color: Colors.white.withValues(alpha: .6), w: FontWeight.w500)), Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(14.5, color: Colors.white, w: FontWeight.w600))]),
        ),
      );

  Widget _miniHeader(double top) => Container(
        padding: EdgeInsets.fromLTRB(14, top + 10, 14, 12),
        decoration: const BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)), boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))]),
        child: Row(children: [
          _av(40, badge: false),
          const SizedBox(width: 12),
          const Text('💰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(rupee(_period.where(_done).fold<num>(0, (s, o) => s + _amt(o))), style: HF.num(19, color: Colors.white, w: FontWeight.w800)),
          const SizedBox(width: 6),
          Text(dayIdx == 0 ? 'आज की कमाई' : 'कमाई', style: HF.hi(11.5, color: Colors.white70, w: FontWeight.w600)),
          const Spacer(),
          _duty(compact: true),
        ]),
      );

  Widget _days() {
    final now = DateTime.now();
    final vals = List.generate(7, (i) { final d0 = _d0(now).subtract(Duration(days: i)); return hist.where((o) { final t = _t(o, 'created_at'); return t != null && _d0(t) == d0 && _done(o); }).fold<num>(0, (s, o) => s + _amt(o)); });
    final cnt = List.generate(7, (i) { final d0 = _d0(now).subtract(Duration(days: i)); return hist.where((o) { final t = _t(o, 'created_at'); return t != null && _d0(t) == d0 && _done(o); }).length; });
    final topv = vals.fold<num>(1, (a, b) => b > a ? b : a);
    Widget chip(int i, Widget child, {double pct = 0}) {
      final on = dayIdx == i;
      return GestureDetector(
        onTap: () => setState(() => dayIdx = i),
        child: Container(
          width: 62, margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.fromLTRB(3, 6, 3, 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: on ? null : HF.card, gradient: on ? const LinearGradient(begin: Alignment(-0.27, -1), end: Alignment(0.27, 1), colors: [HF.heroTop, HF.heroBottom]) : null, border: Border.all(color: on ? Colors.transparent : HF.line)),
          child: Stack(clipBehavior: Clip.none, children: [
            child,
            if (i < 7) Positioned(left: 5, right: 5, bottom: -5, child: Container(height: 2, decoration: BoxDecoration(color: HF.line, borderRadius: BorderRadius.circular(3)), alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: pct.clamp(0, 1).toDouble(), child: Container(decoration: BoxDecoration(color: HF.ok, borderRadius: BorderRadius.circular(3)))))),
          ]),
        ),
      );
    }
    return SizedBox(
      height: 70,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        for (var i = 0; i < 7; i++)
          chip(i, Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_dayLabel(i), style: HF.hi(11, color: dayIdx == i ? Colors.white : HF.tx, w: FontWeight.w800)),
            Text(shortRupee(vals[i]), style: HF.num(11, color: dayIdx == i ? const Color(0xFF86EFAC) : HF.ok, w: FontWeight.w900)),
            Text(cnt[i] == 0 ? '—' : '${cnt[i]} डिलीवरी', style: HF.hi(10.5, color: dayIdx == i ? Colors.white70 : HF.mut, w: FontWeight.w700)),
          ]), pct: vals[i] / topv),
        chip(7, Column(mainAxisSize: MainAxisSize.min, children: [const Text('🗓️', style: TextStyle(fontSize: 18)), Text('महीना', style: HF.hi(11, color: dayIdx == 7 ? Colors.white : HF.tx, w: FontWeight.w800))])),
      ]),
    );
  }

  Widget _tabs(int stockN) {
    Widget b(int i, String t, int n) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => seg = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              decoration: BoxDecoration(color: seg == i ? HF.card : Colors.transparent, borderRadius: BorderRadius.circular(16), boxShadow: seg == i ? const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))] : null),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(13, color: seg == i ? HF.tx : HF.mut, w: FontWeight.w800))),
                const SizedBox(width: 6),
                Container(constraints: const BoxConstraints(minWidth: 22), height: 22, padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(99)), child: Text('$n', style: HF.num(11.5, color: Colors.white, w: FontWeight.w800))),
              ]),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Color.alphaBlend(HF.goldDeep.withValues(alpha: .12), HF.card2), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [b(0, '🛵 डिलीवरी', _period.length), b(1, '📦 स्टॉक', stockN)]),
    );
  }

  List<Widget> _orderList() {
    final p = _period;
    final list = p.where((o) => filter == 'all' || (filter == 'live' ? !['delivered', 'cancelled', 'no_rider'].contains(o['status']) : ['delivered', 'cancelled', 'no_rider'].contains(o['status']))).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(children: [
          for (final f in [['all', 'सब'], ['live', 'चालू'], ['done', 'पूरे']])
            Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setState(() => filter = f[0]), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: filter == f[0] ? const Color(0xFF111111) : HF.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: filter == f[0] ? const Color(0xFF111111) : HF.line, width: 1.5)), child: Text(f[1], style: HF.hi(13, color: filter == f[0] ? Colors.white : HF.mut, w: FontWeight.w800))))),
          const Spacer(),
          Text('${list.length} / ${p.length}', style: HF.num(13, color: HF.mut, w: FontWeight.w700)),
        ]),
      ),
      if (list.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Column(children: [const Text('🛵', style: TextStyle(fontSize: 42)), Text('इस दिन कोई डिलीवरी नहीं', style: HF.hi(15, w: FontWeight.w800))])),
      for (final o in list) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: _card(o)),
    ];
  }

  // order source: shop pickup (vendor request) or app order from my own bag
  (IconData, String, Color) _src(Map o) => o['route'] == 'shop'
      ? (Icons.storefront_rounded, 'दुकान से पिकअप', const Color(0xFF2563EB))
      : (Icons.phone_android_rounded, 'ऐप ऑर्डर · मेरा स्टॉक', HF.goldDeep);

  List<(String, IconData, DateTime?)> _stepsOf(Map o) {
    final shop = o['route'] == 'shop', done = o['status'] == 'delivered';
    final picked = _t(o, 'picked_at') ?? (!shop && (done || o['status'] == 'on_the_way') ? _t(o, 'accepted_at') : null);
    return [
      ('स्वीकार', Icons.notifications_active_rounded, _t(o, 'accepted_at')),
      (shop ? 'दुकान से लिया' : 'पैक / लिया', shop ? Icons.storefront_rounded : Icons.inventory_2_rounded, picked),
      ('रास्ते में', Icons.two_wheeler_rounded, picked),
      ('पहुँचे', Icons.location_on_rounded, _t(o, 'arrived_at') ?? (done ? _t(o, 'delivered_at') : null)),
      ('डिलीवर', Icons.home_rounded, _t(o, 'delivered_at')),
    ];
  }

  Widget _card(Map<String, dynamic> o) {
    final id = o['id'].toString(), isOpen = openCards.contains(id);
    final lines = (o['lines'] as List?)?.whereType<Map>().toList() ?? [];
    final st = o['status'], done = st == 'delivered', cx = st == 'cancelled' || st == 'no_rider';
    final chip = cx ? ['रद्द', const Color(0xFFFEE2E2), const Color(0xFFB91C1C), Icons.cancel_rounded] : (done ? ['डिलीवर', const Color(0xFFDCFCE7), const Color(0xFF166534), Icons.check_circle_rounded] : (st == 'on_the_way' ? ['रास्ते में', const Color(0xFFDBEAFE), const Color(0xFF1E40AF), Icons.two_wheeler_rounded] : ['स्वीकार', const Color(0xFFFEF3C7), const Color(0xFF92400E), Icons.notifications_active_rounded]));
    final steps = _stepsOf(o);
    final cur = cx ? -1 : steps.indexWhere((s) => s.$3 == null);
    final when = _t(o, 'created_at'), src = _src(o);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => _zoom(lines, 0),
            child: SizedBox(width: 62, height: 60, child: Stack(clipBehavior: Clip.none, children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Color.alphaBlend(HF.goldDeep.withValues(alpha: .35), Colors.white), width: 3)), child: ClipOval(child: foodImg(o['image_url'], 50, 50, r: 0))),
              // where the order came from: shop request or app order from my bag
              Positioned(right: 0, bottom: -2, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: src.$3, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Icon(src.$1, size: 13, color: Colors.white))),
            ])),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o['customer'] ?? 'ग्राहक'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(17, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: chip[1] as Color, borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(chip[3] as IconData, size: 12, color: chip[2] as Color), const SizedBox(width: 4), Text(chip[0] as String, style: HF.hi(11, color: chip[2] as Color, w: FontWeight.w800))])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: src.$3.withValues(alpha: .1), borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(src.$1, size: 12, color: src.$3), const SizedBox(width: 4), Text(o['route'] == 'shop' ? (o['shop'] is Map ? '${o['shop']['name']}' : 'दुकान') : 'ऐप ऑर्डर', style: HF.hi(11, color: src.$3, w: FontWeight.w800))])),
              if (o['pay_mode'] == 'upi') Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(999)), child: Text('UPI', style: HF.num(10.5, color: HF.ok, w: FontWeight.w800))),
            ]),
            const SizedBox(height: 4),
            Text('${o['items'] ?? ''} • ${when == null ? '' : hm(when).toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(11, color: HF.mut, w: FontWeight.w600)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(cx ? '' : rupee(_amt(o)), style: HF.num(20, color: HF.goldDeep, w: FontWeight.w800)), Text(cx ? '—' : (o['pay_mode'] == 'upi' ? 'UPI' : 'कलेक्शन'), style: HF.hi(10, color: HF.mut, w: FontWeight.w900))]),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => isOpen ? openCards.remove(id) : openCards.add(id)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _steps(steps, cur, cx)),
            const SizedBox(width: 4),
            AnimatedRotation(turns: isOpen ? .5 : 0, duration: const Duration(milliseconds: 220), child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.keyboard_arrow_down, size: 16, color: HF.mut))),
          ]),
        ),
        AnimatedSize(duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: isOpen ? _expanded(o, lines, cx, steps) : const SizedBox(width: double.infinity)),
      ]),
    );
  }

  static const _okC = Color(0xFF16A34A);

  Widget _dot(IconData ic, bool done, bool now, {double s = 26}) => Container(
        width: s, height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? const Color(0xFFDCFCE7) : (now ? const Color(0xFFFDE68A) : HF.card2),
          border: Border.all(color: done ? _okC : (now ? HF.gold : HF.line), width: 1.6),
          boxShadow: now ? [BoxShadow(color: HF.gold.withValues(alpha: .3), spreadRadius: 3)] : null,
        ),
        child: Icon(ic, size: s * .52, color: done ? _okC : (now ? HF.goldDeep : HF.mut)),
      );

  Widget _steps(List<(String, IconData, DateTime?)> s, int cur, bool cx) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < s.length; i++)
          Expanded(child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            if (i > 0) Positioned(top: 12, left: 0, right: 0, child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .5, child: Container(height: 2.5, color: s[i].$3 != null ? _okC : (i == cur ? HF.gold : HF.line)))),
            if (i < s.length - 1) Positioned(top: 12, left: 0, right: 0, child: FractionallySizedBox(alignment: Alignment.centerRight, widthFactor: .5, child: Container(height: 2.5, color: s[i + 1].$3 != null ? _okC : (i + 1 == cur ? HF.gold : HF.line)))),
            Column(children: [
              _dot(cx && s[i].$3 == null ? Icons.close_rounded : s[i].$2, s[i].$3 != null, i == cur),
              const SizedBox(height: 4),
              Text(s[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(10, color: s[i].$3 != null ? HF.ok : (i == cur ? HF.goldDeep : HF.mut), w: FontWeight.w800)),
            ]),
          ])),
      ]);

  Widget _expanded(Map<String, dynamic> o, List<Map> lines, bool cx, List<(String, IconData, DateTime?)> steps) {
    final shop = o['shop'] is Map ? o['shop'] as Map : null;
    final subs = <String>[
      'आपने रिक्वेस्ट स्वीकार की',
      o['route'] == 'shop' ? 'QR स्कैन करके ${shop?['name'] ?? 'दुकान'} से पैकेट लिया' : 'अपने स्टॉक / बैग से सामान लिया',
      'ग्राहक की ओर निकले',
      'ग्राहक के पते पर पहुँचे',
      cx ? '${o['cancel_reason'] ?? 'ऑर्डर रद्द हुआ'}' : 'OTP से डिलीवरी पूरी${o['pay_mode'] == 'upi' ? ' • UPI से भुगतान' : ' • कैश लिया'}',
    ];
    final drop = ll(o['lat'], o['lng']), sh = shop == null ? null : ll(shop['lat'], shop['lng']);
    final rows = List.generate(steps.length, (i) => (steps[i].$1, steps[i].$2, steps[i].$3, subs[i]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      const Divider(height: 1),
      const SizedBox(height: 12),
      for (var i = 0; i < rows.length; i++)
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 30, child: Column(children: [
            _dot(cx && i == rows.length - 1 ? Icons.close_rounded : rows[i].$2, rows[i].$3 != null, false, s: 30),
            if (i < rows.length - 1) Expanded(child: Container(width: 2.5, margin: const EdgeInsets.symmetric(vertical: 2), color: rows[i + 1].$3 != null ? _okC : HF.line)),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(rows[i].$1, style: HF.hi(14, w: FontWeight.w800, color: rows[i].$3 != null ? HF.tx : HF.mut))),
                Text(rows[i].$3 != null ? hm(rows[i].$3!) : '—', style: HF.hi(12, color: rows[i].$3 != null ? HF.goldDeep : HF.mut, w: FontWeight.w800)),
              ]),
              Text(rows[i].$4, style: HF.hi(12, color: HF.mut, w: FontWeight.w600)),
              if (i == 1 && lines.isNotEmpty) Wrap(children: [for (var k = 0; k < lines.length && k < 6; k++) GestureDetector(onTap: () => _zoom(lines, k), child: Padding(padding: const EdgeInsets.only(right: 8, top: 6), child: Stack(clipBehavior: Clip.none, children: [ClipOval(child: foodImg(lines[k]['image_url'], 40, 40, r: 0)), Positioned(right: -4, bottom: -2, child: Container(width: 18, height: 18, alignment: Alignment.center, decoration: BoxDecoration(color: HF.tx, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('${lines[k]['qty']}', style: HF.num(9, color: Colors.white))))])))]),
            ]),
          )),
        ])),
      if ((o['address'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [const Icon(Icons.place_rounded, size: 16, color: HF.mut), const SizedBox(width: 6), Expanded(child: Text('${o['address']}', style: HF.hi(12, color: HF.mut, w: FontWeight.w700)))])),
      if (drop != null || sh != null)
        RouteMap(shop: sh, drop: drop, height: 150, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteMapPage(shop: sh, drop: drop, title: '${o['customer'] ?? 'ऑर्डर'} — रास्ता')))),
    ]);
  }

  /// Tap a product picture: big view with name, qty and price.
  void _zoom(List<Map> lines, int start) {
    if (lines.isEmpty) return;
    showDialog(context: context, builder: (c) => Dialog(
          backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(18),
          child: Container(
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(26)),
            padding: const EdgeInsets.all(14),
            child: SizedBox(height: 420, child: PageView(controller: PageController(initialPage: start), children: [
              for (final l in lines)
                Column(children: [
                  Expanded(child: foodImg(l['image_url'], double.infinity, double.infinity, r: 20)),
                  const SizedBox(height: 10),
                  Text('${l['name_hi'] ?? l['name'] ?? ''}', textAlign: TextAlign.center, style: HF.hi(18, w: FontWeight.w800)),
                  Text('${l['qty']} × ${rupee((l['price'] ?? 0) as num)} = ${rupee(((l['price'] ?? 0) as num) * ((l['qty'] ?? 0) as num))}', style: HF.num(16, color: HF.goldDeep)),
                  if (lines.length > 1) Text('← खिसकाकर अगला सामान →', style: HF.hi(11.5, color: HF.mut)),
                ]),
            ])),
          ),
        ));
  }

  List<Widget> _stockList(List<Map> s) => [
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 4), child: Text('जो सामान आपकी डिलीवरी-बैग में है। स्टॉक एडमिन / दुकान से भरा जाता है।', style: HF.hi(12, color: HF.mut, w: FontWeight.w600))),
        if (s.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text('📦 अभी कोई स्टॉक नहीं', style: HF.hi(14.5, color: HF.mut, w: FontWeight.w700)))),
        if (s.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .78, children: [
              for (final x in s)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.line)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Stack(children: [
                      Positioned.fill(child: foodImg(Api.products[x['product_id']]?['image_url'], double.infinity, double.infinity, r: 16)),
                      Positioned(left: 6, top: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: ((x['qty'] ?? 0) as num) <= 2 ? const Color(0xFFD97706) : const Color(0xFF16A34A), borderRadius: BorderRadius.circular(99)), child: Text('${x['qty']} नग', style: HF.hi(11, color: Colors.white, w: FontWeight.w800)))),
                    ])),
                    const SizedBox(height: 6),
                    Text(_nm(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(14, w: FontWeight.w800)),
                    Row(children: [Text(rupee((Api.products[x['product_id']]?['price'] ?? 0) as num), style: HF.num(14, color: HF.goldDeep, w: FontWeight.w800)), const Spacer(), if (((x['reserved'] ?? 0) as num) > 0) Text('${x['reserved']} आरक्षित', style: HF.hi(10.5, color: HF.mut))]),
                  ]),
                ),
            ]),
          ),
      ];

  void _earnSheet() {
    final now = DateTime.now();
    final week = List.generate(7, (k) { final i = 6 - k, d0 = _d0(now).subtract(Duration(days: i)); final v = hist.where((o) { final t = _t(o, 'created_at'); return t != null && _d0(t) == d0 && _done(o); }).fold<num>(0, (s, o) => s + _amt(o)); return (i == 0 ? 'आज' : hiDays[d0.weekday - 1], v); });
    final topv = week.fold<num>(1, (a, b) => b.$2 > a ? b.$2 : a);
    final todays = hist.where((o) { final t = _t(o, 'created_at'); return t != null && _d0(t) == _d0(now); }).toList();
    final del = todays.where(_done).toList(), sum = del.fold<num>(0, (s, o) => s + _amt(o));
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: .86, maxChildSize: .95, expand: false,
        builder: (_, ctl) => Container(
          decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
            Row(children: [Expanded(child: Text('आज की कमाई', style: HF.hi(19, w: FontWeight.w800))), GestureDetector(onTap: () => Navigator.pop(c), child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.close, size: 20)))]),
            const SizedBox(height: 14),
            Text('${del.length} डिलीवरी · ${todays.length} ऑर्डर', style: HF.hi(13, color: HF.mut, w: FontWeight.w600)),
            Text(rupee(sum), style: HF.num(34)),
            const SizedBox(height: 20),
            Row(children: [Expanded(child: Text('पिछले 7 दिन', style: HF.hi(14.5, w: FontWeight.w800))), Text(rupee(week.fold<num>(0, (s, w) => s + w.$2)), style: HF.num(15, color: HF.goldDeep, w: FontWeight.w800))]),
            const SizedBox(height: 10),
            Container(
              height: 140, padding: const EdgeInsets.fromLTRB(10, 12, 10, 8), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(week[i].$2 >= 1000 ? '${(week[i].$2 / 1000).toStringAsFixed(1)}k' : '${week[i].$2.round()}', style: HF.num(10.5, color: HF.mut, w: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Container(height: 4 + 70 * (week[i].$2 / topv).toDouble(), margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: i == 6 ? const Color(0xFFB07A12) : const Color(0xFFE6D3A8), borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 4),
                    Text(week[i].$1, style: HF.hi(10.5, color: i == 6 ? HF.tx : HF.mut, w: FontWeight.w800)),
                  ])),
              ]),
            ),
            const SizedBox(height: 20),
            Text('आज की डिलीवरी (${todays.length})', style: HF.hi(14.5, w: FontWeight.w800)),
            for (final o in todays)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HF.line))),
                child: Row(children: [
                  ClipOval(child: foodImg(o['image_url'], 44, 44, r: 0)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${o['customer'] ?? 'ग्राहक'}', style: HF.hi(14.5, w: FontWeight.w800)), Text('${o['items'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: HF.mut, w: FontWeight.w600))])),
                  Text(_done(o) ? '+${rupee(_amt(o))}' : rupee(_amt(o)), style: HF.num(15, color: _done(o) ? HF.ok : HF.mut, w: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  String _nm(Map i) => '${i['name_hi'] ?? i['name'] ?? Api.products[i['product_id']]?['name_hi'] ?? Api.products[i['product_id']]?['name'] ?? ''}';

  Widget _active(Map<String, dynamic> a) {
    final t = task['active'] is Map && task['active']['order_id'] == a['id'] ? Map<String, dynamic>.from(task['active']) : null;
    final shopNeed = t != null && t['picked'] != true;
    final st = a['status'];
    final items = (a['items'] as List?)?.whereType<Map>().toList() ?? [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.gold, width: 1.5), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Text('🛵 चालू डिलीवरी', style: HF.num(17)), const Spacer(), Pill(st == 'on_the_way' ? 'रास्ते में' : 'स्वीकार', bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF))]),
        const SizedBox(height: 10),
        _routeRow('📦', 'पिकअप', t == null ? 'आपके स्टॉक / बैग से' : '${t['shop']?['name'] ?? 'दुकान'} — ${t['shop']?['address'] ?? ''}'),
        _routeRow('🏠', 'डिलीवरी', '${a['customer'] ?? 'ग्राहक'} — ${a['address'] ?? ''}'),
        Builder(builder: (_) {
          final drop = ll(a['lat'], a['lng']);
          final sh = t != null && t['picked'] != true ? ll(t['shop']?['lat'], t['shop']?['lng']) : null;
          if (drop == null && sh == null) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 8), child: RouteMap(me: myPos, shop: sh, drop: drop, height: 170, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RouteMapPage(me: myPos, shop: sh, drop: drop, title: sh != null ? 'पहले दुकान, फिर ग्राहक' : 'ग्राहक का रास्ता')))));
        }),
        if (t != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: shopNeed ? const Color(0xFFFDF8EC) : const Color(0xFFECFDF3), borderRadius: BorderRadius.circular(18), border: Border.all(color: shopNeed ? HF.gold : const Color(0xFF86EFAC), width: 1.3)),
            child: shopNeed
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('🏪 पहले दुकान से पैकेट उठाएँ', style: HF.hi(12, color: HF.goldDeep, w: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Row(children: [
                      if ((t['shop']?['phone'] ?? '').toString().isNotEmpty) Expanded(child: _soft('📞 दुकान', () => _open('tel:+${t['shop']['phone']}'))),
                      if (t['shop']?['lat'] != null) ...[const SizedBox(width: 8), Expanded(child: _soft('🧭 रास्ता', () => _open('https://www.google.com/maps/dir/?api=1&destination=${t['shop']['lat']},${t['shop']['lng']}')))],
                    ]),
                    const SizedBox(height: 8),
                    Text(t['ready'] == true ? '✅ पैकेट तैयार — स्लिप का QR स्कैन करें' : '⏳ दुकान अभी पैक कर रही है…', style: HF.hi(13, color: t['ready'] == true ? HF.ok : HF.mut, w: FontWeight.w800)),
                    const SizedBox(height: 8),
                    GoldButton('📷 QR स्कैन करके पिकअप', onTap: () => scan(a['id'].toString())),
                    TextButton(onPressed: () => manualCode(a['id'].toString()), child: Text('⌨️ QR नहीं चल रहा? 6 अंक का कोड डालें', style: HF.hi(13, color: HF.goldDeep))),
                  ])
                : Text('✅ दुकान (${t['shop']?['name'] ?? ''}) से पैकेट उठा लिया', style: HF.hi(13.5, color: HF.ok, w: FontWeight.w800)),
          ),
        ],
        const SizedBox(height: 12),
        for (var k = 0; k < items.length; k++)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: GestureDetector(
            onTap: () => _zoom(items, k),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [foodImg(items[k]['image_url'], 50, 50, r: 14), Positioned(right: -5, top: -5, child: Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: HF.tx, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('${items[k]['qty']}', style: HF.num(10.5, color: Colors.white))))]),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_nm(items[k]), style: HF.hi(14.5, w: FontWeight.w800)), Text('${items[k]['qty']} × ${rupee((items[k]['price'] ?? 0) as num)}', style: HF.hi(12, color: HF.mut))])),
              Text(rupee(((items[k]['price'] ?? 0) as num) * ((items[k]['qty'] ?? 0) as num)), style: HF.num(14)),
            ]),
          )),
        const Divider(),
        a['pay_mode'] == 'upi'
            ? Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(14)), child: Row(children: [Expanded(child: Text('💳 ग्राहक ने UPI चुना — कैश मत लीजिए, ग्राहक के फ़ोन पर पेमेंट देख लें', style: HF.hi(12.5, color: const Color(0xFF166534), w: FontWeight.w800))), Text(rupee((a['total'] ?? 0) as num), style: HF.num(18, color: HF.ok))]))
            : Row(children: [Text('ग्राहक से लेना (COD)', style: HF.hi(13, color: HF.mut)), const Spacer(), Text(rupee((a['total'] ?? 0) as num), style: HF.num(20, color: HF.goldDeep))]),
        const SizedBox(height: 10),
        Row(children: [
          if ((a['customer_phone'] ?? '').toString().isNotEmpty) Expanded(child: _soft('📞 ग्राहक को कॉल', () => _open('tel:+${a['customer_phone']}'))),
          const SizedBox(width: 8),
          Expanded(child: _soft('🧭 रास्ता', () => _open('https://www.google.com/maps/dir/?api=1&destination=${a['lat']},${a['lng']}'))),
        ]),
        const SizedBox(height: 10),
        if (st == 'accepted' && !shopNeed) GoldButton(busy ? '…' : '🛵 निकल गया — रास्ते में', onTap: busy ? null : () => act('rider_start_trip', {'p_order_id': a['id']}, 'रास्ते में 🛵 — ग्राहक को सूचना गई')),
        if (st == 'on_the_way' && a['arrived_at'] == null) GoldButton('📍 ग्राहक के पास पहुँच गया', onTap: busy ? null : () => act('rider_arrived', {'p_order_id': a['id']}, '📍 पहुँच गए — ग्राहक को कॉल करें')),
        if (st == 'on_the_way' && a['pay_mode'] != 'upi') ...[
          const SizedBox(height: 10),
          GestureDetector(onTap: () => showUpiQr(a), child: Container(height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF93C5FD))), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.qr_code_2_rounded, color: Color(0xFF1D4ED8)), const SizedBox(width: 8), Text('ग्राहक UPI से देगा — QR दिखाएँ', style: HF.hi(14, color: const Color(0xFF1D4ED8), w: FontWeight.w800))]))),
        ],
        if (st == 'on_the_way') ...[
          const SizedBox(height: 10),
          Text('ग्राहक से 4 अंक का OTP लीजिए', style: HF.hi(13, w: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: otp, keyboardType: TextInputType.number, maxLength: 4, textAlign: TextAlign.center, style: HF.num(24).copyWith(letterSpacing: 10), decoration: InputDecoration(counterText: '', hintText: '••••', filled: true, fillColor: HF.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: busy ? null : () { if (otp.text.length != 4) { hfToast(context, '4 अंक का OTP डालिए'); return; } act('complete_delivery', {'p_order_id': a['id'], 'p_otp': otp.text}, '🎉 डिलीवर हो गया — शाबाश!'); },
              child: Container(height: 56, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, decoration: BoxDecoration(color: HF.ok, borderRadius: BorderRadius.circular(16)), child: Text('✅ डिलीवर', style: HF.hi(15.5, color: Colors.white, w: FontWeight.w800))),
            ),
          ]),
        ],
        TextButton(onPressed: () => cancelFlow(a), child: Text('⚠️ डिलीवर नहीं हो पा रहा? कैंसल / वजह बताएँ', style: HF.hi(13, color: HF.bad))),
      ]),
    );
  }

  Widget _routeRow(String ic, String l, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 30, height: 30, alignment: Alignment.center, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: Text(ic, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HF.hi(11, color: HF.mut, w: FontWeight.w800)), Text(v, style: HF.hi(13.5, w: FontWeight.w700))])),
        ]),
      );

  Widget _soft(String t, VoidCallback f) => GestureDetector(onTap: f, child: Container(height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: HF.line)), child: Text(t, style: HF.hi(13.5, w: FontWeight.w800))));

  Future<void> _open(String u) async { try { await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); } catch (_) {} }

  List<Widget> _profile(double top) => [
        SizedBox(height: top + 18),
        Center(child: _av(96)),
        const SizedBox(height: 10),
        Center(child: Text('${me['name'] ?? ''}', style: HF.num(22))),
        Center(child: Text('+${me['phone'] ?? ''} • ${me['vehicle'] ?? ''}', style: HF.hi(13, color: HF.mut))),
        Center(child: TextButton(onPressed: pickPhoto, child: Text('📸 फ़ोटो बदलें', style: HF.hi(14, color: HF.goldDeep)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: HFCard(padding: EdgeInsets.zero, child: Column(children: [
            _row('💳', 'मेरी UPI ID${(me['upi_vpa'] ?? '').toString().isEmpty ? '' : ' — ${me['upi_vpa']}'}', setMyUpi),
            _row('🔔', batteryOk ? 'लॉक फ़ोन पर घंटी — चालू ✅' : 'लॉक फ़ोन पर घंटी — चालू करें', fixBattery),
            _row('💬', 'Happy Food सपोर्ट (WhatsApp)', () => _open('https://wa.me/919540068380')),
            _row('📄', 'नियम व शर्तें', () => _open('https://filtara9811.github.io/happy-food-market/terms.html')),
            _row('🔒', 'प्राइवेसी पॉलिसी', () => _open('https://filtara9811.github.io/happy-food-market/privacy.html')),
            _row('🗑️', 'अकाउंट हटाने का अनुरोध', () => _open('https://filtara9811.github.io/happy-food-market/deletion.html')),
            _row('🚪', 'लॉग-आउट', () async { await Push.unregister(); await Api.signOut(); if (mounted) goNext(context); }),
          ])),
        ),
        const SizedBox(height: 22),
        Center(child: Text('P O W E R E D   B Y', style: HF.hi(11, color: const Color(0xFFB98A2C), w: FontWeight.w800))),
        const Center(child: Text('Filipra Private Limited', style: TextStyle(fontFamily: 'serif', fontSize: 22, fontWeight: FontWeight.w700, color: HF.tx))),
        Center(child: Text('© 2026 Happy Food · Made in India 🇮🇳', style: HF.hi(12, color: HF.mut))),
      ];

  Widget _row(String ic, String t, VoidCallback f) => ListTile(leading: Text(ic, style: const TextStyle(fontSize: 20)), title: Text(t, style: HF.hi(14.5, w: FontWeight.w700)), trailing: const Icon(Icons.chevron_right), onTap: f);

  // bottom bar: डिलीवरी | 📷 स्कैन (shop slip QR) | प्रोफ़ाइल
  Widget _nav(double bottom) => SizedBox(
        height: 72 + bottom + 24,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Container(
            height: 72 + bottom, padding: EdgeInsets.fromLTRB(22, 0, 22, 10 + bottom),
            decoration: const BoxDecoration(color: HF.card, border: Border(top: BorderSide(color: HF.line)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, -8))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_nb(0, Icons.two_wheeler, 'डिलीवरी'), _nb(2, Icons.person_outline, 'प्रोफ़ाइल')]),
          ),
          Positioned(
            bottom: 12 + bottom,
            child: GestureDetector(
              onTap: claimScan,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 54, height: 54, decoration: BoxDecoration(shape: BoxShape.circle, gradient: HF.navGrad, border: Border.all(color: HF.card, width: 4), boxShadow: const [BoxShadow(color: Color(0x73E2A92C), blurRadius: 18, offset: Offset(0, 8))]), child: const Icon(Icons.qr_code_scanner_rounded, size: 27, color: HF.ink)),
                const SizedBox(height: 4),
                Text('स्कैन करें', style: HF.hi(11, color: HF.goldDeep, w: FontWeight.w800)),
              ]),
            ),
          ),
        ]),
      );

  Widget _nb(int i, IconData ic, String l) {
    final on = nav == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { setState(() { nav = i; mini = false; if (i == 0) seg = 0; }); if (sc.hasClients) sc.jumpTo(0); if (i == 0) loadHist(); },
      child: SizedBox(
        width: 96,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          if (on) Positioned(top: -12, child: Container(width: 28, height: 3, decoration: BoxDecoration(color: HF.goldDeep, borderRadius: BorderRadius.circular(3)))),
          Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic, size: 24, color: on ? HF.goldDeep : HF.mut), const SizedBox(height: 4), Text(l, style: HF.hi(11.5, color: on ? HF.goldDeep : HF.mut, w: FontWeight.w700))]),
        ]),
      ),
    );
  }
}

/// Big in-app request screen: picture of every item (tap to enlarge), pickup + drop, money, countdown,
/// one big green Accept button and a small red ✕ in the corner.
class OfferScreen extends StatefulWidget {
  final Map<String, dynamic> offer;
  final Map<String, dynamic>? route;
  const OfferScreen({super.key, required this.offer, this.route});
  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> with SingleTickerProviderStateMixin {
  late int left = (widget.offer['seconds_left'] ?? 60) as int;
  late final int total = left < 1 ? 60 : left;
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Timer? t;

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => left--);
      if (left <= 0) { t?.cancel(); Navigator.pop(context, 'timeout'); }
    });
  }

  @override
  void dispose() { t?.cancel(); pulse.dispose(); super.dispose(); }

  void _zoom(List<Map> items, int k) {
    showDialog(context: context, builder: (c) => Dialog(
          backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(18),
          child: Container(
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(26)), padding: const EdgeInsets.all(14),
            child: SizedBox(height: 400, child: PageView(controller: PageController(initialPage: k), children: [
              for (final l in items) Column(children: [
                Expanded(child: foodImg(l['image_url'], double.infinity, double.infinity, r: 20)),
                const SizedBox(height: 10),
                Text('${l['name_hi'] ?? l['name'] ?? ''}', textAlign: TextAlign.center, style: HF.hi(18, w: FontWeight.w800)),
                Text('${l['qty']} × ${rupee((l['price'] ?? 0) as num)}', style: HF.num(16, color: HF.goldDeep)),
              ]),
            ])),
          ),
        ));
  }

  Widget _leg(String ic, String l, String v, String? km) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: Text(ic, style: const TextStyle(fontSize: 16))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HF.hi(11, color: HF.mut, w: FontWeight.w800)), Text(v, maxLines: 2, overflow: TextOverflow.ellipsis, style: HF.hi(13.5, w: FontWeight.w700))])),
        if (km != null) Text('$km km', style: HF.num(13, color: HF.goldDeep, w: FontWeight.w800)),
      ]);

  @override
  Widget build(BuildContext context) {
    final o = widget.offer, items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final r = widget.route ?? {}, shop = r['shop'] is Map ? r['shop'] as Map : null;
    final n = items.fold<num>(0, (s, i) => s + ((i['qty'] ?? 0) as num));
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .8),
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(30), border: Border.all(color: HF.gold, width: 2), boxShadow: const [BoxShadow(color: Color(0x66E2A92C), blurRadius: 40)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ScaleTransition(scale: Tween(begin: .92, end: 1.08).animate(pulse), child: Container(width: 52, height: 52, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFDE68A), Color(0xFFE2A92C)])), child: const Text('🔔', style: TextStyle(fontSize: 26)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('नई डिलीवरी!', style: HF.num(23)),
                  Text('$n सामान • ${(((o['distance_m'] ?? 0) as num) / 1000).toStringAsFixed(1)} km दूर', style: HF.hi(12.5, color: HF.mut)),
                ])),
                SizedBox(width: 50, height: 50, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: left / total, strokeWidth: 5, color: left <= 10 ? HF.bad : HF.gold, backgroundColor: HF.card2),
                  Text('$left', style: HF.num(16)),
                ])),
                const SizedBox(width: 8),
                // small red ✕ (decline) in the corner
                GestureDetector(onTap: () => Navigator.pop(context, 'reject'), child: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFCA5A5))), child: const Icon(Icons.close, color: HF.bad, size: 22))),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal, itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, k) => GestureDetector(
                    onTap: () => _zoom(items, k),
                    child: SizedBox(width: 74, child: Column(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        foodImg(items[k]['image_url'], 64, 64, r: 18),
                        Positioned(right: -6, top: -6, child: Container(constraints: const BoxConstraints(minWidth: 24), height: 24, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: HF.tx, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 2)), child: Text('×${items[k]['qty']}', style: HF.num(10.5, color: Colors.white)))),
                      ]),
                      const SizedBox(height: 4),
                      Text('${items[k]['name_hi'] ?? items[k]['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(11, w: FontWeight.w700)),
                    ])),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFDF8EC), borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  _leg(shop != null ? '🏪' : '📦', 'पिकअप', shop != null ? '${shop['name'] ?? ''} — ${shop['address'] ?? ''}' : 'आपके स्टॉक / बैग से', shop?['km']?.toString()),
                  Padding(padding: const EdgeInsets.only(left: 16), child: Container(width: 2, height: 12, color: HF.gold)),
                  _leg('🏠', 'डिलीवरी', '${r['drop_address'] ?? 'ग्राहक का पता स्वीकार करने पर'}', r['drop_km']?.toString()),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [Text(o['pay_mode'] == 'upi' ? '💳 UPI पेमेंट (कैश नहीं)' : 'ग्राहक से लेना (COD)', style: HF.hi(13, color: o['pay_mode'] == 'upi' ? HF.ok : HF.mut)), const Spacer(), Text(rupee((o['total'] ?? 0) as num), style: HF.num(24, color: HF.goldDeep))]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => Navigator.pop(context, 'accept'),
                child: Container(
                  height: 64, alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF15803D)]), borderRadius: BorderRadius.circular(22), boxShadow: const [BoxShadow(color: Color(0x6616A34A), blurRadius: 22, offset: Offset(0, 10))]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 34, height: 34, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white)),
                    const SizedBox(width: 12),
                    Text('Accept', style: HF.num(22, color: Colors.white, w: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('• स्वीकार करें', style: HF.hi(15, color: Colors.white70, w: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class ScanPage extends StatefulWidget {
  final bool manual;
  const ScanPage({super.key, this.manual = false});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ctl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128]);
  bool done = false;

  @override
  void dispose() { ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          MobileScanner(controller: ctl, onDetect: (cap) {
            if (done) return;
            final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
            if (v == null || v.isEmpty) return;
            done = true;
            HapticFeedback.mediumImpact();
            Navigator.pop(context, v);
          }),
          Center(child: Container(width: 260, height: 260, decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.goldLight, width: 4)))),
          SafeArea(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Expanded(child: Text('स्लिप का QR फ्रेम में रखें', style: HF.hi(16, color: Colors.white, w: FontWeight.w800))),
            IconButton(onPressed: () => ctl.toggleTorch(), icon: const Icon(Icons.flash_on, color: Colors.white)),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
          ]))),
          if (widget.manual)
            Positioned(left: 20, right: 20, bottom: 40, child: SafeArea(child: GestureDetector(
              onTap: () => Navigator.pop(context, 'MANUAL'),
              child: Container(height: 54, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Text('⌨️ QR नहीं चल रहा? नंबर से डालें', style: HF.hi(15, w: FontWeight.w800))),
            ))),
        ]),
      );
}
