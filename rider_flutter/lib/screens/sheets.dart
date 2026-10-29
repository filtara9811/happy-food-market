import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../data/models.dart';
import '../data/demo.dart';
import '../widgets/common.dart';
import 'home.dart';
import 'pages.dart';

/// Bottom sheet with a round "source" badge sitting on its top edge (📱 app / 🏪 shop / 🧾 POS / 📦 wholesale).
Future<T?> hfSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext, StateSetter) body, (String, String, Color)? badge}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 40),
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .86),
            decoration: const BoxDecoration(color: HF.card, borderRadius: BorderRadius.vertical(top: Radius.circular(28)), border: Border(top: BorderSide(color: HF.gold))),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 6),
                child: Row(children: [
                  Expanded(child: Text(title, style: HF.hi(19, w: FontWeight.w800))),
                  IconButton.filledTonal(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
              ),
              Flexible(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 6, 20, 20 + MediaQuery.of(ctx).padding.bottom), child: body(ctx, setS))),
            ]),
          ),
          if (badge != null)
            Positioned(
              top: -34,
              left: 0,
              right: 0,
              child: Center(
                child: Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: HF.card, shape: BoxShape.circle, border: Border.all(color: badge.$3, width: 3), boxShadow: [BoxShadow(color: badge.$3.withOpacity(.4), blurRadius: 18, offset: const Offset(0, 8))]),
                    child: Text(badge.$1, style: const TextStyle(fontSize: 30)),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -9),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2), decoration: BoxDecoration(color: badge.$3, borderRadius: BorderRadius.circular(99)), child: Text(badge.$2, style: HF.hi(10.5, color: Colors.white, w: FontWeight.w800))),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    ),
  );
}

(String, String, Color) sourceOf(Kind k) => switch (k) {
      Kind.counter => ('🧾', 'POS बिक्री', const Color(0xFF7C3AED)),
      Kind.stock => ('📱', 'ऐप ऑर्डर', const Color(0xFF16A34A)),
      Kind.vendor => ('🏪', 'दुकान ऑर्डर', const Color(0xFFD97706)),
      Kind.restock => ('📦', 'थोक ख़रीद', const Color(0xFF2563EB)),
    };

/// "पूरी जर्नी" — every step of an order with time.
void showJourney(BuildContext context, Job j) {
  HapticFeedback.selectionClick();
  final k = JobCard.kind(j.kind);
  final mins = j.steps.last.at.difference(j.at).inMinutes;
  hfSheet(context, title: 'पूरी जर्नी', badge: sourceOf(j.kind), body: (ctx, _) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        EmojiDisc(j.items.first.emoji, size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Pill(k.$1, bg: k.$2, fg: k.$3),
            Text(j.customer, style: HF.num(19)),
            Text('${hm(j.at)} • ${j.pay}', style: HF.hi(12, color: HF.mut, w: FontWeight.w500)),
          ]),
        ),
        Text(rupee(j.total), style: HF.num(22, color: HF.goldDeep)),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          for (final i in j.items)
            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Expanded(child: Text('${i.qty}× ${i.name}', style: HF.hi(13.5, w: FontWeight.w700))), Text(rupee(i.qty * i.price), style: HF.num(14))])),
        ]),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < j.steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 40,
              child: Column(children: [
                Container(width: 38, height: 38, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: HF.card, border: Border.all(color: const Color(0xFF22C55E), width: 2)), child: Text(j.steps[i].icon, style: const TextStyle(fontSize: 17))),
                if (i < j.steps.length - 1) Expanded(child: Container(width: 3, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF22C55E), HF.gold])))),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(j.steps[i].title, style: HF.hi(14, w: FontWeight.w800)),
                  if (j.steps[i].detail.isNotEmpty) Text(j.steps[i].detail, style: HF.hi(12, color: HF.mut, w: FontWeight.w500)),
                ]),
              ),
            ),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(hm(j.steps[i].at), style: HF.hi(11.5, color: HF.mut, w: FontWeight.w800))),
          ]),
        ),
      if (j.rating != null)
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF6DD), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x66E2B04A))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('⭐' * j.rating!, style: const TextStyle(fontSize: 16)), const SizedBox(height: 4), Text('“${j.review}”', style: HF.hi(13.5, w: FontWeight.w700))]),
        ),
      const SizedBox(height: 12),
      Row(children: [
        if (j.kind != Kind.counter) _sum('आपकी कमाई', rupee(j.earn), HF.goldDeep),
        _sum(j.kind == Kind.counter ? 'समय लगा' : 'कुल समय', '$mins मिनट', HF.tx),
        _sum(j.pay == 'कैश' ? 'कैश लिया' : (j.kind == Kind.counter ? 'ग्राहक से मिले' : 'ऑनलाइन पेमेंट'), rupee(j.total), HF.tx),
      ]),
    ]);
  });
}

