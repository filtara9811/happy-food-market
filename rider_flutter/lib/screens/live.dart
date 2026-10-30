import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../main.dart';
import '../push.dart';
import '../sound.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    Api.loadProducts().then((_) { if (mounted) setState(() {}); }).catchError((_) {});
    poll = Timer.periodic(const Duration(seconds: 3), (_) => load(quiet: true));
    locT = Timer.periodic(const Duration(seconds: 15), (_) => sendLoc());
    Push.register();
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
    try { final h = await Api.history(7); final l = (h['orders'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? []; if (mounted) setState(() => hist = l); } catch (_) {}
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
    final shop = task['offer'] is Map && task['offer']['order_id'] == o['order_id'] ? Map<String, dynamic>.from(task['offer']['shop'] ?? {}) : null;
    final res = await Navigator.of(context).push<String>(PageRouteBuilder(opaque: false, pageBuilder: (_, __, ___) => OfferScreen(offer: o, shop: shop), transitionsBuilder: (_, a, __, w) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: w)));
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

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: HF.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: HF.goldDeep,
          onRefresh: () async { await load(); await loadHist(); },
          child: ListView(padding: EdgeInsets.only(bottom: 110 + pad.bottom), children: [
            _hero(pad.top),
            if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('⚠️ $err', style: HF.hi(13, color: HF.bad))),
            if (!loading && me['approved'] == false) _banner('⏳ एडमिन की मंज़ूरी का इंतज़ार है। मंज़ूरी मिलते ही ऑनलाइन हो सकेंगे।', const Color(0xFFFFF7E6), const Color(0xFFFDBA74)),
            if (!loading && me['has_avatar'] == false && avatar.length < 50) GestureDetector(onTap: pickPhoto, child: _banner('📸 अपनी प्रोफ़ाइल फ़ोटो लगाएँ — इसके बिना ऑनलाइन नहीं हो सकते। यहाँ दबाएँ।', const Color(0xFFFEF2F2), const Color(0xFFFCA5A5))),
            if (me['online'] == true && locMsg.isNotEmpty) _banner('📍 $locMsg', const Color(0xFFFEF2F2), const Color(0xFFFCA5A5)),
            if (nav == 0) ..._deliveries() else if (nav == 1) ..._stock() else ..._profile(),
          ]),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottom(pad.bottom)),
      ]),
    );
  }

  Widget _banner(String t, Color bg, Color br) => Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: HFCard(color: bg, border: br, child: Text(t, style: HF.hi(13.5, w: FontWeight.w700))));

  Widget _av(double s) {
    Widget img;
    if (avatar.startsWith('data:image')) {
      try { img = Image.memory(base64Decode(avatar.split(',').last), width: s, height: s, fit: BoxFit.cover); } catch (_) { img = const SizedBox(); }
    } else {
      final n = '${me['name'] ?? 'R'}'.trim();
      img = Center(child: Text(n.isEmpty ? 'R' : n.characters.first.toUpperCase(), style: HF.num(s * .4, color: HF.ink)));
    }
    return GestureDetector(
      onTap: pickPhoto,
      child: withFlutterBadge(Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)]), border: Border.all(color: const Color(0xFFFDE68A), width: 3)), child: ClipOval(child: img)), s),
    );
  }

  Widget _hero(double top) {
    final on = me['online'] == true, today = (me['today'] as Map?) ?? {};
    final stock = ((me['stock'] as List?) ?? []).fold<num>(0, (s, x) => s + ((x['qty'] ?? 0) as num));
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 18),
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [HF.heroTop, HF.heroBottom]), borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _av(56),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${me['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(19, color: Colors.white)),
            Text('डिलीवरी पार्टनर · ${me['vehicle'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: Colors.white60, w: FontWeight.w500)),
          ])),
          GestureDetector(
            onTap: busy ? null : toggleOnline,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withValues(alpha: .18))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(duration: const Duration(milliseconds: 250), width: 42, height: 24, padding: const EdgeInsets.all(3), alignment: on ? Alignment.centerRight : Alignment.centerLeft, decoration: BoxDecoration(color: on ? const Color(0xFF22C55E) : Colors.white24, borderRadius: BorderRadius.circular(99)), child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(busy ? '…' : (on ? 'ऑनलाइन' : 'ऑफ़लाइन'), style: HF.hi(13, color: Colors.white, w: FontWeight.w800)),
                  Text(on ? (lastLoc.year > 2000 ? 'लोकेशन ${DateTime.now().difference(lastLoc).inSeconds} से. पहले' : 'लोकेशन भेज रहे…') : 'ऑनलाइन होने को दबाएँ', style: HF.hi(10, color: Colors.white60, w: FontWeight.w600)),
                ]),
              ]),
            ),
          ),
        ]),
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withValues(alpha: .07), border: Border.all(color: Colors.white.withValues(alpha: .14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('💰 आज का कलेक्शन', style: HF.hi(12.5, color: Colors.white70, w: FontWeight.w600)),
            Text(rupee((today['total'] ?? 0) as num), style: HF.num(32, color: Colors.white, w: FontWeight.w700)),
            Text('${today['count'] ?? 0} डिलीवरी आज', style: HF.hi(11.5, color: Colors.white60, w: FontWeight.w500)),
            const Divider(color: Colors.white12, height: 20),
            Row(children: [
              _hs('डिलीवरी', '${today['count'] ?? 0}'),
              _hs('कलेक्शन', rupee((today['total'] ?? 0) as num)),
              _hs('स्टॉक बचा', '$stock नग'),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _hs(String l, String v) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HF.hi(10.5, color: Colors.white54, w: FontWeight.w500)), Text(v, style: HF.num(14.5, color: Colors.white, w: FontWeight.w600))]));

  String _nm(Map i) => '${i['name_hi'] ?? i['name'] ?? Api.products[i['product_id']]?['name_hi'] ?? Api.products[i['product_id']]?['name'] ?? ''}';

  Widget _img(dynamic url, double s) {
    final u = (url ?? '').toString();
    final ph = Container(width: s, height: s, color: const Color(0xFFFFF3D6), alignment: Alignment.center, child: Text('🍛', style: TextStyle(fontSize: s * .45)));
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: u.startsWith('http') ? Image.network(u, width: s, height: s, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph) : ph);
  }

  List<Widget> _deliveries() {
    final a = me['active'] is Map ? Map<String, dynamic>.from(me['active']) : null;
    return [
      if (a != null) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: _active(a)),
      if (a == null && !loading)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: HFCard(child: Column(children: [
            Text(me['online'] == true ? '📡' : '😴', style: const TextStyle(fontSize: 40)),
            Text(me['online'] == true ? 'नई रिक्वेस्ट का इंतज़ार…' : 'आप ऑफ़लाइन हैं', style: HF.hi(16, w: FontWeight.w800)),
            Text(me['online'] == true ? 'रिक्वेस्ट आते ही घंटी बजेगी — फ़ोन लॉक हो तब भी' : 'ऊपर "ऑफ़लाइन" दबाकर ऑनलाइन हों', textAlign: TextAlign.center, style: HF.hi(12.5, color: HF.mut)),
          ])),
        ),
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 6), child: Row(children: [Text('🧾 पिछली डिलीवरी', style: HF.hi(15, w: FontWeight.w800)), const Spacer(), Text('7 दिन • ${hist.length}', style: HF.hi(12, color: HF.mut))])),
      if (hist.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('अभी कोई डिलीवरी नहीं', style: HF.hi(13.5, color: HF.mut)))),
      for (final o in hist) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: _histCard(o)),
    ];
  }

  Widget _active(Map<String, dynamic> a) {
    final t = task['active'] is Map && task['active']['order_id'] == a['id'] ? Map<String, dynamic>.from(task['active']) : null;
    final shopNeed = t != null && t['picked'] != true;
    final st = a['status'];
    final items = (a['items'] as List?)?.whereType<Map>().toList() ?? [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.gold, width: 1.5), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('🛵 चालू डिलीवरी', style: HF.num(17)),
          const Spacer(),
          Pill(st == 'on_the_way' ? 'रास्ते में' : 'स्वीकार', bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF)),
        ]),
        if (t != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: shopNeed ? const Color(0xFFFDF8EC) : const Color(0xFFECFDF3), borderRadius: BorderRadius.circular(18), border: Border.all(color: shopNeed ? HF.gold : const Color(0xFF86EFAC), width: 1.3)),
            child: shopNeed
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('🏪 पहले दुकान से पैकेट उठाएँ', style: HF.hi(12, color: HF.goldDeep, w: FontWeight.w900)),
                    Text('${t['shop']?['name'] ?? ''}', style: HF.hi(16, w: FontWeight.w800)),
                    Text('📍 ${t['shop']?['address'] ?? ''}', style: HF.hi(12.5, color: HF.mut)),
                    const SizedBox(height: 8),
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
        for (final i in items)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            _img(i['image_url'], 44),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_nm(i), style: HF.hi(14, w: FontWeight.w800)), Text('${i['qty']} × ${rupee((i['price'] ?? 0) as num)}', style: HF.hi(12, color: HF.mut))])),
            Text(rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num)), style: HF.num(14)),
          ])),
        const Divider(),
        Row(children: [Text('ग्राहक से लेना (COD)', style: HF.hi(13, color: HF.mut)), const Spacer(), Text(rupee((a['total'] ?? 0) as num), style: HF.num(20, color: HF.goldDeep))]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['customer'] ?? 'ग्राहक'}', style: HF.hi(15, w: FontWeight.w800)),
            Text('📍 ${a['address'] ?? ''}', style: HF.hi(12.5, color: HF.mut)),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if ((a['customer_phone'] ?? '').toString().isNotEmpty) Expanded(child: _soft('📞 कॉल करें', () => _open('tel:+${a['customer_phone']}'))),
          const SizedBox(width: 8),
          Expanded(child: _soft('🧭 रास्ता', () => _open('https://www.google.com/maps/dir/?api=1&destination=${a['lat']},${a['lng']}'))),
        ]),
        const SizedBox(height: 10),
        if (st == 'accepted' && !shopNeed) GoldButton(busy ? '…' : '🛵 निकल गया — रास्ते में', onTap: busy ? null : () => act('rider_start_trip', {'p_order_id': a['id']}, 'रास्ते में 🛵 — ग्राहक को सूचना गई')),
        if (st == 'on_the_way' && a['arrived_at'] == null) GoldButton('📍 ग्राहक के पास पहुँच गया', onTap: busy ? null : () => act('rider_arrived', {'p_order_id': a['id']}, '📍 पहुँच गए — ग्राहक को कॉल करें')),
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

  Widget _soft(String t, VoidCallback f) => GestureDetector(onTap: f, child: Container(height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: HF.line)), child: Text(t, style: HF.hi(13.5, w: FontWeight.w800))));

  Future<void> _open(String u) async { try { await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); } catch (_) {} }

  Widget _histCard(Map<String, dynamic> o) {
    final done = o['status'] == 'delivered', cx = o['status'] == 'cancelled';
    final t = DateTime.tryParse('${o['created_at']}')?.toLocal();
    return HFCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        _img(o['image_url'], 52),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${o['customer'] ?? 'ग्राहक'}', style: HF.hi(15, w: FontWeight.w800)),
          Text('${o['items'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: HF.mut)),
          Text('${t == null ? '' : '${t.day}/${t.month} ${hm(t)}'} • ${done ? '✅ डिलीवर' : (cx ? '✖ रद्द' : '${o['status']}')}', style: HF.hi(11.5, color: done ? HF.ok : (cx ? HF.bad : HF.mut))),
        ])),
        Text(rupee((o['total'] ?? 0) as num), style: HF.num(16, color: HF.goldDeep)),
      ]),
    );
  }

  List<Widget> _stock() {
    final s = ((me['stock'] as List?) ?? []).whereType<Map>().toList();
    return [
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 6), child: Text('📦 मेरा स्टॉक', style: HF.hi(16, w: FontWeight.w800))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text('जो सामान आपकी डिलीवरी-बैग में है। स्टॉक एडमिन / दुकान से भरा जाता है।', style: HF.hi(12.5, color: HF.mut))),
      if (s.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Center(child: Text('अभी कोई स्टॉक नहीं', style: HF.hi(14, color: HF.mut)))),
      for (final x in s)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: HFCard(padding: const EdgeInsets.all(12), child: Row(children: [
            _img(Api.products[x['product_id']]?['image_url'], 48),
            const SizedBox(width: 10),
            Expanded(child: Text(_nm(x), style: HF.hi(15, w: FontWeight.w800))),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${x['qty']} नग', style: HF.num(17)), if (((x['reserved'] ?? 0) as num) > 0) Text('${x['reserved']} आरक्षित', style: HF.hi(11, color: HF.mut))]),
          ])),
        ),
    ];
  }

  List<Widget> _profile() => [
        const SizedBox(height: 18),
        Center(child: _av(96)),
        const SizedBox(height: 10),
        Center(child: Text('${me['name'] ?? ''}', style: HF.num(22))),
        Center(child: Text('+${me['phone'] ?? ''} • ${me['vehicle'] ?? ''}', style: HF.hi(13, color: HF.mut))),
        Center(child: TextButton(onPressed: pickPhoto, child: Text('📸 फ़ोटो बदलें', style: HF.hi(14, color: HF.goldDeep)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: HFCard(padding: EdgeInsets.zero, child: Column(children: [
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

  Widget _bottom(double b) {
    Widget nb(int i, IconData ic, String l) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () { setState(() => nav = i); if (i == 0) loadHist(); },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 28, height: 3, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: nav == i ? HF.goldDeep : Colors.transparent, borderRadius: BorderRadius.circular(3))),
              Icon(ic, color: nav == i ? HF.goldDeep : HF.mut),
              const SizedBox(height: 3),
              Text(l, style: HF.hi(12, color: nav == i ? HF.goldDeep : HF.mut)),
            ]),
          ),
        );
    return Container(
      padding: EdgeInsets.only(bottom: 10 + b, top: 0),
      decoration: const BoxDecoration(color: HF.card, border: Border(top: BorderSide(color: HF.line)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -6))]),
      child: Row(children: [nb(0, Icons.two_wheeler, 'डिलीवरी'), nb(1, Icons.inventory_2_outlined, 'मेरा स्टॉक'), nb(2, Icons.person_outline, 'प्रोफ़ाइल')]),
    );
  }
}

