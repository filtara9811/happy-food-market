import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Inventory: which admin products this shop sells, how many are in stock, and the shop's own counter (POS) price.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Map<String, dynamic>> cat = [];
  final edit = <String, Map<String, dynamic>>{};
  bool loading = true, busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try { final c = await Api.catalog(); if (mounted) setState(() { cat = c; loading = false; edit.clear(); }); } catch (e) { if (mounted) { setState(() => loading = false); hfToast(context, errText(e)); } }
  }

  Map<String, dynamic> cur(Map p) => edit[p['product_id']] ?? {'qty': p['qty'] ?? 0, 'shop_price': p['shop_price'], 'active': p['active'] == true};

  void upd(Map p, String k, dynamic v) => setState(() { final c = Map<String, dynamic>.from(cur(p)); c[k] = v; edit[p['product_id'].toString()] = c; });

  Future<void> save() async {
    setState(() => busy = true);
    try {
      for (final e in edit.entries) {
        await Api.rpc('vendor_set_stock', {'p_product_id': e.key, 'p_qty': e.value['qty'], 'p_shop_price': e.value['shop_price'], 'p_active': e.value['active']});
      }
      if (mounted) hfToast(context, 'इन्वेंट्री सेव हो गई ✅');
      await load();
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: HF.bg,
        appBar: AppBar(backgroundColor: HF.bg, elevation: 0, title: Text('📦 इन्वेंट्री', style: HF.num(20))),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: HF.goldDeep))
            : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
                Text('जो सामान आपकी दुकान में है उसे चालू करें, गिनती भरें। "मेरा दाम" सिर्फ़ आपके काउंटर/QR बिल के लिए है — ऐप के ग्राहक एडमिन का दाम देते हैं।', style: HF.hi(12.5, color: HF.mut)),
                const SizedBox(height: 12),
                if (cat.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Text('आपकी कैटेगरी में अभी कोई प्रोडक्ट नहीं', textAlign: TextAlign.center, style: HF.hi(14, color: HF.mut))),
                for (final p in cat) Padding(padding: const EdgeInsets.only(bottom: 10), child: _row(p)),
              ]),
        bottomSheet: edit.isEmpty
            ? null
            : Container(padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10), color: HF.card, child: GoldButton(busy ? 'सेव हो रहा…' : '💾 ${edit.length} बदलाव सेव करें', onTap: busy ? null : save)),
      );

  Widget _row(Map<String, dynamic> p) {
    final c = cur(p), on = c['active'] == true, q = (c['qty'] ?? 0) as num;
    return HFCard(
      padding: const EdgeInsets.all(12),
      color: on ? Colors.white : const Color(0xFFF7F3EA),
      child: Column(children: [
        Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: (p['image_url'] ?? '').toString().startsWith('http') ? Image.network(p['image_url'], width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52)) : const SizedBox(width: 52, height: 52, child: Center(child: Text('🍛', style: TextStyle(fontSize: 24))))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name_hi'] ?? p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(15, w: FontWeight.w800)),
            Text('ऐप का दाम ${rupee((p['price'] ?? 0) as num)}', style: HF.hi(12, color: HF.mut)),
          ])),
          Toggle(on, (v) => upd(p, 'active', v)),
        ]),
        if (on) ...[
          const SizedBox(height: 10),
          Row(children: [
            Text('स्टॉक', style: HF.hi(13, w: FontWeight.w800)),
            const SizedBox(width: 8),
            _sq(Icons.remove, () => upd(p, 'qty', q > 0 ? q - 1 : 0)),
            SizedBox(width: 44, child: Text('$q', textAlign: TextAlign.center, style: HF.num(18))),
            _sq(Icons.add, () => upd(p, 'qty', q + 1)),
            const Spacer(),
            SizedBox(
              width: 104,
              child: TextFormField(
                initialValue: c['shop_price'] == null ? '' : '${c['shop_price']}',
                keyboardType: TextInputType.number,
                onChanged: (v) => upd(p, 'shop_price', num.tryParse(v)),
                decoration: InputDecoration(isDense: true, labelText: 'मेरा दाम ₹', filled: true, fillColor: HF.card2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _sq(IconData i, VoidCallback f) => GestureDetector(onTap: f, child: Container(width: 34, height: 34, decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(10)), child: Icon(i, size: 18)));
}