Widget _sum(String l, String v, Color c) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [Text(l, style: HF.hi(10.5, color: HF.mut)), Text(v, style: HF.num(17, color: c))]),
      ),
    );

/// 🧾 Quick counter sale from the bike stock.
void showQuickSale(BuildContext context, {required VoidCallback onDone}) {
  final pick = <StockLine, int>{};
  String pay = 'cash';
  String? doneNo;
  int doneTot = 0;
  hfSheet(context, title: '🧾 तुरंत बेचें', badge: sourceOf(Kind.counter), body: (ctx, setS) {
    if (doneNo != null) {
      return Column(children: [
        const Text('✅', style: TextStyle(fontSize: 52)),
        Text('बिल बन गया • ${rupee(doneTot)}', style: HF.num(21)),
        Text('$doneNo • ${pay == 'upi' ? 'UPI' : 'कैश'} • स्टॉक अपने-आप घटा', style: HF.hi(12.5, color: HF.mut)),
        const SizedBox(height: 16),
        GoldButton('ठीक है', onTap: () => Navigator.pop(ctx)),
      ]);
    }
    final tot = pick.entries.fold<int>(0, (s, e) => s + e.key.price * e.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('ग्राहक बाइक पर खड़ा है? टोकरी से सामान चुनिए, बिल बनाइए, पैसे लीजिए।', style: HF.hi(12.5, color: HF.mut, w: FontWeight.w500)),
      const SizedBox(height: 10),
      for (final s in Demo.stock.where((x) => x.qty > 0))
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: (pick[s] ?? 0) > 0 ? HF.goldDeep : HF.line, width: 1.5)),
          child: Row(children: [
            EmojiDisc(s.emoji, size: 44),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.name, style: HF.hi(14, w: FontWeight.w800)), Text('${rupee(s.price)} · ${s.qty} बचे', style: HF.hi(11.5, color: HF.mut))])),
            _stepper(pick[s] ?? 0, (d) => setS(() {
                  final q = ((pick[s] ?? 0) + d).clamp(0, s.qty);
                  if (q == 0) {
                    pick.remove(s);
                  } else {
                    pick[s] = q;
                  }
                  HapticFeedback.selectionClick();
                })),
          ]),
        ),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'cash', label: Text('💵 कैश')), ButtonSegment(value: 'upi', label: Text('📱 UPI'))],
        selected: {pay},
        onSelectionChanged: (v) => setS(() => pay = v.first),
      ),
      const SizedBox(height: 12),
      GoldButton('बिल बनाएँ • ${rupee(tot)}', icon: Icons.receipt_long, onTap: tot == 0
          ? null
          : () => setS(() {
                for (final e in pick.entries) {
                  e.key.qty -= e.value;
                }
                if (pay == 'cash') Demo.rider.cash += tot;
                doneTot = tot;
                doneNo = 'HFR-${(DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
                HapticFeedback.heavyImpact();
                onDone();
              })),
    ]);
  });
}

Widget _stepper(int q, void Function(int) d) => Container(
      decoration: BoxDecoration(color: q > 0 ? HF.goldDeep : HF.card2, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => d(-1), icon: Icon(Icons.remove, color: q > 0 ? HF.ink : HF.goldDeep)),
        Text('$q', style: HF.num(16, color: q > 0 ? HF.ink : HF.tx)),
        IconButton(visualDensity: VisualDensity.compact, onPressed: () => d(1), icon: Icon(Icons.add, color: q > 0 ? HF.ink : HF.goldDeep)),
      ]),
    );

/// Centre "मेन्यू" sheet — same 8 tiles as the prototype.
void showMenuSheet(BuildContext context, {required void Function(String) onPick}) {
  HapticFeedback.mediumImpact();
  final r = Demo.rider;
  final tiles = <(String, String, String, Color, String)>[
    ('📦', 'मेरा स्टॉक', 'टोकरी में क्या है', const Color(0xFFDBEAFE), 'stock'),
    ('🏪', 'वेंडर से माल', 'थोक में ख़रीदें', const Color(0xFFFEF3C7), 'wm'),
    ('💵', 'कैश जमा', '${rupee(r.cash)} हाथ में', const Color(0xFFDCFCE7), 'earn'),
    ('💰', 'कमाई व हिसाब', 'हफ़्ते का ग्राफ़', const Color(0xFFFFEDD5), 'earn'),
    ('⬇️', 'पैसे निकालें', 'UPI / बैंक में', const Color(0xFFEDE9FE), 'wd'),
    (r.online ? '🔴' : '🟢', r.online ? 'ड्यूटी बंद' : 'ड्यूटी शुरू', 'रिक्वेस्ट चालू/बंद', const Color(0xFFFEE2E2), 'duty'),
    ('🎧', 'मदद', 'WhatsApp सपोर्ट', const Color(0xFFE0F2FE), 'help'),
    ('🔄', 'रोल बदलें', 'ग्राहक / दुकान', const Color(0xFFF5F5F4), 'role'),
  ];
  hfSheet(context, title: 'मेन्यू', body: (ctx, _) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (final t in tiles)
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              switch (t.$5) {
                case 'earn':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EarnPage()));
                case 'wd':
                  showWithdraw(context);
                case 'duty':
                  r.online = !r.online;
                  hfToast(context, r.online ? 'आप ऑनलाइन हैं 🟢' : 'आप ऑफ़लाइन हैं');
                case 'wm':
                  hfToast(context, 'दुकान से थोक माल — अगले चरण में');
                case 'help':
                  hfToast(context, 'WhatsApp सपोर्ट खुलेगा');
                case 'role':
                  hfToast(context, 'रोल बदलना — लॉगिन के साथ आएगा');
              }
              onPick(t.$5);
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Color.lerp(t.$4, HF.card, .45), borderRadius: BorderRadius.circular(18), border: Border.all(color: HF.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(t.$1, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 6),
                Text(t.$2, style: HF.hi(14.5, w: FontWeight.w800)),
                Text(t.$3, style: HF.hi(11, color: HF.mut, w: FontWeight.w600)),
              ]),
            ),
          ),
      ],
    );
  });
}