/// Big in-app request screen (when the app is open): items, money, shop, countdown, red / green buttons.
class OfferScreen extends StatefulWidget {
  final Map<String, dynamic> offer;
  final Map<String, dynamic>? shop;
  const OfferScreen({super.key, required this.offer, this.shop});
  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  late int left = (widget.offer['seconds_left'] ?? 60) as int;
  late final int total = left < 1 ? 60 : left;
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
  void dispose() { t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer, items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .78),
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(30), border: Border.all(color: HF.gold, width: 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(width: 56, height: 56, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFDE68A), Color(0xFFE2A92C)])), child: const Text('🔔', style: TextStyle(fontSize: 28))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('नई डिलीवरी!', style: HF.num(24)),
                  Text('${(((o['distance_m'] ?? 0) as num) / 1000).toStringAsFixed(1)} km दूर', style: HF.hi(13, color: HF.mut)),
                ])),
                SizedBox(width: 56, height: 56, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: left / total, strokeWidth: 5, color: left <= 10 ? HF.bad : HF.gold, backgroundColor: HF.card2),
                  Text('$left', style: HF.num(18)),
                ])),
              ]),
              if (widget.shop != null) ...[
                const SizedBox(height: 12),
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFDF8EC), borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.gold)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('🏪 दुकान से उठाना है', style: HF.hi(12, color: HF.goldDeep, w: FontWeight.w900)),
                  Text('${widget.shop!['name'] ?? ''}', style: HF.hi(15, w: FontWeight.w800)),
                  Text('📍 ${widget.shop!['address'] ?? ''}', style: HF.hi(12, color: HF.mut)),
                ])),
              ],
              const SizedBox(height: 12),
              for (final i in items)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
                  Expanded(child: Text('${i['qty']}× ${i['name_hi'] ?? i['name']}', style: HF.hi(15, w: FontWeight.w800))),
                  Text(rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num)), style: HF.num(15)),
                ])),
              Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)), child: Row(children: [Text('ग्राहक से लेना (COD)', style: HF.hi(13, color: HF.mut)), const Spacer(), Text(rupee((o['total'] ?? 0) as num), style: HF.num(22, color: HF.goldDeep))])),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _round('✖  मना करें', HF.bad, () => Navigator.pop(context, 'reject'))),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _round('✔  स्वीकार करें', HF.ok, () => Navigator.pop(context, 'accept'))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _round(String t, Color c, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(height: 62, alignment: Alignment.center, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(31), boxShadow: [BoxShadow(color: c.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 8))]), child: Text(t, style: HF.hi(17, color: Colors.white, w: FontWeight.w800))),
      );
}

/// Camera QR scanner for the shop's pickup slip.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
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
        ]),
      );
}
