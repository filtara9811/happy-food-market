import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shop_ui.dart';
import '../printer.dart';

/// "दुकान" tab — same as the web shop panel: dark profile card, 3 numbers, open / auto-accept switches,
/// 8 tiles, shop details form with fold-out sections, support / language / logout, footer.
class ShopPage extends StatefulWidget {
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> orders;
  final Future<void> Function() reload;
  final VoidCallback toggleOpen, openInventory, openEarnings, openBills;
  const ShopPage({super.key, required this.me, required this.orders, required this.reload, required this.toggleOpen, required this.openInventory, required this.openEarnings, required this.openBills});
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  late final name = TextEditingController(text: '${widget.me['shop_name'] ?? ''}');
  late final owner = TextEditingController(text: '${widget.me['owner'] ?? ''}');
  late final addr = TextEditingController(text: '${widget.me['address'] ?? ''}');
  late final prep = TextEditingController(text: '${widget.me['prep_min'] ?? 15}');
  late final hours = TextEditingController(text: '${widget.me['hours'] ?? ''}');
  late final upi = TextEditingController(text: '${widget.me['upi'] ?? ''}');
  late final fssai = TextEditingController(text: '${widget.me['fssai'] ?? ''}');
  late final gstin = TextEditingController(text: '${widget.me['gstin'] ?? ''}');
  bool infoOpen = true, busy = false;
  final fold = <String>{};

