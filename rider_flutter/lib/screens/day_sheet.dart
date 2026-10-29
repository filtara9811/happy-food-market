import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../data/demo.dart';
import '../widgets/common.dart';
import 'sheets.dart';

/// Numbers for one day. Today/last 6 days come from Demo.days; older days are a steady pseudo-random demo.
class DayStat {
  final DateTime d;
  final int earn, delivered, cancelled, skipped, cash, tips, km, minsOnline, sales;
  final double rating;
  const DayStat(this.d, this.earn, this.delivered, this.cancelled, this.skipped, this.cash, this.tips, this.km, this.minsOnline, this.sales, this.rating);

  static DayStat of(DateTime day) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day), d0 = DateTime(day.year, day.month, day.day);
    final back = t0.difference(d0).inDays;
    if (back < 0) return DayStat(d0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0);
    var seed = d0.year * 400 + d0.month * 31 + d0.day;
    int rnd(int n) {
      seed = (seed * 9301 + 49297) % 233280;
      return (seed * n) ~/ 233280;
    }

    final off = d0.weekday == DateTime.sunday && back > 0 && rnd(3) == 0; // some Sundays off
    final del = back < Demo.days.length ? Demo.days[back][1] : (off ? 0 : 2 + rnd(9));
    final earn = back < Demo.days.length ? Demo.days[back][0] : del * (22 + rnd(12));
    return DayStat(d0, earn, del, del == 0 ? 0 : rnd(2), rnd(3), del * (90 + rnd(80)), del == 0 ? 0 : rnd(4) * 10, del * (2 + rnd(3)), del == 0 ? 0 : 180 + rnd(300), back == 0 ? 367 : (del == 0 ? 0 : rnd(3) * 120), del == 0 ? 0.0 : 4.5 + rnd(5) / 10);
  }
}

const _wk = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
const _mo = ['जनवरी', 'फ़रवरी', 'मार्च', 'अप्रैल', 'मई', 'जून', 'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'];
String dayName(DateTime d) {
  final t = DateTime.now();
  if (d.year == t.year && d.month == t.month && d.day == t.day) return 'आज';
  return '${_wk[d.weekday - 1]}, ${d.day} ${_mo[d.month - 1]}';
}

Widget _tile(String ic, String l, String v, {Color c = HF.tx}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$ic $l', style: HF.hi(11.5, color: HF.mut, w: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(v, style: HF.num(20, color: c)),
      ]),
    );

/// Tap a day in the strip → everything about that day.
void showDaySheet(BuildContext context, DateTime day) {
  HapticFeedback.selectionClick();
  final s = DayStat.of(day);
  final isToday = dayName(day) == 'आज';
  hfSheet(context, title: '📅 ${dayName(day)}', body: (ctx, _) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [HF.heroTop, HF.heroBottom]), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('इस दिन की कमाई', style: HF.hi(12, color: Colors.white60)), Text(rupee(s.earn), style: HF.num(34, color: Colors.white))])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('⭐ ${s.rating.toStringAsFixed(1)}', style: HF.num(18, color: HF.gold)), Text('${(s.minsOnline / 60).toStringAsFixed(1)} घंटे ऑनलाइन', style: HF.hi(11, color: Colors.white60))]),
        ]),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
        children: [
          _tile('🏠', 'डिलीवर हुए', '${s.delivered}', c: HF.ok),
          _tile('❌', 'कैंसिल', '${s.cancelled}', c: s.cancelled > 0 ? HF.bad : HF.tx),
          _tile('⏭️', 'छोड़ी रिक्वेस्ट', '${s.skipped}'),
          _tile('🧾', 'काउंटर बिक्री', rupee(s.sales)),
          _tile('💵', 'कैश लिया', rupee(s.cash)),
          _tile('🎁', 'टिप', rupee(s.tips)),
          _tile('🛣️', 'दूरी', '${s.km} km'),
          _tile('⏱️', 'औसत डिलीवरी', s.delivered == 0 ? '—' : '${8 + s.delivered % 7} मिनट'),
        ],
      ),
      if (isToday) ...[
        const SizedBox(height: 14),
        Text('इस दिन की डिलीवरी', style: HF.hi(15, w: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final j in Demo.jobs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(j.items.first.emoji, style: const TextStyle(fontSize: 24)),
            title: Text(j.customer, style: HF.hi(14, w: FontWeight.w800)),
            subtitle: Text('${hm(j.at)} • ${j.items.map((i) => '${i.qty}× ${i.name}').join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(11.5, color: HF.mut)),
            trailing: Text(rupee(j.earn > 0 ? j.earn : j.total), style: HF.num(15, color: HF.goldDeep)),
            onTap: () => showJourney(context, j),
          ),
      ],
      const SizedBox(height: 14),
      GoldButton('📆 पूरा कैलेंडर — हफ़्ता / महीना / साल', onTap: () {
        Navigator.pop(ctx);
        showCalendar(context);
      }),
    ]);
  });
}

