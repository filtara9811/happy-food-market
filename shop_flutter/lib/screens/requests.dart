import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/route_map.dart';
import '../widgets/shop_ui.dart';

/// Requests sheet: app orders (from Happy Food customers) and digital-shop orders, each card expands to a map + items.
/// Accept → card stays with "packed — send to riders"; riders accept → rider name + pickup code; picked → card leaves.
class RequestsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> Function() orders;
  final Future<void> Function(Map<String, dynamic> o, String act) act;
  final ScrollController sc;
  final String initialTab;
  const RequestsSheet({super.key, required this.orders, required this.act, required this.sc, this.initialTab = 'app'});
  @override
  State<RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends State<RequestsSheet> {
  late String tab = widget.initialTab;
  final open = <String>{};
  final busy = <String>{};
  bool auto = false;
  Timer? t;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) { if (mounted) setState(() => auto = p.getBool('rq_auto') ?? false); });
    t = Timer.periodic(const Duration(seconds: 2), (_) { if (mounted) setState(() {}); });
    final n = _app().where((o) => o['status'] == 'new');
    if (n.isNotEmpty) open.add(n.first['id'].toString());
  }

  @override
  void dispose() { t?.cancel(); super.dispose(); }

  bool _live(Map o) => !['done', 'cancelled'].contains(o['status']) && o['picked_at'] == null;
  List<Map<String, dynamic>> _app() => widget.orders().where((o) => o['source'] == 'app' && _live(o)).toList();
  List<Map<String, dynamic>> _ds() => widget.orders().where((o) => (o['source'] == 'qr' || o['source'] == 'whatsapp' || o['source'] == 'shop') && _live(o)).toList();

  Future<void> _do(Map<String, dynamic> o, String a) async {
    final id = o['id'].toString();
    setState(() => busy.add(id));
    HapticFeedback.mediumImpact();
    try {
      await widget.act(o, a);
      if (a == 'accept') open.add(id);
      if (a == 'accept' && auto) await widget.act(o, 'ready');
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  String _ago(Map o) {
    final c = DateTime.tryParse('${o['created_at']}')?.toLocal();
    if (c == null) return '';
    final m = DateTime.now().difference(c).inMinutes;
    return m < 1 ? 'अभी' : (m < 60 ? '$m min' : hm(c));
  }

  Widget _seg() {
    final a = _app(), d = _ds();
    final an = a.where((o) => o['status'] == 'new').length, dn = d.where((o) => o['status'] == 'new').length;
    Widget b(String k, String t, int n, int all, Color hot) => Expanded(
          child: GestureDetector(
            onTap: () => setState(() => tab = k),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(color: tab == k ? const Color(0xFF17130F) : Colors.transparent, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(t, style: HF.hi(14.5, color: tab == k ? const Color(0xFFF3E6C4) : const Color(0xFF8A7F68), w: FontWeight.w800)),
                const SizedBox(width: 7),
                Container(constraints: const BoxConstraints(minWidth: 24), height: 24, padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center, decoration: BoxDecoration(color: n > 0 ? hot : const Color(0xFFCFC6B3), borderRadius: BorderRadius.circular(99)), child: Text('${n > 0 ? n : all}', style: HF.num(12, color: Colors.white))),
              ]),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12), padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: const Color(0xFFECE4D2), borderRadius: BorderRadius.circular(99)),
      child: Row(children: [b('app', '📱 ऐप ऑर्डर', an, a.length, const Color(0xFFE5383B)), b('ds', '🏪 डिजिटल दुकान', dn, d.length, const Color(0xFF16A34A))]),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final id = o['id'].toString(), isOpen = open.contains(id), st = o['status'], b = busy.contains(id);
    final items = (o['items'] as List?)?.whereType<Map>().toList() ?? [];
    final first = items.isEmpty ? {} : items.first;
    final name = '${o['customer_name'] ?? ''}'.trim().isEmpty ? 'ग्राहक' : '${o['customer_name']}';
    final km = o['km'];
    final short = o['order_id'] == null ? 'HFB-${o['bill_no']}' : '#HF-${o['order_id'].toString().replaceAll('-', '').substring(0, 4).toUpperCase()}';
    final qty = items.fold<num>(0, (s, i) => s + ((i['qty'] ?? 0) as num));
    Widget acts;
    if (st == 'new') {
      acts = Row(children: [
        Expanded(child: _btn('मना करें', Colors.white, const Color(0xFFA8401C), b ? null : () => _do(o, 'reject'), outline: true)),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: _btn(b ? '…' : 'स्वीकार करें', const Color(0xFFC8581D), Colors.white, b ? null : () => _do(o, 'accept'))),
      ]);
    } else if (st == 'packing') {
      acts = _btn(b ? '…' : '📦 पैक हो गया — राइडर को रिक्वेस्ट भेजें', const Color(0xFFC8581D), Colors.white, b ? null : () => _do(o, 'ready'));
    } else if ((o['rider_name'] ?? '').toString().isEmpty) {
      acts = Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(16)), child: Text('📡 पास के राइडरों को रिक्वेस्ट गई — कोई स्वीकार करेगा तो यहाँ दिखेगा${o['pickup_code'] != null ? '\nपिकअप कोड: ${o['pickup_code']}' : ''}', style: HF.hi(13, color: const Color(0xFF3730A3), w: FontWeight.w700)));
    } else {
      acts = Container(
        padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFECFDF3), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Text('🛵', style: TextStyle(fontSize: 24)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${o['rider_name']} आ रहे हैं', style: HF.hi(14, w: FontWeight.w800)), Text('पिकअप कोड: ${o['pickup_code'] ?? '—'} • राइडर स्लिप का QR स्कैन करेगा', style: HF.hi(11.5, color: const Color(0xFF4B6B57)))])),
          if ((o['rider_phone'] ?? '').toString().isNotEmpty) IconButton(onPressed: () => openUrl(context, 'tel:+${o['rider_phone']}'), icon: const Icon(Icons.call, color: Color(0xFF16A34A))),
        ]),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: st == 'new' ? const Color(0xFFF0B25A) : const Color(0xFFEFE6D2), width: 1.5), boxShadow: st == 'new' ? const [BoxShadow(color: Color(0x2EF0B25A), blurRadius: 22, offset: Offset(0, 8))] : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 52, height: 52, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF2D2A3E), Color(0xFF17151F)])), child: Text(name.characters.first.toUpperCase(), style: HF.num(20, color: Colors.white, w: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(18, w: FontWeight.w700))), const SizedBox(width: 4), const Icon(Icons.verified, size: 17, color: Color(0xFF2563EB))]),
            Text('🛍 ${tab == 'app' ? 'ऐप ऑर्डर' : 'डिजिटल दुकान'} · $short', style: HF.hi(12.5, color: const Color(0xFF8A5A1C), w: FontWeight.w700)),
            Text('📍 ${'${o['customer_address'] ?? ''}'.split(',').reversed.take(2).toList().reversed.join(',').trim()}${km != null ? ' · $km km' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: const Color(0xFF8A8373))),
          ])),
          Text(_ago(o), style: HF.hi(13, color: st == 'new' ? const Color(0xFFE86A0C) : const Color(0xFF2B7A4B), w: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => isOpen ? open.remove(id) : open.add(id)),
          child: Container(
            padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF8F3E8), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: prodImg(first['image_url'], 52, 52, r: 14)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${first['name_hi'] ?? first['name'] ?? ''}${items.length > 1 ? ' +${items.length - 1}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(15, w: FontWeight.w800)),
                Text('$qty आइटम · ${o['pay'] == 'upi' ? 'UPI' : 'कैश ऑन डिलीवरी'}', style: HF.hi(12, color: const Color(0xFF8A8373))),
              ])),
              Text(rupee((o['total'] ?? 0) as num), style: HF.num(17)),
              const SizedBox(width: 4),
              Icon(isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: const Color(0xFF8A7F68)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut,
          child: !isOpen ? const SizedBox(width: double.infinity) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final drop = ll(o['lat'], o['lng']), shop = ll(o['shop_lat'], o['shop_lng']);
              if (drop == null && shop == null) return const SizedBox.shrink();
              return Stack(children: [
                RouteMap(shop: shop, drop: drop, height: 140),
                if (km != null) Positioned(left: 8, bottom: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xD917130F), borderRadius: BorderRadius.circular(99)), child: Text('🧭 $km km · ~${((km as num) * 8).round().clamp(3, 99)} min', style: HF.num(13, color: Colors.white, w: FontWeight.w700)))),
              ]);
            }),
            const SizedBox(height: 6),
            for (final i in items)
              Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
                ClipOval(child: prodImg(i['image_url'], 32, 32, r: 0)), const SizedBox(width: 10),
                Expanded(child: Text('${i['name_hi'] ?? i['name']}', style: HF.hi(14, w: FontWeight.w600))),
                Text('× ${i['qty']}', style: HF.num(14, color: const Color(0xFF8A7F68))),
                SizedBox(width: 64, child: Text(rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num)), textAlign: TextAlign.right, style: HF.num(14))),
              ])),
          ]),
        ),
        const SizedBox(height: 12),
        acts,
      ]),
    );
  }

  Widget _btn(String t, Color bg, Color fg, VoidCallback? f, {bool outline = false}) => GestureDetector(
        onTap: f,
        child: Opacity(opacity: f == null ? .6 : 1, child: Container(height: 52, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18), border: outline ? Border.all(color: const Color(0xFFE6D7B7), width: 1.5) : null, boxShadow: outline ? null : const [BoxShadow(color: Color(0x4DC8581D), blurRadius: 18, offset: Offset(0, 8))]), child: Text(t, textAlign: TextAlign.center, style: HF.hi(15, color: fg, w: FontWeight.w800)))),
      );

  @override
  Widget build(BuildContext context) {
    final list = tab == 'app' ? _app() : _ds();
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFFDFAF3), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: ListView(controller: widget.sc, padding: const EdgeInsets.fromLTRB(16, 10, 16, 30), children: [
        Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD9D2C0), borderRadius: BorderRadius.circular(9)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('रिक्वेस्ट', style: HF.num(26, w: FontWeight.w800))),
          GestureDetector(onTap: () => Navigator.pop(context), child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFEFE7D6), shape: BoxShape.circle), child: const Icon(Icons.close))),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async { setState(() => auto = !auto); final p = await SharedPreferences.getInstance(); await p.setBool('rq_auto', auto); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFF3ECDD), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Expanded(child: Text('⚡ स्वीकार करते ही राइडर को रिक्वेस्ट अपने-आप', style: HF.hi(12.5, color: const Color(0xFF6B5A3A), w: FontWeight.w700))),
              Switch(value: auto, activeColor: Colors.white, activeTrackColor: const Color(0xFF16A34A), onChanged: (v) async { setState(() => auto = v); final p = await SharedPreferences.getInstance(); await p.setBool('rq_auto', v); }),
            ]),
          ),
        ),
        _seg(),
        if (list.isEmpty)
          Padding(padding: const EdgeInsets.all(40), child: Column(children: [
            Text(tab == 'app' ? '📭' : '🏪', style: const TextStyle(fontSize: 42)),
            Text('अभी कोई रिक्वेस्ट नहीं', style: HF.hi(15, w: FontWeight.w800)),
            Text(tab == 'app' ? 'नया ऑर्डर आते ही घंटी बजेगी और यहाँ दिखेगा' : 'आपकी डिजिटल दुकान से आए ऑर्डर यहाँ दिखेंगे', textAlign: TextAlign.center, style: HF.hi(12.5, color: HF.mut)),
          ])),
        for (final o in list) _card(o),
      ]),
    );
  }
}
