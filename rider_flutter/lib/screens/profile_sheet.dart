import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../theme.dart';
import '../data/demo.dart';
import '../widgets/common.dart';
import '../sound.dart';

/// Profile as a bottom sheet — like the customer app: flip visiting card, referral, KYC, settings.
void showProfileSheet(BuildContext context, {required VoidCallback onChanged}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: .9,
      maxChildSize: .95,
      minChildSize: .5,
      expand: false,
      builder: (ctx, scroll) => _ProfileBody(scroll: scroll, onChanged: onChanged),
    ),
  );
}

class _Doc {
  final String icon, name, note;
  String state; // ok | review | missing
  _Doc(this.icon, this.name, this.note, this.state);
}

final _docs = <_Doc>[
  _Doc('🪪', 'आधार (DigiLocker)', 'XXXX XXXX 4821', 'ok'),
  _Doc('💳', 'PAN कार्ड', 'ABCPK••••K', 'ok'),
  _Doc('🏍️', 'ड्राइविंग लाइसेंस', '2027 तक वैध', 'ok'),
  _Doc('📄', 'गाड़ी के काग़ज़ (RC)', 'DL 3S AB 4821', 'review'),
  _Doc('🏦', 'बैंक / UPI', 'rohit@ybl', 'ok'),
  _Doc('👮', 'पुलिस वेरिफ़िकेशन', 'अभी जमा नहीं', 'missing'),
];