/// Full calendar: week / month / year summaries.
void showCalendar(BuildContext context) {
  var mode = 'month';
  var month = DateTime(DateTime.now().year, DateTime.now().month);
  hfSheet(context, title: '📆 कमाई का कैलेंडर', body: (ctx, setS) {
    final now = DateTime.now();
    List<DayStat> range;
    String label;
    if (mode == 'week') {
      final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      range = [for (var i = 0; i < 7; i++) DayStat.of(start.add(Duration(days: i)))];
      label = 'यह हफ़्ता';
    } else if (mode == 'month') {
      final days = DateUtils.getDaysInMonth(month.year, month.month);
      range = [for (var i = 1; i <= days; i++) DayStat.of(DateTime(month.year, month.month, i))];
      label = '${_mo[month.month - 1]} ${month.year}';
    } else {
      range = [for (var m = 1; m <= 12; m++) for (var d = 1; d <= DateUtils.getDaysInMonth(now.year, m); d++) DayStat.of(DateTime(now.year, m, d))];
      label = 'साल ${now.year}';
    }
    final earn = range.fold<int>(0, (a, s) => a + s.earn), del = range.fold<int>(0, (a, s) => a + s.delivered), can = range.fold<int>(0, (a, s) => a + s.cancelled), work = range.where((s) => s.delivered > 0).length;
    final maxE = range.fold<int>(1, (a, s) => s.earn > a ? s.earn : a);
    Widget seg(String id, String l) => Expanded(
          child: GestureDetector(
            onTap: () => setS(() => mode = id),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: mode == id ? HF.ink : Colors.transparent, borderRadius: BorderRadius.circular(14)),
              child: Text(l, style: HF.hi(13.5, color: mode == id ? Colors.white : HF.tx, w: FontWeight.w800)),
            ),
          ),
        );
    Widget chart;
    if (mode == 'month') {
      final first = DateTime(month.year, month.month, 1).weekday - 1;
      chart = Column(children: [
        Row(children: [
          IconButton(onPressed: () => setS(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Center(child: Text(label, style: HF.hi(16, w: FontWeight.w800)))),
          IconButton(onPressed: DateTime(month.year, month.month + 1).isAfter(now) ? null : () => setS(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: [for (final w in _wk) Expanded(child: Center(child: Text(w, style: HF.hi(11, color: HF.mut, w: FontWeight.w800))))]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: .78,
          children: [
            for (var i = 0; i < first; i++) const SizedBox(),
            for (final s in range)
              GestureDetector(
                onTap: s.d.isAfter(now) ? null : () {
                  Navigator.pop(ctx);
                  showDaySheet(context, s.d);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: s.earn == 0 ? HF.card2 : Color.lerp(const Color(0xFFFFF4D6), const Color(0xFFE2A92C), s.earn / maxE),
                    borderRadius: BorderRadius.circular(10),
                    border: dayName(s.d) == 'आज' ? Border.all(color: HF.ink, width: 2) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${s.d.day}', style: HF.num(13, color: s.d.isAfter(now) ? HF.mut : HF.tx)),
                    if (s.earn > 0) Text('₹${s.earn}', style: HF.num(9.5, color: HF.ink, w: FontWeight.w700)),
                  ]),
                ),
              ),
          ],
        ),
      ]);
    } else {
      final bars = mode == 'week'
          ? [for (var i = 0; i < 7; i++) (_wk[i], range[i].earn)]
          : [for (var m = 1; m <= 12; m++) (_mo[m - 1].substring(0, 3), range.where((s) => s.d.month == m).fold<int>(0, (a, s) => a + s.earn))];
      final mx = bars.fold<int>(1, (a, b) => b.$2 > a ? b.$2 : a);
      chart = SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final b in bars)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (b.$2 > 0) FittedBox(child: Text(b.$2 >= 1000 ? '${(b.$2 / 1000).toStringAsFixed(1)}k' : '${b.$2}', style: HF.num(10, color: HF.mut, w: FontWeight.w700))),
                const SizedBox(height: 3),
                Container(height: 120 * b.$2 / mx + 2, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 4),
                FittedBox(child: Text(b.$1, style: HF.hi(10, color: HF.mut))),
              ]),
            ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)), child: Row(children: [seg('week', 'हफ़्ता'), seg('month', 'महीना'), seg('year', 'साल')])),
      const SizedBox(height: 12),
      Text(mode == 'month' ? 'कुल — $label' : label, style: HF.hi(13, color: HF.mut, w: FontWeight.w700)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _tile('💰', 'कमाई', rupee(earn), c: HF.goldDeep)),
        const SizedBox(width: 8),
        Expanded(child: _tile('🏠', 'डिलीवरी', '$del', c: HF.ok)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _tile('❌', 'कैंसिल', '$can')),
        const SizedBox(width: 8),
        Expanded(child: _tile('📅', 'काम के दिन', '$work')),
      ]),
      const SizedBox(height: 14),
      HFCard(padding: const EdgeInsets.all(12), child: chart),
      const SizedBox(height: 8),
      Text(mode == 'month' ? 'किसी भी दिन पर टैप करें — उस दिन का पूरा हिसाब खुलेगा' : 'औसत: ${rupee(work == 0 ? 0 : earn / work)} प्रति काम का दिन', textAlign: TextAlign.center, style: HF.hi(11.5, color: HF.mut)),
    ]);
  });
}
