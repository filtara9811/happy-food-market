import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shop_ui.dart';

/// Khata book kept on the phone: customers, credit given (उधार) and money received.
class Khata {
  static const _k = 'hf_khata_v1';
  static Future<List<Map<String, dynamic>>> all() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_k);
      if (s == null) return [];
      return (jsonDecode(s) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(l));
  }

  static num bal(Map c) => ((c['e'] as List?) ?? []).fold<num>(0, (s, x) => s + (x['t'] == 'give' ? (x['a'] as num) : -(x['a'] as num)));

  /// A credit bill from the POS goes straight into the khata.
  static Future<void> addCredit(String name, String phone, num amount, String note) async {
    final l = await all();
    var c = l.firstWhere((x) => (phone.isNotEmpty && x['p'] == phone) || (phone.isEmpty && x['n'] == name), orElse: () => {});
    if (c.isEmpty) {
      c = {'id': 'k${DateTime.now().millisecondsSinceEpoch}', 'n': name.isEmpty ? 'ग्राहक' : name, 'p': phone, 'e': []};
      l.insert(0, c);
    }
    (c['e'] as List).add({'t': 'give', 'a': amount, 'note': note, 'ts': DateTime.now().millisecondsSinceEpoch});
    await save(l);
  }
}

Future<void> showKhata(BuildContext context, {String shopName = ''}) => showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(initialChildSize: .9, maxChildSize: .95, expand: false, builder: (_, sc) => _KhataSheet(sc: sc, shop: shopName)),
    );

class _KhataSheet extends StatefulWidget {
  final ScrollController sc;
  final String shop;
  const _KhataSheet({required this.sc, required this.shop});
  @override
  State<_KhataSheet> createState() => _KhataSheetState();
}