class _ProfileBody extends StatefulWidget {
  final ScrollController scroll;
  final VoidCallback onChanged;
  const _ProfileBody({required this.scroll, required this.onChanged});
  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> with SingleTickerProviderStateMixin {
  late final AnimationController flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  bool sureOut = false;
  @override
  void dispose() {
    flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = Demo.rider;
    final ok = _docs.where((d) => d.state == 'ok').length;
    return Container(
      decoration: const BoxDecoration(color: HF.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: ListView(controller: widget.scroll, padding: EdgeInsets.fromLTRB(16, 10, 16, 30 + MediaQuery.of(context).padding.bottom), children: [
        Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: HF.line, borderRadius: BorderRadius.circular(3)))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('मेरी प्रोफ़ाइल', style: HF.hi(20, w: FontWeight.w800))),
          _round(Text('EN', style: HF.num(12)), () => hfToast(context, 'English जल्द आएगा')),
          const SizedBox(width: 8),
          _round(Icon(sureOut ? Icons.check : Icons.logout, size: 18, color: sureOut ? Colors.white : HF.bad), () {
            if (!sureOut) {
              setState(() => sureOut = true);
              hfToast(context, 'लॉगआउट करने के लिए फिर से दबाएँ');
              Future.delayed(const Duration(seconds: 3), () => mounted ? setState(() => sureOut = false) : null);
            } else {
              Navigator.pop(context);
              hfToast(context, 'लॉगआउट — असली लॉगिन अगले चरण में');
            }
          }, bg: sureOut ? HF.bad : const Color(0x14EF4444), border: const Color(0x59EF4444)),
          const SizedBox(width: 8),
          _round(const Icon(Icons.close, size: 18), () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 14),
        // ---- flip visiting card
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            flip.isCompleted ? flip.reverse() : flip.forward();
          },
          child: AnimatedBuilder(
            animation: flip,
            builder: (_, __) {
              final a = flip.value * math.pi;
              final back = a > math.pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .0012)
                  ..rotateX(a),
                child: back ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateX(math.pi), child: _cardBack()) : _cardFront(),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Center(child: Text('↻ टैप करके पलटें', style: HF.hi(11.5, color: HF.mut))),
        const SizedBox(height: 14),
        // ---- referral
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF4D6), Color(0xFFFDE7B0)]), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x80E2B04A))),
          child: Row(children: [
            const Text('🎁', style: TextStyle(fontSize: 34)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('दोस्त को राइडर बनाओ, ₹200 पाओ', style: HF.hi(15, color: const Color(0xFF7A4A06), w: FontWeight.w800)),
                Text('उसकी 20 डिलीवरी पूरी होते ही • कोड HFR-RK786', style: HF.hi(11.5, color: const Color(0xFF8A6A2A))),
                const SizedBox(height: 4),
                Text('3 दोस्त जुड़े • ₹400 मिले', style: HF.hi(11.5, color: HF.ok, w: FontWeight.w800)),
              ]),
            ),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () => Share.share('Happy Food पर डिलीवरी पार्टनर बनिए और रोज़ कमाइए 🛵\nमेरा कोड: HFR-RK786 — 20 डिलीवरी पर ₹200 बोनस\nऐप: https://github.com/filtara9811/happy-food-market/releases'),
              icon: const Icon(Icons.share, color: Colors.white),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // ---- KYC
        Row(children: [
          Expanded(child: Text('🛡️ KYC और काग़ज़', style: HF.hi(16, w: FontWeight.w800))),
          Pill('$ok/${_docs.length} पूरे', bg: ok == _docs.length ? const Color(0xFFDCFCE7) : HF.goldLight, fg: ok == _docs.length ? HF.ok : HF.ink),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: ok / _docs.length, minHeight: 6, color: HF.ok, backgroundColor: HF.card2)),
        const SizedBox(height: 10),
        HFCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final d in _docs)
              ListTile(
                leading: Text(d.icon, style: const TextStyle(fontSize: 22)),
                title: Text(d.name, style: HF.hi(14, w: FontWeight.w800)),
                subtitle: Text(d.note, style: HF.hi(11.5, color: HF.mut)),
                trailing: d.state == 'ok'
                    ? const Pill('✓ जाँचा', bg: Color(0xFFDCFCE7), fg: HF.ok)
                    : d.state == 'review'
                        ? const Pill('⏳ जाँच में', bg: Color(0xFFFEF3C7), fg: Color(0xFF92400E))
                        : FilledButton.tonal(onPressed: () => _upload(d), child: Text('जमा करें', style: HF.hi(12.5, w: FontWeight.w800))),
                onTap: () => _upload(d),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Text('⚙️ सेटिंग', style: HF.hi(16, w: FontWeight.w800)),
        const SizedBox(height: 8),
        HFCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            _row('🟢', 'ऑनलाइन (ड्यूटी)', 'बंद करने पर रिक्वेस्ट नहीं मिलेंगी', Toggle(r.online, (v) => setState(() {
                  r.online = v;
                  widget.onChanged();
                }))),
            _row('🔔', 'रिक्वेस्ट की घंटी', 'नई रिक्वेस्ट पर 3 बार', Toggle(Sound.on, (v) => setState(() => Sound.on = v))),
            _row('▶️', 'घंटी सुनें', 'आवाज़ जाँचें', IconButton(onPressed: Sound.ring3, icon: const Icon(Icons.volume_up, color: HF.goldDeep))),
            _row('🏍️', 'गाड़ी', r.bike, const Icon(Icons.chevron_right, color: HF.mut)),
            _row('💬', 'WhatsApp सपोर्ट (24×7)', 'कोई भी दिक्कत हो', const Icon(Icons.chevron_right, color: HF.mut)),
          ]),
        ),
        const SizedBox(height: 14),
        Center(child: Text('Happy Food Rider • Flutter v1.0', style: HF.hi(11.5, color: HF.mut))),
      ]),
    );
  }

  Widget _round(Widget child, VoidCallback onTap, {Color bg = HF.card, Color border = HF.line}) => GestureDetector(
        onTap: onTap,
        child: Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: border)), child: child),
      );

  Widget _row(String ic, String t, String s, Widget trailing) => ListTile(
        leading: Text(ic, style: const TextStyle(fontSize: 20)),
        title: Text(t, style: HF.hi(14, w: FontWeight.w800)),
        subtitle: Text(s, style: HF.hi(11.5, color: HF.mut)),
        trailing: trailing,
      );

  void _upload(_Doc d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: HF.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${d.icon} ${d.name}', style: HF.hi(18, w: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('फ़ोटो साफ़ हो, चारों कोने दिखें। जाँच 24 घंटे में होगी।', style: HF.hi(12.5, color: HF.mut)),
          const SizedBox(height: 16),
          GoldButton('📷 फ़ोटो खींचें', onTap: () {
            Navigator.pop(c);
            setState(() => d.state = 'review');
            hfToast(context, '${d.name} जाँच के लिए गया ⏳');
          }),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: () {
              Navigator.pop(c);
              setState(() => d.state = 'review');
              hfToast(context, '${d.name} जाँच के लिए गया ⏳');
            },
            child: Text('🖼️ गैलरी से चुनें', style: HF.hi(14, w: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  Widget _cardFront() {
    final r = Demo.rider;
    return Container(
      height: 200,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15110A), Color(0xFF3A2A0C), Color(0xFF15110A)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x80E2B04A)),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 22, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          RichText(text: TextSpan(style: HF.num(16, color: Colors.white), children: [const TextSpan(text: 'Happy '), TextSpan(text: 'Food', style: HF.num(16, color: HF.gold))])),
          const Spacer(),
          const Pill('DELIVERY PARTNER', bg: Color(0x33E2B04A), fg: HF.goldLight),
        ]),
        const Spacer(),
        Row(children: [
          Container(width: 58, height: 58, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)]), border: Border.all(color: HF.goldLight, width: 2)), child: Text(r.initials, style: HF.num(20, color: HF.ink))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: HF.num(21, color: Colors.white)),
              Text('⭐ ${r.rating}  •  ${r.trips} डिलीवरी', style: HF.hi(12.5, color: Colors.white70)),
            ]),
          ),
        ]),
        const Spacer(),
        Row(children: [
          Text('पार्टनर ID', style: HF.hi(10.5, color: Colors.white54)),
          const SizedBox(width: 6),
          Text('HFR-8821', style: HF.num(14, color: HF.gold)),
          const Spacer(),
          Text('KYC ✓', style: HF.hi(12, color: const Color(0xFF86EFAC), w: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _cardBack() {
    final r = Demo.rider;
    Widget l(String a, String b) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [SizedBox(width: 100, child: Text(a, style: HF.hi(12, color: HF.mut))), Expanded(child: Text(b, style: HF.hi(13.5, w: FontWeight.w800)))]));
    return Container(
      height: 200,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: HF.gold, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('संपर्क और गाड़ी', style: HF.hi(15, w: FontWeight.w800)),
        const SizedBox(height: 6),
        l('मोबाइल', r.phone),
        l('गाड़ी', r.bike),
        l('ज़ोन', 'सदर बाज़ार – बाड़ा हिंदू राव'),
        l('जुड़े', '03 Aug 2026'),
        l('इमरजेंसी', '+91 98••• ••210'),
      ]),
    );
  }
}
