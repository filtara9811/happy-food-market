import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Counter bill: tap items, pick cash / UPI, save. Uses the shop's own price when set.
Future<bool?> showPos(BuildContext context) => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PosPage()));

class PosPage extends StatefulWidget {
  const PosPage({super.key});
  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  List<Map<String, dynamic>> cat = [];
  final qty = <String, int>{};
  String pay = 'cash', q = '';
  final phone = TextEditingController();
  bool loading = true, busy = false;
  Map<String, dynamic>? receipt;

  @override
  void initState() {
    super.initState();
    Api.catalog().then((c) { if (mounted) setState(() { cat = c; loading = false; }); }).catchError((e) { if (mounted) { setState(() => loading = false); hfToast(context, errText(e)); } });
  }

  num priceOf(Map p) => (p['shop_price'] ?? p['price'] ?? 0) as num;
  num get total => cat.fold<num>(0, (s, p) => s + priceOf(p) * (qty[p['product_id']] ?? 0));
  int get count => qty.values.fold(0, (a, b) => a + b);

  Future<void> save() async {
    if (count == 0) return hfToast(context, 'पहले सामान चुनें');
    setState(() => busy = true);
    try {
      final items = [for (final p in cat) if ((qty[p['product_id']] ?? 0) > 0) {'product_id': p['product_id'], 'qty': qty[p['product_id']], 'price': priceOf(p)}];
      final r = await Api.rpc('vendor_sale', {'p_items': items, 'p_pay': pay, 'p_phone': phone.text.trim().isEmpty ? null : phone.text.trim()});
      if (r is Map) setState(() => receipt = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (receipt != null) return _receipt();
    final list = cat.where((p) => q.isEmpty || '${p['name']} ${p['name_hi']}'.toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: HF.bg,
      appBar: AppBar(backgroundColor: HF.bg, title: Text('🧾 नया बिल', style: HF.num(20)), elevation: 0),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: HF.goldDeep))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 140), children: [
              TextField(onChanged: (v) => setState(() => q = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'सामान खोजें', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
              const SizedBox(height: 10),
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Text('आपकी कैटेगरी में अभी कोई सामान नहीं — एडमिन से प्रोडक्ट जुड़वाएँ', textAlign: TextAlign.center, style: HF.hi(14, color: HF.mut))),
              for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _item(p)),
            ]),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(top: Radius.circular(24)), boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 20)]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            for (final m in [['cash', '💵 कैश'], ['upi', '📱 UPI'], ['credit', '📒 उधार']])
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: GestureDetector(onTap: () => setState(() => pay = m[0]), child: Container(padding: const EdgeInsets.symmetric(vertical: 9), alignment: Alignment.center, decoration: BoxDecoration(color: pay == m[0] ? HF.goldLight : HF.card2, borderRadius: BorderRadius.circular(12), border: Border.all(color: pay == m[0] ? HF.goldDeep : Colors.transparent, width: 1.5)), child: Text(m[1], style: HF.hi(13.5, w: FontWeight.w800)))))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(isDense: true, hintText: 'ग्राहक का नंबर (ज़रूरी नहीं)', filled: true, fillColor: HF.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 10),
          GoldButton(busy ? 'सेव हो रहा…' : '$count सामान • ${rupee(total)} — बिल बनाएँ', onTap: busy || count == 0 ? null : save),
        ]),
      ),
    );
  }

  Widget _item(Map<String, dynamic> p) {
    final id = p['product_id'].toString(), n = qty[id] ?? 0, stock = (p['qty'] ?? 0) as num;
    return HFCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: (p['image_url'] ?? '').toString().startsWith('http') ? Image.network(p['image_url'], width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52, child: Center(child: Text('🍛')))) : const SizedBox(width: 52, height: 52, child: Center(child: Text('🍛', style: TextStyle(fontSize: 24))))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name_hi'] ?? p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(14.5, w: FontWeight.w800)),
          Text('${rupee(priceOf(p))}  •  स्टॉक $stock', style: HF.hi(12, color: stock > 0 ? HF.mut : HF.bad)),
        ])),
        if (n == 0)
          GestureDetector(onTap: () => setState(() => qty[id] = 1), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: HF.goldLight, borderRadius: BorderRadius.circular(12)), child: Text('+ जोड़ें', style: HF.hi(13.5, w: FontWeight.w800))))
        else
          Row(children: [
            _sq(Icons.remove, () => setState(() { qty[id] = n - 1; if (qty[id]! <= 0) qty.remove(id); })),
            SizedBox(width: 34, child: Text('$n', textAlign: TextAlign.center, style: HF.num(18))),
            _sq(Icons.add, () => setState(() => qty[id] = n + 1)),
          ]),
      ]),
    );
  }

  Widget _sq(IconData i, VoidCallback f) => GestureDetector(onTap: f, child: Container(width: 34, height: 34, decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(10)), child: Icon(i, size: 18)));

  Widget _receipt() {
    final r = receipt!, items = (r['items'] as List?)?.whereType<Map>().toList() ?? [];
    return Scaffold(
      backgroundColor: HF.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 10),
          const Center(child: Text('✅', style: TextStyle(fontSize: 56))),
          Center(child: Text('बिल #${r['bill_no']} बन गया', style: HF.num(24))),
          const SizedBox(height: 16),
          HFCard(child: Column(children: [
            for (final i in items)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [Expanded(child: Text('${i['qty']}× ${i['name_hi'] ?? i['name']}', style: HF.hi(14.5, w: FontWeight.w700))), Text(rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num)), style: HF.hi(14.5, w: FontWeight.w800))])),
            const Divider(),
            Row(children: [Expanded(child: Text('कुल (${pay.toUpperCase()})', style: HF.hi(16, w: FontWeight.w800))), Text(rupee((r['total'] ?? 0) as num), style: HF.num(22, color: HF.goldDeep))]),
          ])),
          const SizedBox(height: 16),
          Text('🖨️ Bluetooth प्रिंटर अगले अपडेट में', textAlign: TextAlign.center, style: HF.hi(13, color: HF.mut)),
          const SizedBox(height: 16),
          GoldButton('➕ अगला बिल', onTap: () => setState(() { receipt = null; qty.clear(); phone.clear(); Api.catalog().then((c) { if (mounted) setState(() => cat = c); }); })),
          const SizedBox(height: 10),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('होम पर जाएँ', style: HF.hi(15, color: HF.goldDeep))),
        ]),
      ),
    );
  }
}