class _KhataSheetState extends State<_KhataSheet> {
  List<Map<String, dynamic>> l = [];
  String cur = '';
  final n = TextEditingController(), p = TextEditingController(), amt = TextEditingController(), note = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final x = await Khata.all(); if (mounted) setState(() => l = x); }

  Future<void> _new() async {
    if (n.text.trim().isEmpty) { hfToast(context, 'नाम लिखिए'); return; }
    final c = {'id': 'k${DateTime.now().millisecondsSinceEpoch}', 'n': n.text.trim(), 'p': p.text.replaceAll(RegExp(r'\D'), ''), 'e': []};
    l.insert(0, c); await Khata.save(l); n.clear(); p.clear();
    setState(() => cur = c['id'] as String);
  }

  Future<void> _add(String t) async {
    final a = num.tryParse(amt.text.trim()) ?? 0;
    if (a <= 0) { hfToast(context, 'रकम लिखिए'); return; }
    final c = l.firstWhere((x) => x['id'] == cur);
    (c['e'] as List).add({'t': t, 'a': a, 'note': note.text.trim(), 'ts': DateTime.now().millisecondsSinceEpoch});
    await Khata.save(l); amt.clear(); note.clear(); HapticFeedback.lightImpact();
    setState(() {});
  }

  Widget _in(TextEditingController c, String h, {TextInputType? k}) => Expanded(child: TextField(controller: c, keyboardType: k, decoration: InputDecoration(hintText: h, filled: true, fillColor: HF.card2, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))));

  Widget _av(String name) => Container(width: 42, height: 42, alignment: Alignment.center, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFCE49D), Color(0xFFB88222)])), child: Text(name.isEmpty ? 'G' : name.characters.first.toUpperCase(), style: HF.num(16, color: HF.ink)));

  @override
  Widget build(BuildContext context) {
    final body = <Widget>[];
    if (cur.isNotEmpty && l.any((x) => x['id'] == cur)) {
      final c = l.firstWhere((x) => x['id'] == cur), b = Khata.bal(c), ent = ((c['e'] as List?) ?? []).reversed.toList();
      body.addAll([
        TextButton.icon(onPressed: () => setState(() => cur = ''), icon: const Icon(Icons.arrow_back, size: 18), label: Text('सभी ग्राहक', style: HF.hi(13, w: FontWeight.w800))),
        Container(
          padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            _av('${c['n']}'), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${c['n']}', style: HF.hi(16, w: FontWeight.w800)), if ('${c['p']}'.isNotEmpty) Text('+91 ${c['p']}', style: HF.hi(12, color: HF.mut))])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(b >= 0 ? 'लेने हैं' : 'देने हैं', style: HF.hi(11, color: HF.mut)), Text(rupee(b.abs()), style: HF.num(19, color: b > 0 ? HF.bad : HF.ok))]),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [_in(amt, '₹ रकम', k: TextInputType.number), const SizedBox(width: 8), _in(note, 'नोट (ज़रूरी नहीं)')]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: () => _add('give'), child: const Text('− उधार दिया'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: () => _add('got'), child: const Text('+ पैसा मिला'))),
        ]),
        if ('${c['p']}'.isNotEmpty && b > 0)
          Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(onPressed: () => whatsApp(context, 'नमस्ते ${c['n']} जी, ${widget.shop} पर आपका ${rupee(b)} बकाया है। सुविधा अनुसार भुगतान कर दें। धन्यवाद 🙏', phone: '91${c['p']}'), icon: const Icon(Icons.chat, color: Color(0xFF128C4A)), label: Text('WhatsApp पर याद दिलाएँ', style: HF.hi(13.5, color: const Color(0xFF128C4A), w: FontWeight.w800)))),
        const SizedBox(height: 12),
        if (ent.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('अभी कोई लेन-देन नहीं', style: HF.hi(13, color: HF.mut)))),
        for (final x in ent)
          Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: HF.line)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x['t'] == 'give' ? 'उधार दिया' : 'पैसा मिला', style: HF.hi(13.5, w: FontWeight.w800)), Text('${hm(DateTime.fromMillisecondsSinceEpoch(x['ts'] as int))} ${x['note'] ?? ''}', style: HF.hi(11, color: HF.mut))])),
              Text('${x['t'] == 'give' ? '−' : '+'}${rupee(x['a'] as num)}', style: HF.num(15, color: x['t'] == 'give' ? HF.bad : HF.ok)),
            ]),
          ),
      ]);
    } else {
      final due = l.fold<num>(0, (s, c) { final b = Khata.bal(c); return s + (b > 0 ? b : 0); });
      body.addAll([
        Row(children: [
          Expanded(flex: 3, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('कुल लेने हैं', style: HF.hi(11, color: Colors.white70)), Text(rupee(due), style: HF.num(24, color: const Color(0xFFF6D68A)))]))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ग्राहक', style: HF.hi(11, color: Colors.white70)), Text('${l.length}', style: HF.num(24, color: const Color(0xFFF6D68A)))]))),
        ]),
        const SizedBox(height: 12),
        Row(children: [_in(n, 'ग्राहक का नाम'), const SizedBox(width: 8), _in(p, 'मोबाइल', k: TextInputType.phone)]),
        const SizedBox(height: 8),
        GoldButton('➕ ग्राहक जोड़ें', onTap: _new),
        const SizedBox(height: 12),
        if (l.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('पहला ग्राहक जोड़ें — या बिल बनाते समय "उधार" चुनें', textAlign: TextAlign.center, style: HF.hi(13, color: HF.mut))),
        for (final c in l)
          GestureDetector(
            onTap: () => setState(() => cur = c['id'] as String),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)),
              child: Row(children: [
                _av('${c['n']}'), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${c['n']}', style: HF.hi(14.5, w: FontWeight.w800)), Text('${((c['e'] as List?) ?? []).length} लेन-देन', style: HF.hi(11.5, color: HF.mut))])),
                Text(rupee(Khata.bal(c).abs()), style: HF.num(16, color: Khata.bal(c) > 0 ? HF.bad : HF.ok)),
              ]),
            ),
          ),
      ]);
    }
    return Container(
      decoration: const BoxDecoration(color: HF.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: ListView(controller: widget.sc, padding: const EdgeInsets.fromLTRB(16, 12, 16, 30), children: [
        Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: HF.line, borderRadius: BorderRadius.circular(9)))),
        const SizedBox(height: 12),
        Row(children: [const Text('📒', style: TextStyle(fontSize: 22)), const SizedBox(width: 8), Text('खाता बुक', style: HF.hi(20, w: FontWeight.w800))]),
        const SizedBox(height: 12),
        ...body,
      ]),
    );
  }
}
