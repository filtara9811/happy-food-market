import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shop_ui.dart';
import 'pos.dart';

/// "मेरी इन्वेंट्री" sheet — same layout as the web shop panel: my category, dark stock card,
/// orders per 3 hours, "I sell / add more", product grid. Tap ADD = put in the bill, long-press = stock / price.
Future<bool?> showInventory(BuildContext context, Map<String, dynamic> me, List<Map<String, dynamic>> orders) =>
    hfSheet<bool>(context, (c, ctl) => InventorySheet(me: me, orders: orders, ctl: ctl), size: .94);

class InventorySheet extends StatefulWidget {
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> orders;
  final ScrollController ctl;
  const InventorySheet({super.key, required this.me, required this.orders, required this.ctl});
  @override
  State<InventorySheet> createState() => _InventorySheetState();
}

class _InventorySheetState extends State<InventorySheet> {
  List<Map<String, dynamic>> cat = [];
  bool loading = true, mine = true, grid = true, changed = false;
  String q = '', sub = 'all';
  final bill = <String, int>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try { final c = await Api.catalog(); if (mounted) setState(() { cat = c; loading = false; if (c.where((p) => p['active'] == true).isEmpty) mine = false; }); }
    catch (e) { if (mounted) { setState(() => loading = false); hfToast(context, errText(e)); } }
  }

  bool _on(Map p) => p['active'] == true;
  num _qty(Map p) => (p['qty'] ?? 0) as num;
  num price(Map p) => (p['shop_price'] ?? p['price'] ?? 0) as num;
  String nm(Map p) => (p['name_hi'] ?? p['name'] ?? '').toString();

  List<Map<String, dynamic>> get _today {
    final now = DateTime.now();
    return widget.orders.where((o) { final t = DateTime.tryParse('${o['created_at']}')?.toLocal(); return t != null && t.year == now.year && t.month == now.month && t.day == now.day && o['status'] != 'cancelled'; }).toList();
  }

  int get billCount => bill.values.fold(0, (a, b) => a + b);

  Future<void> setStock(Map p, {num? qty, num? shopPrice, bool? active, bool keepPrice = true}) async {
    final nq = qty ?? _qty(p), na = active ?? _on(p);
    final sp = shopPrice ?? (keepPrice ? p['shop_price'] : null);
    try {
      await Api.rpc('vendor_set_stock', {'p_product_id': p['product_id'], 'p_qty': nq, 'p_shop_price': sp, 'p_active': na});
      setState(() { p['qty'] = nq; p['active'] = na; p['shop_price'] = sp; changed = true; });
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  void addToBill(Map p) {
    final id = p['product_id'].toString(), n = bill[id] ?? 0;
    if (n >= _qty(p)) { hfToast(context, _qty(p) <= 0 ? 'स्टॉक ख़त्म — देर तक दबाकर स्टॉक भरें' : 'इतना ही स्टॉक है (${_qty(p)} नग)'); return; }
    HapticFeedback.lightImpact();
    setState(() => bill[id] = n + 1);
  }

  Future<void> openBill() async {
    final had = billCount;
    final done = await showBill(context, widget.me, cat, bill);
    if (done == true || (had > 0 && bill.isEmpty)) { bill.clear(); changed = true; await load(); } else if (mounted) { setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    final st = storeOf(widget.me['store']?.toString());
    final extra = ((widget.me['extra_stores'] as List?) ?? []).map((e) => storeOf(e.toString())).toList();
    final my = cat.where(_on).toList();
    final units = my.fold<num>(0, (s, p) => s + _qty(p));
    final today = _today, soldUnits = today.fold<num>(0, (s, o) => s + ((o['items'] as List?) ?? []).fold<num>(0, (a, i) => a + ((i['qty'] ?? 0) as num)));
    final counter = today.where((o) => o['source'] == 'pos').fold<num>(0, (s, o) => s + ((o['total'] ?? 0) as num));
    final low = my.where((p) => _qty(p) <= 2).length;
    final shown = (mine ? my : cat.where((p) => !_on(p)).toList()).where((p) => q.isEmpty || '${p['name']} ${p['name_hi']}'.toLowerCase().contains(q.toLowerCase())).toList();
    return Stack(children: [
        ListView(controller: widget.ctl, padding: const EdgeInsets.only(bottom: 120), children: [
          sheetHead(context, 'मेरी इन्वेंट्री'),
          // my category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Row(children: [
              Text('मेरी श्रेणी', style: HF.hi(11.5, color: HF.mut, w: FontWeight.w700)),
              const SizedBox(width: 8),
              _catChip('${st[1]} ${st[2]}', true),
              for (final e in extra) Padding(padding: const EdgeInsets.only(left: 6), child: _catChip('${e[1]} ${e[2]}', true)),
              const SizedBox(width: 6),
              GestureDetector(onTap: () => _askCategory(), child: _catChip('+ दूसरी श्रेणी', false)),
            ]),
          ),
          // dark stock card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 10))]),
            child: Column(children: [
              Row(children: [Text('📦 मेरा स्टॉक', style: HF.hi(15, color: Colors.white, w: FontWeight.w800)), const Spacer(), Text('आज', style: HF.hi(11, color: Colors.white54, w: FontWeight.w700))]),
              const SizedBox(height: 10),
              Row(children: [
                _stockTile('$units', 'बचे नग'),
                _stockTile('$soldUnits', 'आज बिके'),
                _stockTile(rupee(counter), 'काउंटर बिक्री'),
                _stockTile('$low', 'भरना है', hot: true, onTap: low > 0 ? () => setState(() { mine = true; q = ''; }) : null),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _darkBtn('📱 मेरा QR', () => showMyQr(context, widget.me)),
                _darkBtn('🖼️ बैनर', () => hfToast(context, 'बैनर अगले अपडेट में — अभी QR और डिजिटल दुकान चालू है')),
                _darkBtn('🏪 डिजिटल दुकान', () => openUrl(context, shopLink(widget.me['id']))),
              ]),
            ]),
          ),
          // orders every 3 hours
          _slots(today),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFE9EEDB), borderRadius: BorderRadius.circular(16)),
            child: Text('✅ कोई नया ऑर्डर बाकी नहीं — नया आते ही यहाँ और घंटी के साथ दिखेगा', style: HF.hi(12.5, color: const Color(0xFF166534), w: FontWeight.w700)),
          ),
          // I sell / add more
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: Color.alphaBlend(HF.goldDeep.withValues(alpha: .12), HF.card2), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              _seg('📦 मैं बेचता हूँ (${my.length})', mine, () => setState(() => mine = true)),
              _seg('🔗 और जोड़ें', !mine, () => setState(() => mine = false)),
            ]),
          ),
          // search + view toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(child: Container(
                height: 46, padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)),
                child: Row(children: [const Icon(Icons.search, size: 20, color: HF.mut), const SizedBox(width: 8), Expanded(child: TextField(onChanged: (v) => setState(() => q = v), style: HF.hi(14.5), decoration: InputDecoration.collapsed(hintText: 'आइटम खोजें…', hintStyle: HF.hi(14, color: HF.mut, w: FontWeight.w500))))]),
              )),
              const SizedBox(width: 8),
              Container(
                height: 46, padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)),
                child: Row(children: [_vt(Icons.grid_view_rounded, grid, () => setState(() => grid = true)), _vt(Icons.view_list_rounded, !grid, () => setState(() => grid = false))]),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 4), child: Text(mine ? '👆 ADD = बिल में जोड़ें • आइटम को देर तक दबाएँ = स्टॉक / रेट / हटाएँ' : '👆 "+ जोड़ें" दबाकर अपनी दुकान में यह सामान चालू करें', style: HF.hi(11.5, color: HF.mut, w: FontWeight.w600))),
          if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
          if (!loading && shown.isEmpty)
            Padding(padding: const EdgeInsets.all(30), child: Column(children: [Text(mine ? '📦' : '✅', style: const TextStyle(fontSize: 40)), Text(mine ? (cat.isEmpty ? 'आपकी श्रेणी में अभी कोई प्रोडक्ट नहीं — एडमिन जोड़ेंगे' : 'अभी कुछ नहीं बेच रहे — "और जोड़ें" से सामान चुनें') : 'सब सामान आपकी दुकान में जुड़ चुका है', textAlign: TextAlign.center, style: HF.hi(14, color: HF.mut, w: FontWeight.w700))])),
          if (!loading && shown.isNotEmpty)
            grid
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .66, children: [for (final p in shown) _card(p)]),
                  )
                : Column(children: [for (final p in shown) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: _row(p))]),
        ]),
        // floating bill basket
        if (billCount > 0)
          Positioned(
            right: 18, bottom: 26 + MediaQuery.of(context).padding.bottom,
            child: GestureDetector(
              onTap: openBill,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Color(0x6616A34A), blurRadius: 20, offset: Offset(0, 8))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), shape: BoxShape.circle), child: const Text('🧺', style: TextStyle(fontSize: 24))),
                    Positioned(right: -4, top: -4, child: Container(constraints: const BoxConstraints(minWidth: 22), height: 22, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: HF.gold, borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white, width: 2)), child: Text('$billCount', style: HF.num(11, color: HF.ink)))),
                  ]),
                  const SizedBox(width: 10),
                  Text('बिल', style: HF.hi(17, color: Colors.white, w: FontWeight.w800)),
                ]),
              ),
            ),
          ),
      ]);
  }

  Widget _catChip(String t, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: on ? const Color(0xFFFDF3D6) : HF.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? HF.gold : HF.line, width: on ? 2 : 1)),
        child: Text(t, style: HF.hi(13, color: on ? HF.ink : HF.goldDeep, w: FontWeight.w800)),
      );

  void _askCategory() {
    hfToast(context, 'दूसरी श्रेणी एडमिन चालू करते हैं — WhatsApp पर माँगें');
    whatsApp(context, 'नमस्ते, मेरी दुकान "${widget.me['shop_name']}" में दूसरी श्रेणी भी चालू कर दीजिए।', phone: '919540068380');
  }

  Widget _stockTile(String v, String l, {bool hot = false, VoidCallback? onTap}) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: hot ? HF.gold : Colors.white.withValues(alpha: .12), width: hot ? 1.5 : 1)),
            child: Column(children: [
              FittedBox(child: Text(v, style: HF.num(18, color: hot ? HF.goldLight : Colors.white, w: FontWeight.w800))),
              const SizedBox(height: 2),
              Text(l, style: HF.hi(10.5, color: Colors.white60, w: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _darkBtn(String t, VoidCallback f) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3), height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: .14))),
            child: FittedBox(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: HF.hi(12.5, color: Colors.white, w: FontWeight.w800)))),
          ),
        ),
      );

  Widget _slots(List<Map<String, dynamic>> today) {
    const labels = ['6-9', '9-12', '12-3', '3-6', '6-9', '9-12'];
    final counts = List.filled(6, 0);
    for (final o in today) {
      final h = DateTime.tryParse('${o['created_at']}')?.toLocal().hour ?? -1;
      if (h >= 6) counts[((h - 6) ~/ 3).clamp(0, 5)]++;
    }
    final now = DateTime.now().hour, cur = now >= 6 ? ((now - 6) ~/ 3).clamp(0, 5) : -1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.line)),
      child: Column(children: [
        Row(children: [Text('⏱️ आज के ऑर्डर — हर 3 घंटे', style: HF.hi(13, w: FontWeight.w800)), const Spacer(), Text('${today.length}', style: HF.num(14, color: HF.goldDeep, w: FontWeight.w800))]),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 6; i++)
            Expanded(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5), padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(color: i == cur ? const Color(0xFFFDF3D6) : HF.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: i == cur ? HF.gold : Colors.transparent)),
              child: Column(children: [Text(labels[i], style: HF.hi(10.5, color: HF.mut, w: FontWeight.w700)), Text('${counts[i]}', style: HF.num(15, w: FontWeight.w800))]),
            )),
        ]),
      ]),
    );
  }

  Widget _seg(String t, bool on, VoidCallback f) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? HF.card : Colors.transparent, borderRadius: BorderRadius.circular(14), boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))] : null),
            child: Text(t, style: HF.hi(13.5, color: on ? HF.tx : HF.goldDeep, w: FontWeight.w800)),
          ),
        ),
      );

  Widget _vt(IconData i, bool on, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(width: 38, height: 38, decoration: BoxDecoration(color: on ? const Color(0xFFFDF3D6) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Icon(i, size: 20, color: on ? HF.goldDeep : HF.mut)),
      );

  Widget _badge(Map p) {
    final n = _qty(p), c = n <= 0 ? HF.bad : (n <= 2 ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(99)), child: Text(n <= 0 ? 'ख़त्म' : '$n नग', style: HF.hi(11, color: Colors.white, w: FontWeight.w800)));
  }

  Widget _addBtn(Map p) {
    final id = p['product_id'].toString(), n = bill[id] ?? 0;
    if (!mine) return GestureDetector(onTap: () async { await setStock(p, active: true, qty: _qty(p)); if (mounted) { hfToast(context, '${nm(p)} दुकान में जुड़ा ✅ — अब स्टॉक भरें'); _editor(p); } }, child: _pillAdd('+ जोड़ें'));
    if (n == 0) return GestureDetector(onTap: () => addToBill(p), child: _pillAdd('ADD'));
    return Container(
      height: 36, decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() { if (n <= 1) { bill.remove(id); } else { bill[id] = n - 1; } }), icon: const Icon(Icons.remove, size: 18, color: Colors.white)),
        Text('$n', style: HF.num(15, color: Colors.white)),
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => addToBill(p), icon: const Icon(Icons.add, size: 18, color: Colors.white)),
      ]),
    );
  }

  Widget _pillAdd(String t) => Container(height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF16A34A), width: 1.5)), child: Text(t, style: HF.num(14, color: const Color(0xFF16A34A), w: FontWeight.w800)));

  Widget _card(Map<String, dynamic> p) => GestureDetector(
        onLongPress: mine ? () { HapticFeedback.mediumImpact(); _editor(p); } : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Stack(children: [
              Positioned.fill(child: prodImg(p['image_url'], double.infinity, double.infinity, r: 16)),
              if (mine) Positioned(left: 6, top: 6, child: _badge(p)),
            ])),
            const SizedBox(height: 6),
            Text(nm(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(14, w: FontWeight.w800)),
            Row(children: [
              Text(rupee(price(p)), style: HF.num(15, color: HF.goldDeep, w: FontWeight.w800)),
              if (p['shop_price'] != null && p['shop_price'] != p['price']) ...[const SizedBox(width: 6), Text('ऐप ${rupee((p['price'] ?? 0) as num)}', style: HF.hi(10.5, color: HF.mut))],
            ]),
            const SizedBox(height: 6),
            _addBtn(p),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> p) => GestureDetector(
        onLongPress: mine ? () => _editor(p) : null,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.line)),
          child: Row(children: [
            prodImg(p['image_url'], 56, 56),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nm(p), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(14.5, w: FontWeight.w800)),
              Row(children: [Text(rupee(price(p)), style: HF.num(14, color: HF.goldDeep, w: FontWeight.w800)), const SizedBox(width: 8), if (mine) _badge(p)]),
            ])),
            SizedBox(width: 104, child: _addBtn(p)),
          ]),
        ),
      );

  /// Long-press editor: stock count with quick +5 +10…, on/off, my price, remove from shop.
  void _editor(Map p) {
    num qty = _qty(p);
    bool on = _on(p);
    final pc = TextEditingController(text: p['shop_price'] == null ? '' : '${p['shop_price']}');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(builder: (c, ss) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: Container(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 20 + MediaQuery.of(c).padding.bottom),
              decoration: const BoxDecoration(color: HF.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  ClipOval(child: prodImg(p['image_url'], 58, 58, r: 0)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(nm(p), style: HF.hi(17, w: FontWeight.w800)), Text('${rupee(price(p))} • ऐप का दाम ${rupee((p['price'] ?? 0) as num)}', style: HF.hi(12.5, color: HF.mut))])),
                  GestureDetector(onTap: () => Navigator.pop(c), child: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 14),
                Text('स्टॉक (कितने नग हैं)', style: HF.hi(13, w: FontWeight.w800)),
                const SizedBox(height: 6),
                Container(
                  height: 64, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: HF.gold, width: 2)),
                  child: Row(children: [
                    _bigStep('−', () => ss(() => qty = qty > 0 ? qty - 1 : 0)),
                    Expanded(child: Text('$qty', textAlign: TextAlign.center, style: HF.num(28))),
                    _bigStep('+', () => ss(() => qty = qty + 1)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  for (final d in [5, 10, 25, 50]) Expanded(child: GestureDetector(onTap: () => ss(() => qty += d), child: Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center, decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(12)), child: Text('+$d', style: HF.num(14, w: FontWeight.w800))))),
                  Expanded(child: GestureDetector(onTap: () => ss(() => qty = 0), child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)), child: Text('ख़त्म करें', style: HF.hi(12.5, color: HF.bad, w: FontWeight.w800))))),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [Expanded(child: Text(on ? '🟢 चालू — ऑर्डर आ रहे हैं' : '⚪ बंद — अभी नहीं बेच रहे', style: HF.hi(13.5, w: FontWeight.w800))), Toggle(on, (v) => ss(() => on = v))]),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pc, keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '✏️ मेरी दुकान का दाम ₹ (खाली = ऐप का दाम)', filled: true, fillColor: HF.card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HF.line))),
                ),
                const SizedBox(height: 4),
                Text('ऐप वाले ग्राहक हमेशा एडमिन वाला दाम देते हैं — आपका दाम सिर्फ़ काउंटर बिल और QR दुकान पर चलेगा।', style: HF.hi(11.5, color: HF.mut)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async { Navigator.pop(c); await setStock(p, qty: 0, active: false); if (mounted) hfToast(context, 'दुकान से हटाया'); },
                  child: Container(height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(16)), child: Text('🗑 दुकान से हटाएँ', style: HF.hi(14.5, color: HF.bad, w: FontWeight.w800))),
                ),
                const SizedBox(height: 10),
                GoldButton('हो गया ✓', onTap: () async {
                  Navigator.pop(c);
                  await setStock(p, qty: qty, active: on, shopPrice: num.tryParse(pc.text.trim()), keepPrice: false);
                  if (mounted) hfToast(context, 'स्टॉक सेव ✅');
                }),
              ]),
            ),
          )),
    );
  }

  Widget _bigStep(String t, VoidCallback f) => GestureDetector(onTap: f, child: Container(width: 64, alignment: Alignment.center, decoration: const BoxDecoration(color: HF.card2, borderRadius: BorderRadius.horizontal(left: Radius.circular(16), right: Radius.circular(16))), child: Text(t, style: HF.num(26))));
}
