import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pos.dart';
import 'inventory.dart';

/// Shop home: today's money, open/closed, orders & bills (cards open like the prototype), centre ➕ for a new bill.
class ShopHome extends StatefulWidget {
  const ShopHome({super.key});
  @override
  State<ShopHome> createState() => _ShopHomeState();
}

class _ShopHomeState extends State<ShopHome> {
  Map<String, dynamic> me = {};
  List<Map<String, dynamic>> orders = [];
  final open = <String>{};
  int tab = 0; // 0 orders, 1 shop
  String filter = 'all';
  bool loading = true;
  String err = '';
  Timer? poll;

  @override
  void initState() {
    super.initState();
    load();
    poll = Timer.periodic(const Duration(seconds: 25), (_) => load(quiet: true));
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!quiet) setState(() => loading = true);
    try {
      final m = await Api.me();
      final o = await Api.orders();
      if (!mounted) return;
      setState(() { me = m; orders = o; err = ''; });
    } catch (e) {
      if (mounted) setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> toggleOpen() async {
    try {
      final r = await Api.rpc('vendor_set_open', {'p_open': !(me['open'] == true)});
      if (r is Map && r['ok'] == false) {
        if (mounted) hfToast(context, 'एडमिन की मंज़ूरी बाकी है — मंज़ूरी के बाद दुकान खोल सकेंगे');
        return;
      }
      await load(quiet: true);
      if (mounted) hfToast(context, me['open'] == true ? 'दुकान खुल गई 🟢' : 'दुकान बंद की');
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  Future<void> newBill() async {
    final done = await showPos(context);
    if (done == true) load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final today = (me['today'] as Map?) ?? {};
    return Scaffold(
      backgroundColor: HF.bg,
      body: RefreshIndicator(
        color: HF.goldDeep,
        onRefresh: load,
        child: ListView(padding: EdgeInsets.zero, children: [
          _header(today),
          if (me['approved'] == false)
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: HFCard(color: const Color(0xFFFFF7E6), border: const Color(0xFFFDBA74), child: Text('⏳ आपकी दुकान एडमिन की मंज़ूरी का इंतज़ार कर रही है। तब तक आप इन्वेंट्री भर सकते हैं और बिल बना सकते हैं।', style: HF.hi(13.5, w: FontWeight.w700)))),
          if (err.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('⚠️ $err', style: HF.hi(13, color: HF.bad))),
          if (tab == 0) ..._ordersTab() else ..._shopTab(),
          const SizedBox(height: 110),
        ]),
      ),
      bottomNavigationBar: _nav(),
    );
  }

  Widget _header(Map today) {
    final name = (me['shop_name'] ?? 'मेरी दुकान').toString();
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 18),
      decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)), boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 48, height: 48, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)])), child: Text(name.isEmpty ? 'HF' : name.characters.first.toUpperCase(), style: HF.num(20, color: HF.ink))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(18)),
            Text('दुकान पार्टनर • ${_storeName(me['store'])}', style: HF.hi(12, color: HF.mut)),
          ])),
          GestureDetector(
            onTap: toggleOpen,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(99)),
              child: Row(children: [Toggle(me['open'] == true, (_) => toggleOpen()), const SizedBox(width: 6), Text(me['open'] == true ? 'खुली' : 'बंद', style: HF.hi(13.5, w: FontWeight.w800))]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [HF.heroTop, HF.heroBottom])),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('💰 आज की बिक्री', style: HF.hi(12.5, color: Colors.white70)),
              Text(rupee((today['total'] ?? 0) as num), style: HF.num(32, color: HF.gold)),
              Text('${today['count'] ?? 0} बिल / ऑर्डर', style: HF.hi(12, color: Colors.white60)),
            ])),
            GestureDetector(onTap: newBill, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(16)), child: Text('🧾 नया बिल', style: HF.hi(14, color: HF.ink, w: FontWeight.w800)))),
          ]),
        ),
      ]),
    );
  }

  String _storeName(dynamic id) {
    for (final s in stores) { if (s[0] == id) return '${s[1]} ${s[2]}'; }
    return '🍛 फ़ूड';
  }

  List<Widget> _ordersTab() {
    final list = orders.where((o) => filter == 'all' || (filter == 'live' ? !['done', 'cancelled'].contains(o['status']) : ['done', 'cancelled'].contains(o['status']))).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(children: [
          for (final f in [['all', 'सब'], ['live', 'चालू'], ['done', 'पूरे']])
            Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(onTap: () => setState(() => filter = f[0]), child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9), decoration: BoxDecoration(color: filter == f[0] ? HF.tx : Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: HF.line)), child: Text(f[1], style: HF.hi(14, color: filter == f[0] ? Colors.white : HF.tx, w: FontWeight.w800))))),
          const Spacer(),
          Text('${list.length}/${orders.length}', style: HF.hi(13, color: HF.mut)),
        ]),
      ),
      if (loading && orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
      if (!loading && list.isEmpty)
        Padding(padding: const EdgeInsets.all(30), child: Column(children: [const Text('🧾', style: TextStyle(fontSize: 44)), Text('अभी कोई बिल / ऑर्डर नहीं', style: HF.hi(15, w: FontWeight.w800)), Text('नीचे ➕ से पहला बिल बनाएँ', style: HF.hi(13, color: HF.mut))])),
      for (final o in list) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: _orderCard(o)),
    ];
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final id = o['id'].toString(), isOpen = open.contains(id);
    final items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final first = items.isNotEmpty ? items.first : {};
    final cx = o['status'] == 'cancelled';
    final src = {'pos': '🧾 POS बिल', 'qr': '📱 QR दुकान', 'app': '🛵 ऐप ऑर्डर', 'wholesale': '📦 थोक'}[o['source']] ?? '🧾 बिल';
    DateTime? t(String k) => o[k] == null ? null : DateTime.tryParse(o[k].toString())?.toLocal();
    final steps = <(String, String, bool, bool)>[
      ('स्वीकार', '🔔', t('accepted_at') != null, false),
      ('पैकिंग', '📦', t('packed_at') != null, false),
      (o['source'] == 'pos' ? 'बिल' : 'पिकअप', '🧾', t('done_at') != null, false),
      ('पैसा', '₹', o['status'] == 'done', false),
    ];
    return HFCard(
      onTap: () => setState(() => isOpen ? open.remove(id) : open.add(id)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _img(first['image_url'], 58),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('बिल #${o['bill_no'] ?? ''}', style: HF.num(17)),
            const SizedBox(height: 4),
            Pill(cx ? '✕ रद्द' : (o['status'] == 'done' ? '✅ पूरा' : '⏳ चालू'), bg: cx ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7), fg: cx ? HF.bad : HF.ok),
            const SizedBox(height: 4),
            Text('${items.map((i) => '${i['qty']}× ${i['name_hi'] ?? i['name']}').join(', ')} • ${t('created_at') != null ? hm(t('created_at')!) : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: HF.mut)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rupee((o['total'] ?? 0) as num), style: HF.num(20, color: cx ? HF.mut : HF.goldDeep)),
            Text((o['pay_mode'] ?? '').toString().toUpperCase(), style: HF.hi(10.5, color: HF.mut, w: FontWeight.w800)),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: StepLine(steps)), const SizedBox(width: 6), AnimatedRotation(turns: isOpen ? .5 : 0, duration: const Duration(milliseconds: 220), child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.keyboard_arrow_down, size: 18, color: HF.mut)))]),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child: !isOpen
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Divider(height: 26),
                  Text(src, style: HF.hi(13, color: HF.goldDeep, w: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final i in items)
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                      _img(i['image_url'], 42),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${i['name_hi'] ?? i['name']}', style: HF.hi(14, w: FontWeight.w700))),
                      Text('${i['qty']} × ${rupee((i['price'] ?? 0) as num)}', style: HF.hi(13, w: FontWeight.w800)),
                    ])),
                  if ((o['customer_phone'] ?? '').toString().isNotEmpty) Text('📞 ${o['customer_phone']}', style: HF.hi(13, color: HF.mut)),
                  const SizedBox(height: 6),
                  for (final r in [['🔔', 'स्वीकार', 'accepted_at'], ['📦', 'पैकिंग', 'packed_at'], ['✅', 'पूरा', 'done_at']])
                    if (t(r[2]) != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Text(r[0]), const SizedBox(width: 8), Expanded(child: Text(r[1], style: HF.hi(13.5, w: FontWeight.w700))), Text(hm(t(r[2])!), style: HF.hi(12.5, color: HF.goldDeep, w: FontWeight.w800))])),
                  if (!cx && o['source'] == 'pos')
                    Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _cancelBill(id), icon: const Icon(Icons.undo, size: 16, color: HF.bad), label: Text('बिल रद्द करें (स्टॉक वापस)', style: HF.hi(13, color: HF.bad)))),
                ]),
        ),
      ]),
    );
  }

  Future<void> _cancelBill(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text('बिल रद्द करें?', style: HF.hi(18, w: FontWeight.w800)), content: Text('सामान वापस स्टॉक में जुड़ जाएगा।', style: HF.hi(14)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('रहने दें')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('रद्द करें'))]));
    if (ok != true) return;
    try { await Api.rpc('vendor_cancel_sale', {'p_id': id}); await load(quiet: true); if (mounted) hfToast(context, 'बिल रद्द — स्टॉक वापस'); } catch (e) { if (mounted) hfToast(context, errText(e)); }
  }

  Widget _img(dynamic url, double s) {
    final u = (url ?? '').toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(s * .3),
      child: u.startsWith('http') ? Image.network(u, width: s, height: s, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph(s)) : _ph(s),
    );
  }

  Widget _ph(double s) => Container(width: s, height: s, color: const Color(0xFFFFF3D6), alignment: Alignment.center, child: Text('🍛', style: TextStyle(fontSize: s * .45)));

  List<Widget> _shopTab() => [
        Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: HFCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(me['shop_name']?.toString() ?? '', style: HF.num(20)),
          const SizedBox(height: 4),
          Text('📍 ${me['address'] ?? ''}', style: HF.hi(13.5, color: HF.mut)),
          Text('👤 ${me['owner'] ?? ''} • ${me['phone'] ?? ''}', style: HF.hi(13.5, color: HF.mut)),
          const SizedBox(height: 10),
          Pill(me['approved'] == true ? '✅ मंज़ूर' : '⏳ मंज़ूरी बाकी', bg: me['approved'] == true ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7E6), fg: me['approved'] == true ? HF.ok : const Color(0xFFC2410C)),
        ]))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _row('📦', 'इन्वेंट्री व अपना दाम', 'कितना माल है, POS का दाम', () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryPage())); load(quiet: true); })),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _row('🧾', 'नया बिल (POS)', 'काउंटर पर बिक्री', newBill)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _row('🚪', 'लॉग-आउट', 'इस फ़ोन से बाहर निकलें', () async { await Api.signOut(); if (mounted) goNext(context); })),
        const SizedBox(height: 24),
        Center(child: Text('नियम व शर्तें  ·  प्राइवेसी पॉलिसी  ·  रिफ़ंड पॉलिसी', style: HF.hi(13, color: HF.mut, w: FontWeight.w700))),
        const SizedBox(height: 12),
        Center(child: Text('P O W E R E D   B Y', style: HF.hi(11, color: HF.goldDeep, w: FontWeight.w800))),
        Center(child: Text('Filipra Private Limited', style: const TextStyle(fontFamily: 'serif', fontSize: 22, fontWeight: FontWeight.w700, color: HF.tx))),
        Center(child: Text('© 2026 Happy Food · Made in India 🇮🇳', style: HF.hi(12, color: HF.mut))),
      ];

  Widget _row(String ic, String t, String s, VoidCallback onTap) => HFCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(14)), child: Text(ic, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HF.hi(15, w: FontWeight.w800)), Text(s, style: HF.hi(12, color: HF.mut))])),
          const Icon(Icons.chevron_right, color: HF.mut),
        ]),
      );

  Widget _nav() => Container(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 8),
        decoration: const BoxDecoration(color: HF.card, boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, -4))]),
        child: Row(children: [
          Expanded(child: _navBtn(0, Icons.receipt_long, 'ऑर्डर')),
          GestureDetector(
            onTap: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InventoryPage())); load(quiet: true); },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 58, height: 58, decoration: BoxDecoration(gradient: HF.goldGrad, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x59E2A92C), blurRadius: 16, offset: Offset(0, 6))]), child: const Icon(Icons.add, size: 30, color: HF.ink)),
              Text('इन्वेंट्री', style: HF.hi(12, color: HF.mut, w: FontWeight.w800)),
            ]),
          ),
          Expanded(child: _navBtn(1, Icons.storefront, 'दुकान')),
        ]),
      );

  Widget _navBtn(int i, IconData ic, String l) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => tab = i),
        child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic, color: tab == i ? HF.goldDeep : HF.mut, size: 26), Text(l, style: HF.hi(12.5, color: tab == i ? HF.goldDeep : HF.mut, w: FontWeight.w800))]),
      );
}
