import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../data/models.dart';
import '../data/demo.dart';
import '../widgets/common.dart';
import 'sheets.dart';
import 'pages.dart';

/// Rider home — same layout as the prototype's partner screen:
/// dark hero with earnings card, waiting card, day strip, Deliveries / My stock tabs, order cards.
class RiderHome extends StatefulWidget {
  const RiderHome({super.key});
  @override
  State<RiderHome> createState() => _RiderHomeState();
}

class _RiderHomeState extends State<RiderHome> {
  final scroll = ScrollController();
  String tab = 'orders';
  String filter = 'all';
  int day = 0;
  bool mini = false;
  Rider get r => Demo.rider;

  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      final m = scroll.offset > 300;
      if (m != mini) setState(() => mini = m);
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  int get todayEarn => Demo.days[0][0];

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBody: true,
        body: Stack(children: [
          RefreshIndicator(
            color: HF.goldDeep,
            onRefresh: () async {
              await Future.delayed(const Duration(milliseconds: 600));
              if (context.mounted) hfToast(context, 'ताज़ा हो गया ✨');
            },
            child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
              _hero(top),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _autoAccept(),
                  const SizedBox(height: 12),
                  _waiting(),
                  const SizedBox(height: 16),
                  _days(),
                  const SizedBox(height: 14),
                  _tabs(),
                  const SizedBox(height: 12),
                  if (tab == 'orders') ..._orders() else ..._stock(),
                ]),
              ),
            ]),
          ),
          // compact header when scrolled, like the prototype's mini bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            top: mini ? 0 : -(top + 90),
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, top + 10, 16, 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [HF.heroTop, HF.heroBottom]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
                boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 18)],
              ),
              child: Row(children: [
                _avatar(40),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('💰 ${rupee(todayEarn)}', style: HF.num(19, color: Colors.white)),
                  Text('आज की कमाई', style: HF.hi(11.5, color: Colors.white60)),
                ]),
              ]),
            ),
          ),
        ]),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _avatar(double s) => Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)]),
          border: Border.all(color: const Color(0xFFFDE68A), width: s > 44 ? 3 : 2),
        ),
        child: Text(r.initials, style: HF.num(s * .34, color: HF.ink)),
      );

  Widget _hero(double top) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [HF.heroTop, HF.heroBottom]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _avatar(56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(20, color: Colors.white)),
              Text('डिलीवरी पार्टनर · ${r.bike}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: Colors.white60, w: FontWeight.w500)),
            ]),
          ),
          GestureDetector(
            onTap: () => setState(() {
              r.online = !r.online;
              hfToast(context, r.online ? 'आप ऑनलाइन हैं 🟢' : 'आप ऑफ़लाइन हैं');
            }),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white24)),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 24,
                  padding: const EdgeInsets.all(3),
                  alignment: r.online ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(color: r.online ? const Color(0xFF22C55E) : Colors.white24, borderRadius: BorderRadius.circular(20)),
                  child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.online ? 'ऑनलाइन' : 'ऑफ़लाइन', style: HF.hi(13, color: Colors.white, w: FontWeight.w800)),
                  Text(r.online ? 'रिक्वेस्ट आ रही हैं' : 'ड्यूटी शुरू करें', style: HF.hi(10, color: Colors.white60, w: FontWeight.w500)),
                ]),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('💰 मेरी कमाई · आज', style: HF.hi(13, color: Colors.white.withOpacity(.85), w: FontWeight.w700))),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EarnPage())),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(.1), borderRadius: BorderRadius.circular(20)), child: Text('हिसाब ›', style: HF.hi(12, color: const Color(0xFF86EFAC), w: FontWeight.w800))),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Text(rupee(todayEarn), style: HF.num(44, color: Colors.white)),
              const SizedBox(width: 8),
              Container(width: 26, height: 26, decoration: BoxDecoration(color: Colors.white.withOpacity(.12), shape: BoxShape.circle), child: const Icon(Icons.chevron_right, color: Colors.white70, size: 18)),
              const Spacer(),
              GestureDetector(
                onTap: () => showWithdraw(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x66E2A92C), blurRadius: 16, offset: Offset(0, 6))]),
                  child: Row(children: [const Icon(Icons.arrow_downward, size: 17, color: HF.ink), const SizedBox(width: 4), Text('निकालें', style: HF.hi(15, color: HF.ink, w: FontWeight.w800))]),
                ),
              ),
            ]),
            Text('${Demo.days[0][1]} डिलीवरी पूरी · टिप समेत', style: HF.hi(12, color: Colors.white60, w: FontWeight.w500)),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white12),
            const SizedBox(height: 10),
            Row(children: [
              _stat('डिलीवरी', '${Demo.days[0][1]}'),
              _sep(),
              _stat('कमाई', rupee(todayEarn)),
              _sep(),
              _stat('कैश हाथ में', rupee(r.cash)),
            ]),
          ]),
        ),
        if (r.cash > 0) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EarnPage())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(.07), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Expanded(child: Text('💵 ${rupee(r.cash)} कैश आपके पास · आज रात तक जमा करें', style: HF.hi(12.5, color: Colors.white, w: FontWeight.w700))),
                Text('देखें ›', style: HF.hi(12.5, color: const Color(0xFF86EFAC), w: FontWeight.w800)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _stat(String l, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: HF.hi(11, color: Colors.white54, w: FontWeight.w500)),
          Text(v, style: HF.num(17, color: Colors.white)),
        ]),
      );
  Widget _sep() => Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 10), color: Colors.white12);

  Widget _autoAccept() => HFCard(
        color: HF.card2,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('⚡ रिक्वेस्ट ऑटो-एक्सेप्ट', style: HF.hi(13.5, w: FontWeight.w800)),
              Text('रिक्वेस्ट आते ही अपने-आप स्वीकार', style: HF.hi(11, color: HF.mut, w: FontWeight.w500)),
            ]),
          ),
          Toggle(r.autoAccept, (v) => setState(() {
                r.autoAccept = v;
                hfToast(context, v ? 'ऑटो-एक्सेप्ट चालू ⚡' : 'ऑटो-एक्सेप्ट बंद');
              })),
        ]),
      );

  Widget _waiting() => HFCard(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(children: [
          Text(r.online ? '📡' : '😴', style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 6),
          Text(r.online ? 'रिक्वेस्ट का इंतज़ार…' : 'आप ऑफ़लाइन हैं', style: HF.hi(15, w: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(r.online ? 'ग्राहक ऑर्डर करते ही यहाँ घंटी बजेगी — ऐप बंद हो तब भी' : 'ड्यूटी शुरू करें, तभी रिक्वेस्ट आएँगी', textAlign: TextAlign.center, style: HF.hi(12.5, color: HF.mut, w: FontWeight.w500)),
          const SizedBox(height: 12),
          TextButton(onPressed: () => showRequest(context, onDone: refresh), child: Text('🔔 डेमो रिक्वेस्ट देखें', style: HF.hi(13, color: HF.goldDeep, w: FontWeight.w800))),
        ]),
      );

  Widget _days() {
    const wk = ['रवि', 'सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि'];
    final now = DateTime.now();
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Demo.days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final d = now.subtract(Duration(days: i)), on = day == i, v = Demo.days[i];
          return GestureDetector(
            onTap: () => setState(() => day = i),
            child: Container(
              width: 76,
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              decoration: BoxDecoration(
                color: on ? HF.ink : HF.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: on ? HF.ink : HF.line),
              ),
              child: Column(children: [
                Text(i == 0 ? 'आज ${d.day}' : '${wk[d.weekday % 7]} ${d.day}', style: HF.hi(12, color: on ? Colors.white : HF.tx, w: FontWeight.w800)),
                Text(rupee(v[0]), style: HF.num(15, color: on ? HF.gold : HF.ok)),
                Text('${v[1]} डिलीवरी', style: HF.hi(10.5, color: on ? Colors.white70 : HF.mut, w: FontWeight.w600)),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: v[0] / 150, minHeight: 3, color: HF.ok, backgroundColor: on ? Colors.white12 : HF.line),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _tabs() {
    final units = Demo.stock.fold<int>(0, (s, x) => s + x.qty);
    Widget t(String id, String label, int n) {
      final on = tab == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => tab = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 46,
            decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(18), boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 10)] : null),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: HF.hi(14, color: on ? HF.tx : HF.mut, w: FontWeight.w800)),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1), decoration: BoxDecoration(color: HF.ok, borderRadius: BorderRadius.circular(10)), child: Text('$n', style: HF.num(12, color: Colors.white))),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: const Color(0xFFE9DFC9), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [t('orders', '🛵 डिलीवरी', Demo.jobs.length), t('stock', '📦 मेरा स्टॉक', units)]),
    );
  }

  List<Widget> _orders() {
    final all = Demo.jobs;
    final list = all.where((j) => filter == 'all' || (filter == 'done' ? j.done : !j.done)).toList();
    Widget f(String id, String l) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(l, style: HF.hi(13, color: filter == id ? Colors.white : HF.tx, w: FontWeight.w800)),
            selected: filter == id,
            showCheckmark: false,
            selectedColor: HF.ink,
            backgroundColor: HF.card,
            shape: StadiumBorder(side: BorderSide(color: filter == id ? HF.ink : HF.line)),
            onSelected: (_) => setState(() => filter = id),
          ),
        );
    return [
      Row(children: [f('all', 'सब'), f('pending', 'चालू'), f('done', 'पूरे'), const Spacer(), Text('${list.length} / ${all.length}', style: HF.num(14, color: HF.mut, w: FontWeight.w700))]),
      const SizedBox(height: 10),
      for (final j in list) Padding(padding: const EdgeInsets.only(bottom: 12), child: JobCard(j, onTap: () => showJourney(context, j))),
    ];
  }

  List<Widget> _stock() {
    final units = Demo.stock.fold<int>(0, (s, x) => s + x.qty), value = Demo.stock.fold<int>(0, (s, x) => s + x.qty * x.price);
    Widget box(String l, String v) => Expanded(
          child: HFCard(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [Text(l, style: HF.hi(11, color: HF.mut)), Text(v, style: HF.num(18))])),
        );
    return [
      Row(children: [box('आइटम', '${Demo.stock.where((s) => s.qty > 0).length}'), const SizedBox(width: 8), box('कुल नग', '$units'), const SizedBox(width: 8), box('माल की कीमत', rupee(value))]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: GoldButton('तुरंत बेचें', icon: Icons.receipt_long, height: 46, onTap: () => showQuickSale(context, onDone: refresh))),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: const BorderSide(color: HF.line, width: 1.5), backgroundColor: HF.card),
            onPressed: () => hfToast(context, 'दुकान से थोक माल — अगले चरण में'),
            icon: const Icon(Icons.storefront, color: HF.tx, size: 18),
            label: Text('माल भरें', style: HF.hi(14, w: FontWeight.w800)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      for (final s in Demo.stock.where((s) => s.qty > 0))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HFCard(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              EmojiDisc(s.emoji, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: HF.hi(14, w: FontWeight.w800)),
                  Text('${rupee(s.price)} · कीमत ${rupee(s.price * s.qty)}', style: HF.hi(11.5, color: HF.mut, w: FontWeight.w500)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${s.qty}', style: HF.num(22, color: s.qty <= 2 ? HF.bad : HF.goldDeep)),
                Text(s.qty <= 2 ? 'कम बचा' : 'नग', style: HF.hi(10.5, color: HF.mut)),
              ]),
            ]),
          ),
        ),
    ];
  }

  Widget _bottomBar() {
    Widget nb(IconData ic, String l, bool on, VoidCallback tap) => Expanded(
          child: GestureDetector(
            onTap: tap,
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 28, height: 3, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: on ? HF.goldDeep : Colors.transparent, borderRadius: BorderRadius.circular(3))),
              Icon(ic, color: on ? HF.goldDeep : HF.mut, size: 24),
              const SizedBox(height: 3),
              Text(l, style: HF.hi(12, color: on ? HF.goldDeep : HF.mut, w: FontWeight.w800)),
            ]),
          ),
        );
    final bottom = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: 78 + bottom,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Positioned.fill(
          top: 8,
          child: Container(
            padding: EdgeInsets.only(bottom: bottom + 6),
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              nb(Icons.two_wheeler, 'डिलीवरी', true, () => scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut)),
              const Expanded(child: SizedBox()),
              nb(Icons.person, 'प्रोफ़ाइल', false, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()))),
            ]),
          ),
        ),
        Positioned(
          top: -18,
          child: GestureDetector(
            onTap: () => showMenuSheet(context, onPick: (k) {
              if (k == 'stock') {
                setState(() => tab = 'stock');
              }
              refresh();
            }),
            child: Column(children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(gradient: HF.goldGrad, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), boxShadow: const [BoxShadow(color: Color(0x73E2A92C), blurRadius: 18, offset: Offset(0, 8))]),
                child: const Icon(Icons.apps_rounded, color: HF.ink, size: 28),
              ),
              const SizedBox(height: 2),
              Text('मेन्यू', style: HF.hi(12, color: HF.goldDeep, w: FontWeight.w800)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// One order / sale card with the progress line (same as prototype).
class JobCard extends StatelessWidget {
  final Job j;
  final VoidCallback onTap;
  const JobCard(this.j, {super.key, required this.onTap});

  static (String, Color, Color) kind(Kind k) => switch (k) {
        Kind.counter => ('🧾 काउंटर बिक्री', const Color(0xFFEDE9FE), const Color(0xFF5B21B6)),
        Kind.stock => ('⚡ टोकरी से डिलीवरी', const Color(0xFFDCFCE7), const Color(0xFF166534)),
        Kind.vendor => ('🏪 दुकान से डिलीवरी', const Color(0xFFFEF3C7), const Color(0xFF92400E)),
        Kind.restock => ('📦 थोक ख़रीद', const Color(0xFFDBEAFE), const Color(0xFF1E40AF)),
      };

  List<(String, String, bool, bool)> get line => switch (j.kind) {
        Kind.counter => [('ग्राहक', '🛒', true, false), ('बिल', '🧾', true, false), ('पेमेंट', '💳', true, false), ('स्टॉक', '📦', true, false)],
        Kind.stock => j.rating != null
            ? [('रिक्वेस्ट', '🔔', true, false), ('रास्ते में', '🛵', true, false), ('OTP', '🔑', true, false), ('कैश', '💵', true, false), ('रेटिंग', '⭐', true, false)]
            : [('स्वीकार', '✅', true, false), ('टोकरी से', '📦', true, false), ('रास्ते में', '🛵', j.done, !j.done), ('डिलीवर', '🏠', j.done, false), ('कैश', '💵', j.done, false)],
        Kind.vendor => [('दुकान', '🏪', true, false), ('पैक', '📦', true, false), ('पिकअप', '🛍️', true, false), ('डिलीवर', '🏠', j.done, false), ('रेटिंग', '⭐', j.rating != null, false)],
        Kind.restock => [('पेमेंट', '💳', true, false), ('तैयार', '📦', j.done, !j.done), ('पिकअप', '🛵', j.done, false), ('टोकरी में', '🧺', j.done, false)],
      };

  @override
  Widget build(BuildContext context) {
    final k = kind(j.kind);
    final amt = j.kind == Kind.counter ? j.total : j.earn;
    return HFCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EmojiDisc(j.items.first.emoji, check: j.done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(j.customer + (j.example ? ' · उदाहरण' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.num(17)),
              const SizedBox(height: 4),
              Pill(k.$1, bg: k.$2, fg: k.$3),
              const SizedBox(height: 4),
              Text('${j.items.map((i) => '${i.qty}× ${i.name}').join(', ')} • ${hm(j.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(12, color: HF.mut, w: FontWeight.w500)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rupee(amt), style: HF.num(20, color: HF.goldDeep)),
            Text(j.kind == Kind.counter ? 'बिक्री' : 'कमाई', style: HF.hi(10, color: HF.mut, w: FontWeight.w800)),
          ]),
        ]),
        const SizedBox(height: 14),
        StepLine(line),
      ]),
    );
  }
}
