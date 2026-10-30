import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shop_ui.dart';
import '../printer.dart';

/// "नया बिल" sheet (counter bill) and the "बिल बन गया" receipt — same as the web shop panel.
/// [bill] is product_id → count, shared with the inventory sheet so changes show up there too.
Future<bool?> showBill(BuildContext context, Map<String, dynamic> me, List<Map<String, dynamic>> cat, Map<String, int> bill) =>
    hfSheet<bool>(context, (c, ctl) => BillSheet(me: me, cat: cat, bill: bill, ctl: ctl), size: .92);

class BillSheet extends StatefulWidget {
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> cat;
  final Map<String, int> bill;
  final ScrollController ctl;
  const BillSheet({super.key, required this.me, required this.cat, required this.bill, required this.ctl});
  @override
  State<BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends State<BillSheet> {
  String pay = 'cash';
  final name = TextEditingController(), phone = TextEditingController(), disc = TextEditingController();
  bool busy = false;
  Map<String, dynamic>? receipt;

  num price(Map p) => (p['shop_price'] ?? p['price'] ?? 0) as num;
  List<Map<String, dynamic>> get lines => [for (final p in widget.cat) if ((widget.bill[p['product_id'].toString()] ?? 0) > 0) p];
  num get sub => lines.fold<num>(0, (s, p) => s + price(p) * widget.bill[p['product_id'].toString()]!);
  num get discount { final d = num.tryParse(disc.text.trim()) ?? 0; return d < 0 ? 0 : (d > sub ? sub : d); }
  int get nextNo => ((widget.me['total_bills'] ?? 0) as num).toInt() + 1;
  String billNo(dynamic n) => 'HFB-${n.toString().padLeft(4, '0')}';

  Future<void> make() async {
    if (lines.isEmpty) return;
    final ph = phone.text.replaceAll(RegExp(r'\D'), '');
    if (ph.isNotEmpty && ph.length != 10) { hfToast(context, 'मोबाइल नंबर 10 अंक का हो'); return; }
    setState(() => busy = true);
    try {
      final items = [for (final p in lines) {'product_id': p['product_id'], 'qty': widget.bill[p['product_id'].toString()], 'price': price(p)}];
      final r = await Api.rpc('vendor_bill', {'p_items': items, 'p_pay': pay, 'p_phone': ph.isEmpty ? null : ph, 'p_name': name.text.trim(), 'p_discount': discount});
      if (r is Map) setState(() { receipt = Map<String, dynamic>.from(r); widget.bill.clear(); });
      widget.me['total_bills'] = nextNo;
    } catch (e) {
      final s = e.toString();
      if (mounted) hfToast(context, s.contains('pos_not_allowed') ? 'एडमिन ने काउंटर बिलिंग बंद की है' : (s.contains('shop_suspended') ? 'दुकान सस्पेंड है — एडमिन से बात करें' : errText(e)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => receipt != null ? _receipt() : _bill();

  Widget _bill() {
    final shop = (widget.me['shop_name'] ?? '').toString();
    return Stack(children: [
      ListView(controller: widget.ctl, padding: const EdgeInsets.only(bottom: 130), children: [
        sheetHead(context, '🧾 नया बिल', sub: '$shop • बिल नंबर ${billNo(nextNo)}'),
        if (lines.isEmpty) Padding(padding: const EdgeInsets.all(30), child: Text('बिल ख़ाली है', textAlign: TextAlign.center, style: HF.hi(15, color: HF.mut))),
        for (final p in lines) _line(p),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Expanded(child: _input(name, 'ग्राहक का नाम (ज़रूरी नहीं)')),
            const SizedBox(width: 8),
            Expanded(child: _input(phone, 'मोबाइल (WhatsApp बिल)', num: true)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            for (final m in [['cash', '💵 कैश'], ['upi', '📱 UPI'], ['credit', '📒 उधार']])
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => pay = m[0]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160), height: 50, alignment: Alignment.center,
                    decoration: BoxDecoration(color: pay == m[0] ? const Color(0xFFDCFCE7) : HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: pay == m[0] ? const Color(0xFF16A34A) : HF.line, width: pay == m[0] ? 2 : 1)),
                    child: Text(m[1], style: HF.hi(15, color: pay == m[0] ? const Color(0xFF166534) : HF.tx, w: FontWeight.w800)),
                  ),
                ),
              )),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            Row(children: [Text('जोड़', style: HF.hi(14, w: FontWeight.w700)), const Spacer(), Text(rupee(sub), style: HF.num(15, w: FontWeight.w700))]),
            const SizedBox(height: 8),
            Row(children: [
              Text('छूट ', style: HF.hi(14, w: FontWeight.w700)), Text('(ज़्यादा से ज़्यादा ${rupee(sub)})', style: HF.hi(11, color: HF.mut)), const Spacer(),
              SizedBox(width: 90, height: 40, child: TextField(controller: disc, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, textAlign: TextAlign.right, style: HF.num(15), decoration: InputDecoration(hintText: '0', filled: true, fillColor: HF.card, contentPadding: const EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: HF.line))))),
            ]),
            const Divider(height: 22),
            Row(children: [Text('कुल', style: HF.hi(16, w: FontWeight.w800)), const Spacer(), Text(rupee(sub - discount), style: HF.num(24, color: const Color(0xFF16A34A)))]),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: TextButton(onPressed: () { widget.bill.clear(); Navigator.pop(context, false); }, child: Text('बिल ख़ाली करें', style: HF.hi(13.5, color: HF.mut, w: FontWeight.w700))))),
      ]),
      Positioned(
        left: 16, right: 16, bottom: 16 + MediaQuery.of(context).padding.bottom,
        child: _greenBtn(busy ? 'बन रहा है…' : '🧾 बिल बनाएँ • ${rupee(sub - discount)}', busy || lines.isEmpty ? null : make),
      ),
    ]);
  }

  Widget _input(TextEditingController c, String hint, {bool num = false}) => TextField(
        controller: c, keyboardType: num ? TextInputType.phone : TextInputType.name, style: HF.hi(14),
        decoration: InputDecoration(hintText: hint, hintStyle: HF.hi(12.5, color: HF.mut, w: FontWeight.w500), filled: true, fillColor: HF.card, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HF.line)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: HF.line))),
      );

  Widget _line(Map<String, dynamic> p) {
    final id = p['product_id'].toString(), n = widget.bill[id] ?? 0, stock = (p['qty'] ?? 0) as num;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.line)),
      child: Row(children: [
        ClipOval(child: prodImg(p['image_url'], 48, 48, r: 0)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name_hi'] ?? p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(14.5, w: FontWeight.w800)),
          Text('${rupee(price(p))} × $n = ${rupee(price(p) * n)}', style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)),
        ])),
        Container(
          height: 40, decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() { if (n <= 1) { widget.bill.remove(id); } else { widget.bill[id] = n - 1; } }), icon: const Icon(Icons.remove, size: 18, color: Colors.white)),
            Text('$n', style: HF.num(15, color: Colors.white)),
            IconButton(visualDensity: VisualDensity.compact, onPressed: () { if (n >= stock) { hfToast(context, 'इतना ही स्टॉक है ($stock नग)'); return; } setState(() => widget.bill[id] = n + 1); }, icon: const Icon(Icons.add, size: 18, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }

  Widget _greenBtn(String t, VoidCallback? f, {Color c = const Color(0xFF16A34A)}) => Opacity(
        opacity: f == null ? .55 : 1,
        child: GestureDetector(onTap: f, child: Container(height: 56, alignment: Alignment.center, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: c.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))]), child: Text(t, style: HF.hi(16.5, color: Colors.white, w: FontWeight.w800)))),
      );

  String _text() {
    final r = receipt!, items = (r['items'] as List?) ?? [];
    final b = StringBuffer('🧾 ${widget.me['shop_name']}\nबिल: ${billNo(r['bill_no'])} • ${hm(DateTime.now())}\n\n');
    for (final i in items) { b.writeln('${i['name_hi'] ?? i['name']} × ${i['qty']} = ${rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num))}'); }
    if (((r['discount'] ?? 0) as num) > 0) b.writeln('छूट: −${rupee((r['discount'] ?? 0) as num)}');
    b.writeln('\nकुल: ${rupee((r['total'] ?? 0) as num)} (${pay == 'cash' ? 'कैश' : (pay == 'upi' ? 'UPI' : 'उधार')})');
    b.writeln('\nधन्यवाद 🙏 घर बैठे मँगाने के लिए: ${shopLink(widget.me['id'])}');
    return b.toString();
  }

  Receipt _slip() {
    final r = receipt!, items = (r['items'] as List?)?.whereType<Map>().toList() ?? [];
    return Receipt(
      shop: '${widget.me['shop_name']}', billNo: billNo(r['bill_no']), at: DateTime.now(),
      items: [for (final i in items) ('${i['name_hi'] ?? i['name']}', (i['price'] ?? 0) as num, (i['qty'] ?? 0) as num)],
      subtotal: (r['subtotal'] ?? r['total'] ?? 0) as num, discount: (r['discount'] ?? 0) as num, total: (r['total'] ?? 0) as num,
      payLabel: pay == 'cash' ? 'कैश' : (pay == 'upi' ? 'UPI' : 'उधार'), customer: name.text.trim(), phone: phone.text.trim(),
    );
  }

  Future<void> _quick() async {
    final e = await Printer.quickPrint(_slip());
    if (!mounted) return;
    if (e == null) { hfToast(context, 'प्रिंट हो गया 🖨️'); } else { showPrinter(context, _slip()); }
  }

  Widget _receipt() {
    final r = receipt!, items = (r['items'] as List?)?.whereType<Map>().toList() ?? [];
    final now = DateTime.now();
    final payL = pay == 'cash' ? '💵 कैश' : (pay == 'upi' ? '📱 UPI' : '📒 उधार');
    return ListView(controller: widget.ctl, padding: const EdgeInsets.only(bottom: 30), children: [
      sheetHead(context, '✅ बिल बन गया', sub: 'स्टॉक अपने-आप घट गया'),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.gold.withValues(alpha: .5), width: 1.2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.me['shop_name']}', textAlign: TextAlign.center, style: HF.num(19, w: FontWeight.w800)),
          Text('Happy Food पार्टनर', textAlign: TextAlign.center, style: HF.hi(12, color: HF.mut)),
          const SizedBox(height: 12),
          Row(children: [Text('बिल: ${billNo(r['bill_no'])}', style: HF.hi(12.5, w: FontWeight.w700)), const Spacer(), Text('${now.day}/${now.month}/${now.year}, ${hm(now)}', style: HF.hi(12, color: HF.mut))]),
          if (name.text.trim().isNotEmpty || phone.text.trim().isNotEmpty) Text('ग्राहक: ${name.text.trim()} ${phone.text.trim()}', style: HF.hi(12, color: HF.mut)),
          const Divider(height: 20),
          for (final i in items)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${i['name_hi'] ?? i['name']}', style: HF.hi(14, w: FontWeight.w700)), Text('${rupee((i['price'] ?? 0) as num)} × ${i['qty']}', style: HF.hi(11.5, color: HF.mut))])),
              Text(rupee(((i['price'] ?? 0) as num) * ((i['qty'] ?? 0) as num)), style: HF.num(14, w: FontWeight.w700)),
            ])),
          const Divider(height: 16),
          Row(children: [Text('जोड़', style: HF.hi(13.5)), const Spacer(), Text(rupee((r['subtotal'] ?? r['total'] ?? 0) as num), style: HF.num(14, w: FontWeight.w700))]),
          if (((r['discount'] ?? 0) as num) > 0) Row(children: [Text('छूट', style: HF.hi(13.5)), const Spacer(), Text('−${rupee((r['discount'] ?? 0) as num)}', style: HF.num(14, color: HF.bad, w: FontWeight.w700))]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('कुल', style: HF.hi(15, w: FontWeight.w800)), const Spacer(), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(rupee((r['total'] ?? 0) as num), style: HF.num(26)), Text(payL, style: HF.hi(12, color: const Color(0xFF166534), w: FontWeight.w800))])]),
          const SizedBox(height: 12),
          Text('धन्यवाद 🙏 घर बैठे मँगाने के लिए Happy Food ऐप', textAlign: TextAlign.center, style: HF.hi(11.5, color: HF.mut)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(child: pillBtn('WhatsApp', const Color(0xFF16A34A), Colors.white, Icons.chat, () => whatsApp(context, _text(), phone: phone.text))),
          const SizedBox(width: 10),
          Expanded(child: pillBtn('शेयर', HF.card, HF.tx, Icons.share, () => shareText(_text()))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          Expanded(child: _greenBtn('🖨️ प्रिंट करें', _quick, c: const Color(0xFF16120B))),
          const SizedBox(width: 10),
          GestureDetector(onTap: () => showPrinter(context, _slip()), child: Container(width: 56, height: 56, decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: HF.line)), child: const Icon(Icons.settings))),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _greenBtn('＋ नया बिल', () { widget.bill.clear(); Navigator.pop(context, true); })),
    ]);
  }
}
