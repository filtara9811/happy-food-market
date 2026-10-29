import 'package:flutter/material.dart';
import '../theme.dart';
import '../data/demo.dart';
import '../widgets/common.dart';
import 'sheets.dart';

class _Back extends StatelessWidget {
  final String title;
  const _Back(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 10, 16, 14),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(width: 38, height: 38, decoration: BoxDecoration(color: HF.card, shape: BoxShape.circle, border: Border.all(color: HF.line)), child: const Icon(Icons.arrow_back, size: 18)),
          ),
          const SizedBox(width: 10),
          Text(title, style: HF.num(20)),
        ]),
      );
}

/// 💰 Earnings & cash — weekly bars, cash in hand with deposit.
class EarnPage extends StatefulWidget {
  const EarnPage({super.key});
  @override
  State<EarnPage> createState() => _EarnPageState();
}

class _EarnPageState extends State<EarnPage> {
  @override
  Widget build(BuildContext context) {
    final r = Demo.rider;
    const vals = [225, 300, 200, 350, 275, 400, 150];
    const days = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'आज'];
    final mx = vals.reduce((a, b) => a > b ? a : b);
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        const _Back('कमाई व हिसाब'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            HFCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('कुल कमाई', style: HF.hi(12, color: HF.mut)),
              Text(rupee(5120), style: HF.num(34, color: HF.goldDeep)),
              Text('${r.trips} डिलीवरी • ⭐ ${r.rating}', style: HF.hi(12.5, color: HF.mut)),
            ])),
            const SizedBox(height: 16),
            Text('इस हफ़्ते', style: HF.hi(16, w: FontWeight.w800)),
            const SizedBox(height: 8),
            HFCard(
              child: SizedBox(
                height: 150,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < vals.length; i++)
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('${vals[i]}', style: HF.num(10, color: HF.mut, w: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Container(
                          height: 100 * vals[i] / mx,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(gradient: i == vals.length - 1 ? HF.goldGrad : null, color: i == vals.length - 1 ? null : const Color(0xFFEFE4CC), borderRadius: BorderRadius.circular(6)),
                        ),
                        const SizedBox(height: 4),
                        Text(days[i], style: HF.hi(10.5, color: HF.mut)),
                      ]),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text('कैश हिसाब', style: HF.hi(16, w: FontWeight.w800)),
            const SizedBox(height: 8),
            HFCard(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('कैश हाथ में', style: HF.hi(13, w: FontWeight.w800)), Text(rupee(r.cash), style: HF.num(24)), Text('COD का पैसा कंपनी में जमा करना है', style: HF.hi(11.5, color: HF.mut))])),
                SizedBox(
                  width: 110,
                  child: GoldButton('जमा करें', height: 44, onTap: r.cash == 0
                      ? null
                      : () => setState(() {
                            r.cash = 0;
                            hfToast(context, 'कैश जमा हो गया ✅');
                          })),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            GoldButton('⬇️ पैसे निकालें', onTap: () => showWithdraw(context)),
            const SizedBox(height: 30),
          ]),
        ),
      ]),
    );
  }
}

/// 👤 Profile
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final r = Demo.rider;
    Widget tile(String l, String v) => Expanded(
          child: HFCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: HF.hi(11.5, color: HF.mut)), Text(v, style: HF.hi(15, w: FontWeight.w800))])),
        );
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        const _Back('मेरी प्रोफ़ाइल'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            HFCard(
              child: Row(children: [
                Container(width: 58, height: 58, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)])), child: Text(r.initials, style: HF.num(20, color: HF.ink))),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.name, style: HF.num(19)), Text(r.phone, style: HF.hi(12.5, color: HF.mut))]),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [tile('बाइक', r.bike), const SizedBox(width: 10), tile('रेटिंग', '⭐ ${r.rating}')]),
            const SizedBox(height: 10),
            Row(children: [tile('कुल ट्रिप', '${r.trips}'), const SizedBox(width: 10), tile('जुड़े', '03 Aug 2026')]),
            const SizedBox(height: 10),
            HFCard(
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('ऑनलाइन', style: HF.hi(14, w: FontWeight.w800)), Text('बंद करने पर रिक्वेस्ट नहीं मिलेंगी', style: HF.hi(11.5, color: HF.mut))])),
                Toggle(r.online, (v) => setState(() => r.online = v)),
              ]),
            ),
            const SizedBox(height: 30),
          ]),
        ),
      ]),
    );
  }
}
