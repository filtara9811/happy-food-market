import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shop_ui.dart';
import 'pos.dart';

/// POS tab on the home screen: tap tap tap on items → bill. Tap = +1, long-press = −1.
class PosQuick extends StatefulWidget {
  final Map<String, dynamic> me;
  final VoidCallback openInventory;
  final void Function(int count, num total) onBill;
  final Future<void> Function() reload;
  const PosQuick({super.key, required this.me, required this.openInventory, required this.onBill, required this.reload});
  @override
  State<PosQuick> createState() => PosQuickState();
}

class PosQuickState extends State<PosQuick> {
  List<Map<String, dynamic>> cat = [];
  final bill = <String, int>{};
  bool loading = true;
  String q = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try { final c = await Api.catalog(); if (mounted) setState(() { cat = c.where((p) => p['active'] == true).toList(); loading = false; }); }
    catch (e) { if (mounted) { setState(() => loading = false); hfToast(context, errText(e)); } }
    _notify();
  }

  num price(Map p) => (p['shop_price'] ?? p['price'] ?? 0) as num;
  int get count => bill.values.fold(0, (a, b) => a + b);
  num get total => cat.fold<num>(0, (s, p) => s + price(p) * (bill[p['product_id'].toString()] ?? 0));
  void _notify() => WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.onBill(count, total); });

  void add(Map p, int d) {
    final id = p['product_id'].toString(), n = (bill[id] ?? 0) + d, stock = (p['qty'] ?? 0) as num;
    if (d > 0 && n > stock) { hfToast(context, stock <= 0 ? 'स्टॉक ख़त्म — इन्वेंट्री में भरें' : 'इतना ही स्टॉक है ($stock नग)'); return; }
    HapticFeedback.selectionClick();
    setState(() { if (n <= 0) { bill.remove(id); } else { bill[id] = n; } });
    _notify();
  }

  void clear() { setState(bill.clear); _notify(); }

  Future<void> openBill() async {
    if (count == 0) return;
    final had = count;
    final done = await showBill(context, widget.me, cat, bill);
    if (done == true || (had > 0 && bill.isEmpty)) { bill.clear(); await load(); await widget.reload(); } else if (mounted) { setState(() {}); }
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final list = cat.where((p) => q.isEmpty || '${p['name']} ${p['name_hi']}'.toLowerCase().contains(q.toLowerCase())).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(children: [
          Expanded(child: Container(
            height: 46, padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)),
            child: Row(children: [const Icon(Icons.search, size: 20, color: HF.mut), const SizedBox(width: 8), Expanded(child: TextField(onChanged: (v) => setState(() => q = v), style: HF.hi(14.5), decoration: InputDecoration.collapsed(hintText: 'सामान खोजें…', hintStyle: HF.hi(14, color: HF.mut, w: FontWeight.w500))))]),
          )),
          const SizedBox(width: 8),
          GestureDetector(onTap: widget.openInventory, child: Container(height: 46, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)), child: Text('📦 स्टॉक', style: HF.hi(13.5, w: FontWeight.w800)))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 2),
        child: Row(children: [
          Expanded(child: Text('👆 दबाएँ = बिल में +1 • देर तक दबाएँ = −1', style: HF.hi(11.5, color: HF.mut, w: FontWeight.w600))),
          if (count > 0) GestureDetector(onTap: clear, child: Text('सब हटाएँ', style: HF.hi(12.5, color: HF.bad, w: FontWeight.w800))),
        ]),
      ),
      if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: HF.goldDeep))),
      if (!loading && cat.isEmpty)
        Padding(padding: const EdgeInsets.all(26), child: Column(children: [
          const Text('📦', style: TextStyle(fontSize: 42)),
          Text('बिल बनाने के लिए पहले अपनी दुकान का सामान चालू करें', textAlign: TextAlign.center, style: HF.hi(14.5, w: FontWeight.w800)),
          const SizedBox(height: 12),
          GoldButton('➕ इन्वेंट्री भरें', onTap: widget.openInventory),
        ])),
      if (!loading && cat.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .72, children: [for (final p in list) _tile(p)]),
        ),
    ]);
  }

  Widget _tile(Map<String, dynamic> p) {
    final n = bill[p['product_id'].toString()] ?? 0, stock = (p['qty'] ?? 0) as num;
    return GestureDetector(
      onTap: () => add(p, 1),
      onLongPress: n > 0 ? () => add(p, -1) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: n > 0 ? const Color(0xFFECFDF3) : HF.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: n > 0 ? const Color(0xFF16A34A) : HF.line, width: n > 0 ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(children: [
            Positioned.fill(child: Opacity(opacity: stock <= 0 ? .4 : 1, child: prodImg(p['image_url'], double.infinity, double.infinity, r: 13))),
            Positioned(left: 4, top: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: stock <= 0 ? HF.bad : (stock <= 2 ? const Color(0xFFD97706) : Colors.black54), borderRadius: BorderRadius.circular(99)), child: Text(stock <= 0 ? 'ख़त्म' : '$stock', style: HF.num(10, color: Colors.white, w: FontWeight.w800)))),
            if (n > 0) Positioned(right: 4, top: 4, child: Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF16A34A), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Text('$n', style: HF.num(13, color: Colors.white)))),
          ])),
          const SizedBox(height: 4),
          Text('${p['name_hi'] ?? p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12.5, w: FontWeight.w800)),
          Text(rupee(price(p)), style: HF.num(13, color: HF.goldDeep, w: FontWeight.w800)),
        ]),
      ),
    );
  }
}