  Map<String, dynamic> get me => widget.me;
  String get _initials { final p = '${me['shop_name'] ?? 'HF'}'.trim().split(RegExp(r'\s+')); return (p.length > 1 ? p[0].characters.first + p[1].characters.first : p[0].characters.take(2).toString()).toUpperCase(); }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await Api.rpc('vendor_update', {'p': {'shop_name': name.text.trim(), 'owner': owner.text.trim(), 'address': addr.text.trim(), 'prep_min': int.tryParse(prep.text.trim()) ?? 15, 'hours': hours.text.trim(), 'upi': upi.text.trim(), 'fssai': fssai.text.trim(), 'gstin': gstin.text.trim()}});
      await widget.reload();
      if (mounted) hfToast(context, 'सब सेव हो गया ✅');
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) { if (mounted) hfToast(context, 'फ़ोन की लोकेशन (GPS) चालू करें'); return; }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) { if (mounted) hfToast(context, 'लोकेशन की अनुमति दीजिए'); return; }
      if (mounted) hfToast(context, '📍 लोकेशन ले रहे हैं… दुकान के अंदर ही रहें');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await Api.rpc('vendor_set_location', {'p_lat': pos.latitude, 'p_lng': pos.longitude});
      if (mounted) hfToast(context, '📍 दुकान की लोकेशन सेव — अब पास के ग्राहकों के ऑर्डर आएँगे');
    } catch (e) {
      if (mounted) hfToast(context, errText(e));
    }
  }

  Future<void> autoAccept(bool v) async {
    try { await Api.rpc('vendor_update', {'p': {'auto_accept': v}}); await widget.reload(); if (mounted) hfToast(context, v ? 'ऑर्डर अपने-आप स्वीकार होंगे ⚡' : 'ऑर्डर ख़ुद स्वीकार करेंगे'); }
    catch (e) { if (mounted) hfToast(context, errText(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final joined = DateTime.tryParse('${me['created_at']}')?.toLocal();
    final verified = me['approved'] == true && me['suspended'] != true;
    final docsMissing = '${me['fssai'] ?? ''}'.isEmpty || '${me['gstin'] ?? ''}'.isEmpty;
    final link = shopLink(me['id']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // dark profile card
      Container(
        margin: EdgeInsets.fromLTRB(16, top + 14, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: HF.heroGrad, borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))]),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(width: 72, height: 72, alignment: Alignment.center, decoration: BoxDecoration(gradient: HF.avGrad, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .85), width: 2)), child: Text(_initials, style: HF.num(26, color: HF.ink))),
            Positioned(right: -4, bottom: -4, child: Container(width: 26, height: 26, decoration: BoxDecoration(color: HF.ink, shape: BoxShape.circle, border: Border.all(color: HF.gold, width: 2)), child: const Icon(Icons.photo_camera, size: 13, color: HF.goldLight))),
            const Positioned(left: -5, top: -5, child: FlutterBadge(size: 22)),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${me['shop_name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: HF.num(20, color: Colors.white, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${me['owner'] ?? ''} • ${me['suspended'] == true ? '🚫 सस्पेंड' : (verified ? '✅ वेरिफ़ाइड' : '⏳ मंज़ूरी बाकी')}', style: HF.hi(12.5, color: Colors.white70, w: FontWeight.w600)),
            Text('⭐ नया • जुड़े ${joined == null ? '' : '${joined.day} ${_mon[joined.month - 1]} ${joined.year}'}', style: HF.hi(12, color: Colors.white60, w: FontWeight.w600)),
          ])),
        ]),
      ),
      // 3 numbers
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          _num('${me['total_bills'] ?? 0}', 'कुल ऑर्डर', widget.openBills),
          const SizedBox(width: 8),
          _num(rupee((me['month_total'] ?? 0) as num), 'इस महीने', widget.openEarnings),
          const SizedBox(width: 8),
          _num('⭐ —', '0 रिव्यू', () => hfToast(context, 'अभी कोई रिव्यू नहीं')),
        ]),
      ),
      // switches
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.line)),
        child: Column(children: [
          _switch('🟢 दुकान खुली है', 'बंद होने पर ग्राहक को आपके आइटम नहीं दिखेंगे', me['open'] == true, (_) => widget.toggleOpen()),
          const Divider(height: 1),
          _switch('⚡ ऑर्डर अपने-आप स्वीकार', 'भीड़ के समय काम आता है', me['auto_accept'] == true, autoAccept),
        ]),
      ),
      // 8 tiles
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .95, children: [
          _tile('📱', 'मेरा QR', () => showMyQr(context, me)),
          _tile('🏪', 'डिजिटल दुकान', () => openUrl(context, link)),
          _tile('🖼️', 'बैनर', () => hfToast(context, 'बैनर अगले अपडेट में')),
          _tile('📦', 'इन्वेंट्री', widget.openInventory),
          _tile('💰', 'कमाई', widget.openEarnings),
          _tile('🧾', 'बिल', widget.openBills),
          _tile('⭐', 'रिव्यू', () => hfToast(context, 'अभी कोई रिव्यू नहीं')),
          _tile('🛵', 'राइडर स्टॉक', () => hfToast(context, 'राइडर को स्टॉक देना अगले अपडेट में')),
        ]),
      ),
      // share shop link
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFE9F7EE), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF86EFAC))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('🔗 मेरी दुकान का लिंक', style: HF.hi(15, w: FontWeight.w800)),
          Text('ग्राहक इसे खोलकर आपका स्टॉक देखेंगे और सीधे आपको WhatsApp पर ऑर्डर भेजेंगे', style: HF.hi(12, color: HF.mut, w: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: pillBtn('WhatsApp पर भेजें', const Color(0xFF16A34A), Colors.white, Icons.chat, () => whatsApp(context, '🏪 ${me['shop_name']} — Happy Food पर सीधे ऑर्डर करें 👉 $link'))),
            const SizedBox(width: 8),
            SizedBox(width: 56, child: pillBtn('', HF.card, HF.tx, Icons.share, () => shareText('🏪 ${me['shop_name']} — Happy Food पर सीधे ऑर्डर करें 👉 $link'))),
          ]),
        ]),
      ),
      // info form
      _foldCard('🏪 दुकान की जानकारी', infoOpen, () => setState(() => infoOpen = !infoOpen), Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field('दुकान का नाम', name),
        _field('मालिक का नाम', owner),
        _field('पता', addr, lines: 2),
        Row(children: [
          Expanded(child: _field('फ़ोन', TextEditingController(text: _phone('${me['phone'] ?? ''}')), enabled: false)),
          const SizedBox(width: 10),
          Expanded(child: _field('तैयारी (मिनट)', prep, num: true)),
        ]),
      ])),
      _foldCard('⏰ खुलने का समय', fold.contains('h'), () => setState(() => fold.contains('h') ? fold.remove('h') : fold.add('h')), _field('जैसे 09:00 - 23:00', hours)),
      _foldCard('💳 पेमेंट (पैसा कहाँ आए)', fold.contains('p'), () => setState(() => fold.contains('p') ? fold.remove('p') : fold.add('p')), _field('UPI ID (जैसे shop@upi)', upi)),
      _foldCard('📄 दस्तावेज़', fold.contains('d'), () => setState(() => fold.contains('d') ? fold.remove('d') : fold.add('d')), Column(children: [_field('FSSAI नंबर', fssai), _field('GSTIN (हो तो)', gstin)]), badge: docsMissing ? 'अधूरे' : null),
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: GoldButton(busy ? 'सेव हो रहा…' : '✓ सब सेव करें', onTap: busy ? null : save)),
      // rows
      Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.line)),
        child: Column(children: [
          _row('📍', 'दुकान की लोकेशन (GPS) सेट करें', setLocation),
          const Divider(height: 1, indent: 50),
          _row('🖨️', 'प्रिंटर सेटिंग / टेस्ट प्रिंट', () => showPrinter(context, Receipt(shop: '${me['shop_name'] ?? ''}', billNo: 'TEST', at: DateTime.now(), items: const [('टेस्ट प्रिंट — हिंदी ठीक दिख रही है?', 1, 1)], subtotal: 1, total: 1, payLabel: 'टेस्ट'))),
          const Divider(height: 1, indent: 50),
          _row('💬', 'Happy Food सपोर्ट (WhatsApp)', () => whatsApp(context, 'नमस्ते, मैं ${me['shop_name']} से बात कर रहा हूँ।', phone: '919540068380')),
          const Divider(height: 1, indent: 50),
          _row('🌐', 'भाषा: हिंदी → English', () => hfToast(context, 'English जल्द आएगी')),
          const Divider(height: 1, indent: 50),
          _row('🚪', 'लॉग-आउट', () async { await Api.signOut(); if (context.mounted) goNext(context); }),
        ]),
      ),
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.center, children: [
        for (final l in [['नियम व शर्तें', 'terms'], ['प्राइवेसी पॉलिसी', 'privacy'], ['रिफ़ंड पॉलिसी', 'refund']])
          TextButton(onPressed: () => openUrl(context, 'https://filtara9811.github.io/happy-food-market/${l[1]}.html'), child: Text(l[0], style: HF.hi(13, color: HF.mut, w: FontWeight.w700))),
      ]),
      Center(child: Text('Happy Food Shop • दुकान कोड ${me['id'] == null ? '' : shopCode(me['id'])}', style: HF.hi(11.5, color: HF.mut))),
      const SizedBox(height: 10),
      Center(child: Text('P O W E R E D   B Y', style: HF.hi(11, color: const Color(0xFFB98A2C), w: FontWeight.w800))),
      const Center(child: Text('Filipra Private Limited', style: TextStyle(fontFamily: 'serif', fontSize: 22, fontWeight: FontWeight.w700, color: HF.tx))),
      Center(child: Text('© 2026 Happy Food · Made in India 🇮🇳', style: HF.hi(12, color: HF.mut))),
    ]);
  }

  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _phone(String p) { final d = p.replaceAll(RegExp(r'\D'), ''); final n = d.length > 10 ? d.substring(d.length - 10) : d; return n.length == 10 ? '+91 ${n.substring(0, 5)} ${n.substring(5)}' : p; }

  Widget _num(String v, String l, VoidCallback f) => Expanded(
        child: GestureDetector(
          onTap: f,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.line)),
            child: Column(children: [FittedBox(child: Text(v, style: HF.num(19, w: FontWeight.w800))), const SizedBox(height: 2), Text(l, style: HF.hi(11.5, color: HF.mut, w: FontWeight.w600))]),
          ),
        ),
      );

  Widget _switch(String t, String s, bool on, ValueChanged<bool> f) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: HF.hi(14.5, w: FontWeight.w800)), Text(s, style: HF.hi(11.5, color: HF.mut, w: FontWeight.w600))])),
          Toggle(on, f),
        ]),
      );

  Widget _tile(String ic, String l, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(
          decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: HF.line)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(ic, style: const TextStyle(fontSize: 26)), const SizedBox(height: 6), Text(l, textAlign: TextAlign.center, maxLines: 2, style: HF.hi(11.5, w: FontWeight.w700))]),
        ),
      );

  Widget _foldCard(String t, bool open, VoidCallback tap, Widget body, {String? badge}) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(color: HF.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: HF.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Text(t, style: HF.hi(15, w: FontWeight.w800)),
                if (badge != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(99)), child: Text(badge, style: HF.hi(11, color: const Color(0xFFB45309), w: FontWeight.w800)))],
                const Spacer(),
                AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.keyboard_arrow_down, color: HF.mut)),
              ]),
            ),
          ),
          AnimatedSize(duration: const Duration(milliseconds: 220), child: open ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: body) : const SizedBox(width: double.infinity)),
        ]),
      );

  Widget _field(String l, TextEditingController c, {int lines = 1, bool num = false, bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: HF.hi(11.5, color: HF.mut, w: FontWeight.w700)),
          const SizedBox(height: 4),
          TextField(
            controller: c, maxLines: lines, enabled: enabled, keyboardType: num ? TextInputType.number : TextInputType.text, style: HF.hi(15, w: FontWeight.w600),
            decoration: InputDecoration(isDense: true, filled: true, fillColor: const Color(0xFFF5EEDC), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          ),
        ]),
      );

  Widget _row(String ic, String t, VoidCallback f) => InkWell(
        onTap: f,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), child: Row(children: [Text(ic, style: const TextStyle(fontSize: 18)), const SizedBox(width: 14), Expanded(child: Text(t, style: HF.hi(14.5, w: FontWeight.w700))), const Icon(Icons.chevron_right, color: HF.mut)])),
      );
}
