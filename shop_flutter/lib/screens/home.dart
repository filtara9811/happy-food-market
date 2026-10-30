import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../printer.dart';
import '../push.dart';
import '../widgets/shop_ui.dart';
import 'inventory.dart';
import 'shop_page.dart';
import 'pos_quick.dart';

/// Shop home — a copy of the prototype's shop panel: dark gold hero, earnings card, days row,
/// order / POS tabs, filters, order cards with step dots that open in place, bottom bar with ➕.
class ShopHome extends StatefulWidget {
  const ShopHome({super.key});
  @override
  State<ShopHome> createState() => _ShopHomeState();
}

class _ShopHomeState extends State<ShopHome> {
  Map<String, dynamic> me = {};
  List<Map<String, dynamic>> orders = [];
  final open = <String>{};
  int nav = 0; // 0 orders, 2 shop
  int seg = 0; // 0 orders, 1 POS & inventory
  String filter = 'all';
  int dayIdx = 0; // 0 = today, 1..6 = days back, 7 = month
  bool loading = true, mini = false;
  String err = '';
  Timer? poll;
  final sc = ScrollController();
  final seen = <String>{};
  StreamSubscription? actSub;

  Future<void> _pushAct(String act, String saleId) async {
    if (orders.every((o) => o['id'].toString() != saleId)) await load(quiet: true);
    if (!mounted) return;
    final o = orders.where((o) => o['id'].toString() == saleId).toList();
    setState(() { nav = 0; seg = 0; filter = 'live'; dayIdx = 0; open.add(saleId); });
    if (o.isEmpty) return;
    if (act == 'accept') await _act(o.first, 'accept');
    if (act == 'reject') await _act(o.first, 'reject');
  }
  final player = AudioPlayer();