/// ⬇️ Withdraw sheet (UPI / bank) — amount from this week's earnings.
void showWithdraw(BuildContext context) {
  final ctl = TextEditingController();
  const bal = 400;
  hfSheet(context, title: 'पैसे निकालें', body: (ctx, setS) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [HF.heroTop, HF.heroBottom]), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('निकाल सकते हैं', style: HF.hi(12, color: Colors.white60)), Text(rupee(bal), style: HF.num(36, color: Colors.white))]),
      ),
      const SizedBox(height: 14),
      TextField(controller: ctl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'कितने रुपये', prefixText: '₹ ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [for (final v in [100, 200, bal]) ActionChip(label: Text(rupee(v)), onPressed: () => setS(() => ctl.text = '$v'))]),
      const SizedBox(height: 14),
      GoldButton('UPI में भेजें', icon: Icons.send, onTap: () {
        Navigator.pop(ctx);
        hfToast(context, 'निकालने की रिक्वेस्ट गई ✅ — 24 घंटे में खाते में');
      }),
    ]);
  });
}

/// 🔔 New request popup — rings 3 times, 30-second timer, accept / skip.
/// (In the live app this also opens over the lock screen through the Firebase high-priority message.)
void showRequest(BuildContext context, {required VoidCallback onDone}) {
  var left = 30;
  Timer? t;
  var rang = 0;
  Timer.periodic(const Duration(milliseconds: 900), (tm) {
    if (rang >= 3) {
      tm.cancel();
      return;
    }
    rang++;
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  });
  hfSheet(context, title: '🔔 नई रिक्वेस्ट!', badge: sourceOf(Kind.stock), body: (ctx, setS) {
    t ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ctx.mounted) {
        t?.cancel();
        return;
      }
      setS(() => left--);
      if (left <= 0) {
        t?.cancel();
        Navigator.pop(ctx);
      }
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('नया डिलीवरी ऑर्डर • #HF-8570', style: HF.hi(12.5, color: HF.mut))),
        Pill('⏱ ${left}s', bg: HF.goldLight, fg: HF.ink),
      ]),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: left / 30, minHeight: 5, color: HF.gold, backgroundColor: HF.card2)),
      const SizedBox(height: 12),
      Row(children: [const EmojiDisc('🥟', size: 50), const SizedBox(width: 12), Expanded(child: Text('स्टीम मोमोज़ × 1', style: HF.hi(15, w: FontWeight.w800)))]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('डिलीवरी चार्ज (आपकी कमाई)', style: HF.hi(13, w: FontWeight.w800)), Text('बेस ₹20 + दूरी 3.1 km × ₹6 = ₹19', style: HF.hi(11.5, color: HF.mut))])),
          Text('₹39', style: HF.num(28, color: HF.goldDeep)),
        ]),
      ),
      const SizedBox(height: 10),
      Text('📦 आपके स्टॉक से • 📍 Rahul Sharma, 3.1 km • 💵 कैश वसूलना है: ₹124', style: HF.hi(12.5, w: FontWeight.w600)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: HF.bad, side: const BorderSide(color: Color(0x66DC2626)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () {
              t?.cancel();
              Navigator.pop(ctx);
              hfToast(context, 'रिक्वेस्ट छोड़ी — अगले राइडर को गई');
            },
            child: Text('छोड़ें', style: HF.hi(15, color: HF.bad, w: FontWeight.w800)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GoldButton('✓ स्वीकार करें', onTap: () {
            t?.cancel();
            Navigator.pop(ctx);
            HapticFeedback.heavyImpact();
            hfToast(context, 'स्वीकार ✅ — ग्राहक की ओर चलिए 🛵');
            onDone();
          }),
        ),
      ]),
    ]);
  }).whenComplete(() => t?.cancel());
}