  Future<void> _ring(List<Map<String, dynamic>> fresh) async {
    final n = fresh.length;
    try { await player.play(AssetSource('sounds/ring3.wav')); } catch (_) {}
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() { nav = 0; seg = 0; filter = 'live'; dayIdx = 0; });
    for (final x in fresh) { open.add(x['id'].toString()); }
    hfToast(context, '🔔 $n नया ऑर्डर आया!');
  }

  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 12), (_) => load(quiet: true));
    Push.register();
    actSub = Push.actions.stream.listen((a) => _pushAct(a.$1, a.$2));
    if (Push.launch != null) { final l = Push.launch!; Push.launch = null; Future.delayed(const Duration(milliseconds: 1500), () => _pushAct(l.$1, l.$2)); }
    sc.addListener(() { final m = sc.offset > 250; if (m != mini) setState(() => mini = m); });
  }

  @override
  void dispose() {
    poll?.cancel();
    actSub?.cancel();
    sc.dispose();
    player.dispose();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final m = await Api.me();
      final o = await Api.orders();
      if (!mounted) return;
      final fresh = o.where((x) => x['source'] != 'pos' && !['done', 'cancelled'].contains(x['status']) && !seen.contains(x['id'].toString())).toList();
      if (seen.isNotEmpty && fresh.isNotEmpty) _ring(fresh);
      for (final x in o) { seen.add(x['id'].toString()); }
      if (seen.isEmpty) seen.add('-');
      setState(() { me = m; orders = o; err = ''; });
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------- data helpers ----------
  DateTime? _t(Map o, String k) => o[k] == null ? null : DateTime.tryParse(o[k].toString())?.toLocal();
  DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _paid(Map o) => o['status'] != 'cancelled';
  num _amt(Map o) => (o['total'] ?? 0) as num;

  List<Map<String, dynamic>> get _period {
    final now = DateTime.now();
    if (dayIdx == 7) return orders.where((o) { final t = _t(o, 'created_at'); return t != null && t.year == now.year && t.month == now.month; }).toList();
    final d0 = _day0(now).subtract(Duration(days: dayIdx));
    return orders.where((o) { final t = _t(o, 'created_at'); return t != null && _day0(t) == d0; }).toList();
  }

  Future<void> toggleOpen() async {
    if (me['suspended'] == true) { hfToast(context, '🚫 दुकान सस्पेंड है — एडमिन से बात करें'); return; }
    try {
      final r = await Api.rpc('vendor_set_open', {'p_open': !(me['open'] == true)});
      if (r is Map && r['ok'] == false) { if (mounted) hfToast(context, 'एडमिन की मंज़ूरी बाकी है'); return; }
      await load(quiet: true);
      if (mounted) hfToast(context, me['open'] == true ? 'दुकान खुल गई 🟢' : 'दुकान बंद की');
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  Future<void> openInventory() async { await showInventory(context, me, orders); load(quiet: true); }
  Future<void> newBill() => openInventory();

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: HF.bg,
      body: Stack(children: [
        RefreshIndicator(
          color: HF.goldDeep,
          onRefresh: load,
          child: ListView(controller: sc, padding: EdgeInsets.only(bottom: 100 + pad.bottom), children: nav == 0 ? _ordersPage() : _shopPage()),
        ),
        // sticky mini header (shows after scrolling past the hero)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          left: 0, right: 0, top: mini ? 0 : -140,
          child: _miniHeader(pad.top),
        ),
        if (nav == 0 && seg == 1 && posCount > 0) Positioned(left: 0, right: 0, bottom: 0, child: _posBar(pad.bottom)),
        Positioned(left: 0, right: 0, bottom: 0, child: _nav(pad.bottom)),
      ]),
    );
  }

  // ---------- hero ----------
  String get _name => (me['shop_name'] ?? 'मेरी दुकान').toString();
  String get _initials { final p = _name.trim().split(RegExp(r'\s+')); return p.isEmpty || p.first.isEmpty ? 'HF' : (p.length > 1 ? p[0].characters.first + p[1].characters.first : p[0].characters.take(2).toString()).toUpperCase(); }

  Widget _av(double s, {double border = 3, double font = 20}) => withFlutterBadge(_avCore(s, border: border, font: font), s);

  Widget _avCore(double s, {double border = 3, double font = 20}) => Container(
        width: s, height: s, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: HF.avGrad, border: Border.all(color: Colors.white.withValues(alpha: .85), width: border)),
        child: Text(_initials, style: HF.num(font, color: HF.ink)),
      );

  Widget _duty({bool compact = false}) {
    final on = me['open'] == true;
    return GestureDetector(
      onTap: toggleOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: .18))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 42, height: 24, padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(color: on ? HF.okBright : Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(999)),
            child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 8),
          if (compact)
            Text(on ? 'खुली' : 'बंद', style: HF.hi(13, color: Colors.white, w: FontWeight.w800))
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(on ? 'दुकान खुली' : 'दुकान बंद', style: HF.hi(13, color: Colors.white, w: FontWeight.w800)),
              Text(on ? 'ऑर्डर आ रहे हैं' : 'खोलने के लिए दबाएँ', style: HF.hi(10.5, color: Colors.white70, w: FontWeight.w600)),
            ]),
        ]),
      ),
    );
  }

  Widget _hero(double top) {
    final p = _period, paid = p.where(_paid).toList();
    final sale = paid.fold<num>(0, (s, o) => s + _amt(o));
    const commission = 0; // POS / own bills: no Happy Food commission
    final label = dayIdx == 0 ? 'आज' : (dayIdx == 7 ? 'इस महीने' : '${_dayLabel(dayIdx)}');
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        gradient: HF.heroGrad,
        boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, 14))],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        gradient: RadialGradient(center: const Alignment(.6, -1), radius: 1.2, colors: [HF.gold.withValues(alpha: .16), Colors.transparent], stops: const [0, .6]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _av(56),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(18, color: Colors.white, w: FontWeight.w800)),
            Text('दुकान पार्टनर · ${me['owner'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: Colors.white60, w: FontWeight.w600)),
          ])),
          const SizedBox(width: 8),
          _duty(),
        ]),
        // earnings card (.ph-cc)
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withValues(alpha: .07), border: Border.all(color: Colors.white.withValues(alpha: .14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('💰 मेरी कमाई · $label', style: HF.hi(12.5, color: Colors.white.withValues(alpha: .85), w: FontWeight.w600))),
              GestureDetector(onTap: _earnSheet, child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(999)), child: Text('हिसाब ›', style: HF.hi(12, color: const Color(0xFF86EFAC), w: FontWeight.w600)))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: GestureDetector(onTap: _earnSheet, child: Row(children: [
                Flexible(child: Text(rupee(sale - commission), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(32, color: Colors.white, w: FontWeight.w700))),
                const SizedBox(width: 8),
                Container(width: 22, height: 22, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), shape: BoxShape.circle), child: const Icon(Icons.chevron_right, size: 14, color: Colors.white70)),
              ]))),
              GestureDetector(
                onTap: () => hfToast(context, 'पैसे निकालना जल्द आएगा — अभी POS का पैसा सीधे आपके पास है'),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x4DF2B632), blurRadius: 14, offset: Offset(0, 6))]),
                    child: Row(children: [const Icon(Icons.arrow_downward, size: 14, color: HF.ink), const SizedBox(width: 6), Text('निकालें', style: HF.hi(12.5, color: HF.ink, w: FontWeight.w800))])),
              ),
            ]),
            Text('${paid.length} ऑर्डर पूरे · कमीशन कटकर', style: HF.hi(11.5, color: Colors.white.withValues(alpha: .62), w: FontWeight.w500)),
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .12)))),
              child: Row(children: [
                _stat('ऑर्डर', '${paid.length}', first: true),
                _stat('बिक्री', rupee(sale)),
                _stat('कमीशन', commission == 0 ? '₹0' : rupee(-commission)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String l, String v, {bool first = false}) => Expanded(
        child: Container(
          padding: EdgeInsets.only(left: first ? 0 : 6, right: 6),
          decoration: BoxDecoration(border: first ? null : Border(left: BorderSide(color: Colors.white.withValues(alpha: .12)))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: HF.hi(10.5, color: Colors.white.withValues(alpha: .6), w: FontWeight.w500)),
            Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(14.5, color: Colors.white, w: FontWeight.w600)),
          ]),
        ),
      );

  Widget _miniHeader(double top) => Container(
        padding: EdgeInsets.fromLTRB(14, top + 10, 14, 12),
        decoration: const BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)), boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))]),
        child: Row(children: [
          _av(40, border: 2, font: 14),
          const SizedBox(width: 12),
          const Text('💰', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(rupee(_period.where(_paid).fold<num>(0, (s, o) => s + _amt(o))), style: HF.num(19, color: Colors.white, w: FontWeight.w800)),
          const SizedBox(width: 6),
          Text(dayIdx == 0 ? 'आज की कमाई' : 'कमाई', style: HF.hi(11.5, color: Colors.white70, w: FontWeight.w600)),
          const Spacer(),
          _duty(compact: true),
        ]),
      );

  String _dayLabel(int i) {
    final d = DateTime.now().subtract(Duration(days: i));
    return i == 0 ? 'आज ${d.day}' : '${hiDays[d.weekday - 1]} ${d.day}';
  }

  Widget _days() {
    final now = DateTime.now();
    final maxv = List.generate(7, (i) {
      final d0 = _day0(now).subtract(Duration(days: i));
      return orders.where((o) { final t = _t(o, 'created_at'); return t != null && _day0(t) == d0 && _paid(o); }).fold<num>(0, (s, o) => s + _amt(o));
    });
    final top = maxv.fold<num>(1, (a, b) => b > a ? b : a);
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
            Text(shortRupee(maxv[i]), style: HF.num(11, color: dayIdx == i ? const Color(0xFF86EFAC) : HF.ok, w: FontWeight.w900)),
            Text('${orders.where((o) { final t = _t(o, 'created_at'); return t != null && _day0(t) == _day0(now).subtract(Duration(days: i)); }).length} ऑर्डर', style: HF.hi(10.5, color: dayIdx == i ? Colors.white70 : HF.mut, w: FontWeight.w700)),
          ]), pct: maxv[i] / top),
        chip(7, Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🗓️', style: TextStyle(fontSize: 18)),
          Text('महीना', style: HF.hi(11, color: dayIdx == 7 ? Colors.white : HF.tx, w: FontWeight.w800)),
        ])),
      ]),
    );
  }

  Widget _tabs() {
    Widget b(int i, String t, int n, {bool hot = false}) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => seg = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              decoration: BoxDecoration(color: seg == i ? HF.card : Colors.transparent, borderRadius: BorderRadius.circular(16), boxShadow: seg == i ? const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))] : null),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(13, color: seg == i ? HF.tx : HF.mut, w: FontWeight.w800))),
                const SizedBox(width: 6),
                Container(constraints: const BoxConstraints(minWidth: 22), height: 22, padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center, decoration: BoxDecoration(color: hot && n > 0 ? const Color(0xFFEF4444) : const Color(0xFF16A34A), borderRadius: BorderRadius.circular(999)), child: Text('$n', style: HF.num(11.5, color: Colors.white, w: FontWeight.w800))),
              ]),
            ),
          ),
        );
    final live = orders.where((o) => !['done', 'cancelled'].contains(o['status'])).length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Color.alphaBlend(HF.goldDeep.withValues(alpha: .12), HF.card2), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [b(0, '🧾 ऑर्डर', orders.length), b(1, '🏪 POS • इन्वेंट्री', live, hot: true)]),
    );
  }

  List<Widget> _ordersPage() {
    final top = MediaQuery.of(context).padding.top;
    final list = _period.where((o) => filter == 'all' || (filter == 'live' ? !['done', 'cancelled'].contains(o['status']) : ['done', 'cancelled'].contains(o['status']))).toList();
    return [
      _hero(top),
      if (me['suspended'] == true) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: HFCard(color: const Color(0xFFFEE2E2), border: const Color(0xFFFCA5A5), child: Text('🚫 आपकी दुकान एडमिन ने सस्पेंड की है। ग्राहक आपकी दुकान नहीं देख पाएँगे — सपोर्ट से बात करें।', style: HF.hi(13.5, color: HF.bad, w: FontWeight.w700)))),
      if (me['approved'] == false && me['suspended'] != true) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: HFCard(color: const Color(0xFFFFF7E6), border: const Color(0xFFFDBA74), child: Text('⏳ आपकी दुकान एडमिन की मंज़ूरी का इंतज़ार कर रही है। तब तक आप इन्वेंट्री भर सकते हैं और बिल बना सकते हैं।', style: HF.hi(13.5, w: FontWeight.w700)))),
      if (err.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Text('⚠️ $err', style: HF.hi(13, color: HF.bad))),
      const SizedBox(height: 16),
      _days(),
      const SizedBox(height: 12),
      _tabs(),
      if (seg == 1) ..._posTab() else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            for (final f in [['all', 'सब'], ['live', 'चालू'], ['done', 'पूरे']])
              Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setState(() => filter = f[0]), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: filter == f[0] ? const Color(0xFF111111) : HF.card, borderRadius: BorderRadius.circular(999), border: Border.all(color: filter == f[0] ? const Color(0xFF111111) : HF.line, width: 1.5)), child: Text(f[1], style: HF.hi(13, color: filter == f[0] ? Colors.white : HF.mut, w: FontWeight.w800))))),
            const Spacer(),
            Text('${list.length} / ${_period.length}', style: HF.num(13, color: HF.mut, w: FontWeight.w700)),
          ]),
        ),
        if (loading && orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
        if (!loading && list.isEmpty)
          Padding(padding: const EdgeInsets.all(30), child: Column(children: [const Text('🧾', style: TextStyle(fontSize: 44)), Text(orders.isEmpty ? 'अभी कोई बिल / ऑर्डर नहीं' : 'इस दिन कोई ऑर्डर नहीं', style: HF.hi(15, w: FontWeight.w800)), Text('नीचे ➕ से इन्वेंट्री भरें, ऊपर "निकालें" के पास से बिल बनाएँ', textAlign: TextAlign.center, style: HF.hi(13, color: HF.mut))])),
        for (final o in list) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: _card(o)),
      ],
    ];
  }

  // ---------- order card (.ph-card + .ph-st) ----------
  Widget _card(Map<String, dynamic> o) {
    final id = o['id'].toString(), isOpen = open.contains(id);
    final items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final first = items.isNotEmpty ? items.first : {};
    final cx = o['status'] == 'cancelled', done = o['status'] == 'done';
    final pos = o['source'] == 'pos';
    final cname = (o['customer_name'] ?? '').toString();
    final title = cname.isNotEmpty ? cname : ((o['customer_phone'] ?? '').toString().isNotEmpty ? '+91 ${o['customer_phone']}' : (pos ? 'काउंटर ग्राहक' : 'ग्राहक'));
    final st = o['status'];
    final chip = cx ? ['रद्द', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)] : (done ? [pos ? '✅ बिल' : '✅ डिलीवर', const Color(0xFFDCFCE7), const Color(0xFF166534)]
        : (st == 'new' ? ['🔔 नया ऑर्डर', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)] : (st == 'packing' ? ['📦 पैक हो रहा', const Color(0xFFFEF3C7), const Color(0xFF92400E)]
        : (o['picked_at'] != null ? ['🛵 राइडर ले गया', const Color(0xFFDBEAFE), const Color(0xFF1E40AF)] : ['🛵 राइडर का इंतज़ार', const Color(0xFFFEF3C7), const Color(0xFF92400E)]))));
    final steps = pos
        ? [('स्वीकार', '', true, false), ('पैकिंग', '📦', _t(o, 'packed_at') != null || done, false), ('बिल', '🧾', done, false), ('पैसा', '₹', done, false), ('रेटिंग', '⭐', false, false)]
        : [('स्वीकार', '', _t(o, 'accepted_at') != null, false), ('पैकिंग', '📦', _t(o, 'packed_at') != null, false), ('पिकअप', '🛵', _t(o, 'picked_at') != null || done, false), ('डिलीवर', '🏠', done, false), ('रेटिंग', '⭐', false, false)];
    // the first step that is not done is "current" (unless cancelled)
    final cur = cx ? -1 : steps.indexWhere((s) => !s.$3);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 62, height: 60, child: Stack(clipBehavior: Clip.none, children: [
            Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Color.alphaBlend(HF.goldDeep.withValues(alpha: .35), Colors.white), width: 3)), child: ClipOval(child: _img(first['image_url'], 50))),
            Positioned(right: 2, bottom: 0, child: Container(width: 22, height: 22, alignment: Alignment.center, decoration: const BoxDecoration(color: HF.gold, shape: BoxShape.circle), child: Text(cx ? '✕' : (done ? '✓' : '⏳'), style: const TextStyle(fontSize: 11)))),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(17, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), decoration: BoxDecoration(color: chip[1] as Color, borderRadius: BorderRadius.circular(999)), child: Text(chip[0] as String, style: HF.hi(11.5, color: chip[2] as Color, w: FontWeight.w800))),
            const SizedBox(height: 4),
            Text('${items.map((i) => '${i['qty']}× ${i['name']}').join(', ')} • ${_t(o, 'created_at') != null ? hm(_t(o, 'created_at')!).toUpperCase() : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(11, color: HF.mut, w: FontWeight.w600)),
          ])),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(cx ? '' : rupee(_amt(o)), style: HF.num(20, color: HF.goldDeep, w: FontWeight.w800)),
            Text(cx ? '—' : 'बिक्री', style: HF.hi(10, color: HF.mut, w: FontWeight.w900)),
          ]),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => isOpen ? open.remove(id) : open.add(id)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _steps(steps, cur)),
            const SizedBox(width: 4),
            Padding(padding: const EdgeInsets.only(top: 2), child: AnimatedRotation(turns: isOpen ? .5 : 0, duration: const Duration(milliseconds: 220), child: Container(width: 26, height: 26, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.keyboard_arrow_down, size: 16, color: HF.mut)))),
          ]),
        ),
        if (!pos && !cx && !done) _appActions(o),
        AnimatedSize(duration: const Duration(milliseconds: 260), curve: Curves.easeOut, child: isOpen ? _expanded(o, items, cx) : const SizedBox(width: double.infinity)),
      ]),
    );
  }

  Widget _steps(List<(String, String, bool, bool)> s, int cur) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < s.length; i++)
          Expanded(child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            if (i > 0)
              Positioned(top: 12.5, left: 0, right: 0, child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .5, child: Container(height: 3, decoration: BoxDecoration(gradient: s[i].$3 || i == cur ? const LinearGradient(colors: [HF.okBright, HF.gold]) : null, color: s[i].$3 || i == cur ? null : HF.line)))),
            if (i < s.length - 1)
              Positioned(top: 12.5, left: 0, right: 0, child: FractionallySizedBox(alignment: Alignment.centerRight, widthFactor: .5, child: Container(height: 3, decoration: BoxDecoration(gradient: s[i + 1].$3 || i + 1 == cur ? const LinearGradient(colors: [HF.okBright, HF.gold]) : null, color: s[i + 1].$3 || i + 1 == cur ? null : HF.line)))),
            Column(children: [
              Container(
                width: 28, height: 28, alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s[i].$3 ? Color.alphaBlend(HF.okBright.withValues(alpha: .15), HF.card) : (i == cur ? const Color(0xFFFDE68A) : HF.card2),
                  border: Border.all(color: s[i].$3 ? HF.okBright : (i == cur ? HF.gold : HF.line), width: 2),
                  boxShadow: i == cur ? [BoxShadow(color: HF.gold.withValues(alpha: .25), spreadRadius: 5)] : null,
                ),
                child: s[i].$3 ? const Icon(Icons.check, size: 14, color: Color(0xFF16A34A)) : Text(s[i].$2, style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 4),
              Text(s[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(10.5, color: s[i].$3 ? HF.ok : (i == cur ? HF.goldDeep : HF.mut), w: FontWeight.w800)),
            ]),
          ])),
      ]);

  Widget _expanded(Map<String, dynamic> o, List<Map> items, bool cx) {
    final rows = <(String, String, String, DateTime?, Widget?)>[
      ('✓', 'स्वीकार', o['source'] == 'pos' ? 'काउंटर पर बिल बना' : 'आपने ऑर्डर स्वीकार किया', _t(o, 'accepted_at') ?? _t(o, 'created_at'), null),
      ('📦', 'पैकिंग', '', _t(o, 'packed_at'), Row(children: [for (final i in items.take(4)) Padding(padding: const EdgeInsets.only(right: 8, top: 6), child: Stack(clipBehavior: Clip.none, children: [ClipOval(child: _img(i['image_url'], 44)), Positioned(right: -4, bottom: -2, child: Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: HF.tx, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('${i['qty']}', style: HF.num(10, color: Colors.white))))]))])),
      (cx ? '✕' : '₹', cx ? 'रद्द' : (o['source'] == 'pos' ? 'पैसा मिला' : 'डिलीवर'), cx ? 'बिल रद्द — स्टॉक वापस' : '${(o['pay_mode'] ?? 'cash').toString().toUpperCase()} • ${rupee(_amt(o))}', cx ? null : _t(o, 'done_at'), null),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      Container(height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), gradient: const LinearGradient(colors: [HF.okBright, HF.gold]))),
      const SizedBox(height: 14),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: r.$4 != null || r.$1 == '✕' ? Colors.white : HF.card2, border: Border.all(color: r.$1 == '✕' ? const Color(0xFFEF4444) : (r.$4 != null ? HF.okBright : HF.line), width: 2)),
                child: r.$4 != null && r.$1 != '✕' ? const Icon(Icons.check, size: 16, color: Color(0xFF16A34A)) : Text(r.$1, style: TextStyle(fontSize: 12, color: r.$1 == '✕' ? const Color(0xFFDC2626) : HF.mut))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.$2, style: HF.hi(14.5, w: FontWeight.w800)),
              if (r.$3.isNotEmpty) Text(r.$3, style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)),
              if (r.$5 != null) r.$5!,
            ])),
            Text(r.$4 != null ? hm(r.$4!) : '', style: HF.hi(12.5, color: HF.goldDeep, w: FontWeight.w800)),
          ]),
        ),
      if (!cx)
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _printOrder(o), icon: const Icon(Icons.print, size: 18, color: HF.goldDeep), label: Text(o['source'] == 'pos' ? 'बिल प्रिंट करें' : 'स्लिप प्रिंट करें', style: HF.hi(13, color: HF.goldDeep)))),
      if (!cx && o['source'] == 'pos')
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _cancelBill(o['id'].toString()), icon: const Icon(Icons.undo, size: 16, color: HF.bad), label: Text('बिल रद्द करें (स्टॉक वापस)', style: HF.hi(12.5, color: HF.bad)))),
    ]);
  }

  // ---------- app orders: accept → pack → ready (QR slip) → rider scans ----------
  final busyAct = <String>{};

  Future<void> _act(Map<String, dynamic> o, String act) async {
    final id = o['id'].toString();
    if (busyAct.contains(id)) return;
    setState(() => busyAct.add(id));
    try {
      final r = await Api.rpc('vendor_order_act', {'p_sale': id, 'p_act': act});
      final ok = r is Map && r['ok'] == true;
      if (!mounted) return;
      if (!ok) {
        final code = r is Map ? r['code'] : '';
        hfToast(context, code == 'gone' ? 'ग्राहक ने ऑर्डर रद्द कर दिया' : (code == 'too_late' ? 'अब मना नहीं कर सकते — राइडर आ रहा है' : 'नहीं हो पाया ($code)'));
      } else if (act == 'accept') {
        HapticFeedback.mediumImpact();
        hfToast(context, '✅ स्वीकार — पैक करके "पैक हो गया" दबाएँ');
      } else if (act == 'reject') {
        hfToast(context, 'मना किया — ऑर्डर दूसरी जगह चला गया');
      } else if (act == 'ready') {
        o['pickup_code'] = r['code']; o['status'] = 'ready'; o['packed_at'] = DateTime.now().toIso8601String();
        hfToast(context, '📦 पैक — राइडर बुला रहे हैं। स्लिप प्रिंट करके पैकेट पर लगाएँ');
        final e = await Printer.quickPrint(_receiptOf(o));
        if (e != null && mounted) showPrinter(context, _receiptOf(o));
      }
      await load(quiet: true);
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busyAct.remove(id));
    }
  }

  String _qrOf(Map o) => 'HFPICK:${o['order_id']}:${o['pickup_code']}';

  Receipt _receiptOf(Map o) {
    final items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final pos = o['source'] == 'pos', code = o['pickup_code']?.toString();
    final sub = items.fold<num>(0, (s, i) => s + ((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num));
    return Receipt(
      heading: pos ? null : 'HAPPY FOOD — पिकअप स्लिप',
      shop: (me['shop_name'] ?? '').toString(), billNo: 'HFB-${o['bill_no'].toString().padLeft(4, '0')}', at: _t(o, 'created_at') ?? DateTime.now(),
      items: [for (final i in items) ('${i['name_hi'] ?? i['name']}', (i['price'] ?? 0) as num, (i['qty'] ?? 0) as num)],
      subtotal: sub, discount: ((o['discount'] ?? 0) as num), total: _amt(o),
      payLabel: pos ? ((o['pay_mode'] ?? 'cash') == 'cash' ? 'कैश' : (o['pay_mode'] == 'upi' ? 'UPI' : 'उधार')) : 'COD — राइडर लेगा',
      customer: (o['customer_name'] ?? '').toString(), phone: (o['customer_phone'] ?? '').toString(), address: pos ? null : (o['customer_address'] ?? '').toString(),
      qr: !pos && code != null ? _qrOf(o) : null, code: code,
      note: !pos && code != null ? 'राइडर यह QR स्कैन करेगा, तभी पिकअप होगा' : null,
    );
  }

  Future<void> _printOrder(Map<String, dynamic> o) async {
    final e = await Printer.quickPrint(_receiptOf(o));
    if (!mounted) return;
    if (e == null) { hfToast(context, 'प्रिंट हो गया 🖨️'); } else { showPrinter(context, _receiptOf(o)); }
  }

  Widget _actBtn(String t, Color bg, Color fg, VoidCallback? f, {bool outline = false}) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Opacity(opacity: f == null ? .5 : 1, child: Container(height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: outline ? Border.all(color: fg.withValues(alpha: .4), width: 1.5) : null), child: Text(t, style: HF.hi(14, color: fg, w: FontWeight.w800)))),
        ),
      );

  Widget _appActions(Map<String, dynamic> o) {
    final id = o['id'].toString(), b = busyAct.contains(id), st = o['status'];
    if (st == 'new') {
      return Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        _actBtn('मना करें', HF.card, HF.bad, b ? null : () => _act(o, 'reject'), outline: true),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: Row(children: [_actBtn(b ? '…' : '✅ स्वीकार करें', const Color(0xFF16A34A), Colors.white, b ? null : () => _act(o, 'accept'))])),
      ]));
    }
    if (st == 'packing') {
      return Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        _actBtn('मना करें', HF.card, HF.bad, b ? null : () => _act(o, 'reject'), outline: true),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: Row(children: [_actBtn(b ? '…' : '📦 पैक हो गया — राइडर बुलाएँ', const Color(0xFF16120B), HF.goldLight, b ? null : () => _act(o, 'ready'))])),
      ]));
    }
    if (st == 'ready') {
      final picked = o['picked_at'] != null, code = o['pickup_code']?.toString();
      return Container(
        margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: picked ? const Color(0xFFEFF6FF) : const Color(0xFFFDF8EC), borderRadius: BorderRadius.circular(18), border: Border.all(color: picked ? const Color(0xFF93C5FD) : HF.gold.withValues(alpha: .5))),
        child: Row(children: [
          if (!picked && code != null) Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: QrImageView(data: _qrOf(o), size: 84, padding: EdgeInsets.zero)),
          if (!picked && code != null) const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(picked ? '🛵 राइडर पैकेट ले गया' : '🛵 राइडर का इंतज़ार', style: HF.hi(14.5, w: FontWeight.w800)),
            if ((o['rider_name'] ?? '').toString().isNotEmpty) Text('राइडर: ${o['rider_name']}', style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)) else Text('राइडर ढूँढ रहे हैं…', style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)),
            if (!picked && code != null) Text('पिकअप कोड: $code', style: HF.num(15, color: HF.goldDeep, w: FontWeight.w800)),
            if (!picked) Text('राइडर यह QR (स्लिप या इस स्क्रीन से) स्कैन करेगा — तभी पिकअप होगा', style: HF.hi(11.5, color: HF.mut)),
            const SizedBox(height: 4),
            Row(children: [
              GestureDetector(onTap: () => _printOrder(o), child: Text('🖨️ स्लिप प्रिंट', style: HF.hi(13, color: HF.goldDeep, w: FontWeight.w800))),
              if ((o['rider_phone'] ?? '').toString().isNotEmpty) ...[const SizedBox(width: 14), GestureDetector(onTap: () => openUrl(context, 'tel:+${o['rider_phone']}'), child: Text('📞 राइडर को कॉल', style: HF.hi(13, color: const Color(0xFF16A34A), w: FontWeight.w800)))],
            ]),
          ])),
        ]),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _cancelBill(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('बिल रद्द करें?', style: HF.hi(18, w: FontWeight.w800)), content: Text('सामान वापस स्टॉक में जुड़ जाएगा।', style: HF.hi(14)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('रहने दें')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('रद्द करें'))]));
    if (ok != true) return;
    try { await Api.rpc('vendor_cancel_sale', {'p_id': id}); await load(quiet: true); if (mounted) hfToast(context, 'बिल रद्द — स्टॉक वापस'); } catch (e) { if (mounted) hfToast(context, errText(e)); }
  }

  Widget _img(dynamic url, double s) {
    final u = (url ?? '').toString();
    if (u.startsWith('asset:')) return Image.asset('assets/food/${u.substring(6)}.webp', width: s, height: s, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph(s));
    return u.startsWith('http') ? Image.network(u, width: s, height: s, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph(s)) : _ph(s);
  }

  Widget _ph(double s) => Container(width: s, height: s, color: const Color(0xFFFFF3D6), alignment: Alignment.center, child: Text('🍛', style: TextStyle(fontSize: s * .42)));

  // ---------- POS tab (part 2 will match the prototype's inventory screen exactly) ----------
  final posKey = GlobalKey<PosQuickState>();
  int posCount = 0;
  num posTotal = 0;

  List<Widget> _posTab() => [
        PosQuick(
          key: posKey, me: me, reload: () => load(quiet: true),
          openInventory: () async { await openInventory(); posKey.currentState?.load(); },
          onBill: (c, t) { if (c != posCount || t != posTotal) setState(() { posCount = c; posTotal = t; }); },
        ),
      ];

  Widget _posBar(double bottom) => GestureDetector(
        onTap: () => posKey.currentState?.openBill(),
        child: Container(
          margin: EdgeInsets.fromLTRB(16, 0, 16, 96 + bottom),
          height: 58, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x6616A34A), blurRadius: 20, offset: Offset(0, 8))]),
          child: Row(children: [
            const Text('🧺', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(child: Text('$posCount सामान • ${rupee(posTotal)}', style: HF.num(17, color: Colors.white, w: FontWeight.w800))),
            Text('बिल बनाएँ ›', style: HF.hi(15.5, color: Colors.white, w: FontWeight.w800)),
          ]),
        ),
      );

  Widget _bigBtn(String ic, String t, String s, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.line)),
          child: Row(children: [
            Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)), child: Text(ic, style: const TextStyle(fontSize: 24))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HF.num(16, w: FontWeight.w800)), Text(s, style: HF.hi(12, color: HF.mut, w: FontWeight.w600))])),
            const Icon(Icons.chevron_right, color: HF.mut),
          ]),
        ),
      );

  // ---------- earnings popup ----------
  void _earnSheet() {
    final now = DateTime.now();
    final week = List.generate(7, (k) {
      final i = 6 - k, d0 = _day0(now).subtract(Duration(days: i));
      final v = orders.where((o) { final t = _t(o, 'created_at'); return t != null && _day0(t) == d0 && _paid(o); }).fold<num>(0, (s, o) => s + _amt(o));
      return (i == 0 ? 'आज' : hiDays[d0.weekday - 1], v);
    });
    final top = week.fold<num>(1, (a, b) => b.$2 > a ? b.$2 : a);
    final todays = orders.where((o) { final t = _t(o, 'created_at'); return t != null && _day0(t) == _day0(now); }).toList();
    final paid = todays.where(_paid).toList(), sale = paid.fold<num>(0, (s, o) => s + _amt(o));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: .86, maxChildSize: .95, expand: false,
        builder: (_, ctl) => Container(
          decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
            Row(children: [Expanded(child: Text('आज की कमाई', style: HF.hi(19, w: FontWeight.w800))), GestureDetector(onTap: () => Navigator.pop(c), child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.close, size: 20)))]),
            const SizedBox(height: 14),
            Text('${paid.length} ऑर्डर पूरे · कमीशन कटकर', style: HF.hi(13, color: HF.mut, w: FontWeight.w600)),
            Text(rupee(sale), style: HF.num(34)),
            const SizedBox(height: 10),
            Row(children: [
              for (final t in [['ऑर्डर', '${paid.length}'], ['बिक्री', rupee(sale)], ['कमीशन', '₹0']])
                Expanded(child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t[0], style: HF.hi(11.5, color: HF.mut)), Text(t[1], style: HF.num(17, w: FontWeight.w700))]))),
            ]),
            const SizedBox(height: 20),
            Row(children: [Expanded(child: Text('पिछले 7 दिन', style: HF.hi(14.5, w: FontWeight.w800))), Text(rupee(week.fold<num>(0, (s, w) => s + w.$2)), style: HF.num(15, color: HF.goldDeep, w: FontWeight.w800))]),
            const SizedBox(height: 10),
            Container(
              height: 140, padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
              decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(week[i].$2 >= 1000 ? '${(week[i].$2 / 1000).toStringAsFixed(1)}k' : '${week[i].$2.round()}', style: HF.num(10.5, color: HF.mut, w: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Container(height: 4 + 70 * (week[i].$2 / top).toDouble(), margin: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: i == 6 ? const Color(0xFFB07A12) : const Color(0xFFE6D3A8), borderRadius: BorderRadius.circular(5))),
                    const SizedBox(height: 4),
                    Text(week[i].$1, style: HF.hi(10.5, color: i == 6 ? HF.tx : HF.mut, w: FontWeight.w800)),
                  ])),
              ]),
            ),
            const SizedBox(height: 20),
            Text('आज के ऑर्डर (${todays.length})', style: HF.hi(14.5, w: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final o in todays)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HF.line))),
                child: Row(children: [
                  ClipOval(child: _img(((o['items'] as List?)?.isNotEmpty == true ? (o['items'] as List).first['image_url'] : null), 44)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((o['customer_phone'] ?? '').toString().isNotEmpty ? '+91 ${o['customer_phone']}' : 'बिल #${o['bill_no']}', style: HF.hi(14.5, w: FontWeight.w800)),
                    Text('${((o['items'] as List?) ?? []).map((i) => '${i['qty']}× ${i['name']}').join(', ')} • ${_t(o, 'created_at') != null ? hm(_t(o, 'created_at')!).toUpperCase() : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: HF.mut, w: FontWeight.w600)),
                  ])),
                  Text(_paid(o) ? '+${rupee(_amt(o))}' : rupee(_amt(o)), style: HF.num(15, color: _paid(o) ? HF.ok : HF.mut, w: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  // ---------- shop page ----------
  List<Widget> _shopPage() => [
        ShopPage(
          key: ValueKey('shop-${me['id']}'),
          me: me, orders: orders, reload: () => load(quiet: true), toggleOpen: toggleOpen, openInventory: openInventory,
          openEarnings: _earnSheet,
          openBills: () { setState(() { nav = 0; seg = 0; filter = 'all'; dayIdx = 7; }); if (sc.hasClients) sc.jumpTo(0); },
        ),
      ];

  // ---------- bottom bar (#phNav) ----------
  Widget _nav(double bottom) => SizedBox(
        height: 72 + bottom + 24,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
          Container(
            height: 72 + bottom,
            padding: EdgeInsets.fromLTRB(22, 0, 22, 10 + bottom),
            decoration: const BoxDecoration(color: HF.card, border: Border(top: BorderSide(color: HF.line)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, -8))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_nb(0, Icons.receipt_long, 'ऑर्डर'), _nb(2, Icons.storefront, 'दुकान')]),
          ),
          Positioned(
            bottom: 12 + bottom,
            child: GestureDetector(
              onTap: openInventory,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 54, height: 54, decoration: BoxDecoration(shape: BoxShape.circle, gradient: HF.navGrad, border: Border.all(color: HF.card, width: 4), boxShadow: const [BoxShadow(color: Color(0x73E2A92C), blurRadius: 18, offset: Offset(0, 8))]), child: const Icon(Icons.add, size: 28, color: HF.ink)),
                const SizedBox(height: 4),
                Text('इन्वेंट्री', style: HF.hi(11, color: HF.goldDeep, w: FontWeight.w800)),
              ]),
            ),
          ),
        ]),
      );

  Widget _nb(int i, IconData ic, String l) {
    final on = nav == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { setState(() { nav = i; mini = false; }); if (sc.hasClients) sc.jumpTo(0); },
      child: SizedBox(
        width: 96,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          if (on) Positioned(top: -12, child: Container(width: 28, height: 3, decoration: BoxDecoration(color: HF.goldDeep, borderRadius: BorderRadius.circular(3)))),
          Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic, size: 22, color: on ? HF.goldDeep : HF.mut), const SizedBox(height: 4), Text(l, style: HF.hi(11.5, color: on ? HF.goldDeep : HF.mut, w: FontWeight.w700))]),
        ]),
      ),
    );
  }
}
