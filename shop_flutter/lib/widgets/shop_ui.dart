import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';
import 'common.dart';

/// Public link of a shop (GitHub Pages page that reads `public_shop` from the server).
String shopLink(dynamic id) => 'https://filtara9811.github.io/happy-food-market/s/?v=$id';
String shopCode(dynamic id) => 'HF${id.toString().replaceAll('-', '').substring(0, 6).toUpperCase()}';

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) hfToast(context, 'खुल नहीं पाया');
}

Future<void> whatsApp(BuildContext context, String text, {String? phone}) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  final to = d.isEmpty ? '' : (d.length == 10 ? '91$d' : d);
  return openUrl(context, 'https://wa.me/$to?text=${Uri.encodeComponent(text)}');
}

Future<void> shareText(String text) => Share.share(text);

List<String> storeOf(String? k) => stores.firstWhere((s) => s[0] == k, orElse: () => ['food', '🍛', 'फ़ूड']);

/// Title row used on every bottom sheet: big title, close circle.
Widget sheetHead(BuildContext context, String title, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: HF.hi(20, w: FontWeight.w800)),
          if (sub != null) Text(sub, style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)),
        ])),
        GestureDetector(onTap: () => Navigator.pop(context), child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: HF.card2, shape: BoxShape.circle), child: const Icon(Icons.close, size: 20))),
      ]),
    );

Future<T?> hfSheet<T>(BuildContext context, Widget Function(BuildContext, ScrollController) body, {double size = .92}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: size, maxChildSize: .97, minChildSize: .4, expand: false,
        builder: (_, ctl) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: ScaffoldMessenger(child: Scaffold(backgroundColor: HF.bg, body: Builder(builder: (sc) => body(sc, ctl)))),
        ),
      ),
    );

/// "My QR" sticker — the same card the web shop panel shows.
void showMyQr(BuildContext context, Map me) {
  final id = me['id'], link = shopLink(id), name = (me['shop_name'] ?? '').toString();
  hfSheet(context, (c, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 18, 20, 30), children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFDE68A), Color(0xFFF2B632)]), borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x40E2A92C), blurRadius: 24, offset: Offset(0, 10))]),
          child: Column(children: [
            RichText(text: TextSpan(style: HF.num(24, color: HF.ink), children: const [TextSpan(text: 'Happy '), TextSpan(text: 'Food', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7A4A00)))])),
            Text('📱 स्कैन करें • ऑर्डर करें', style: HF.hi(15, color: HF.ink, w: FontWeight.w800)),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: QrImageView(data: link, size: 210, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF16120B)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF16120B)))),
            const SizedBox(height: 10),
            Text(name, textAlign: TextAlign.center, style: HF.num(20, color: HF.ink, w: FontWeight.w800)),
            Text('दुकान कोड: ${shopCode(id)} • ✅ वेरिफ़ाइड', style: HF.hi(12.5, color: HF.ink, w: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 14),
        Text('इसे प्रिंट करवाकर काउंटर या बाइक पर लगाइए। ग्राहक स्कैन करेगा तो सिर्फ़ आपकी दुकान और आपका स्टॉक दिखेगा।', textAlign: TextAlign.center, style: HF.hi(13, color: HF.mut, w: FontWeight.w600)),
        const SizedBox(height: 14),
        GoldButton('🏪 देखें: ग्राहक को क्या दिखेगा', onTap: () => openUrl(c, link)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _pillBtn('WhatsApp', const Color(0xFF16A34A), Colors.white, Icons.chat, () => whatsApp(c, '🏪 $name — Happy Food पर सीधे ऑर्डर करें 👉 $link'))),
          const SizedBox(width: 10),
          Expanded(child: _pillBtn('शेयर', HF.card, HF.tx, Icons.share, () => shareText('🏪 $name — Happy Food पर सीधे ऑर्डर करें 👉 $link'))),
        ]),
        const SizedBox(height: 10),
        _pillBtn('लिंक कॉपी करें', HF.card2, HF.tx, Icons.copy, () { Clipboard.setData(ClipboardData(text: link)); hfToast(c, 'लिंक कॉपी हो गया ✅'); }),
      ]), size: .9);
}

Widget _pillBtn(String t, Color bg, Color fg, IconData ic, VoidCallback f) => GestureDetector(
      onTap: f,
      child: Container(height: 50, alignment: Alignment.center, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: HF.line)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(ic, size: 18, color: fg), const SizedBox(width: 8), Text(t, style: HF.hi(15, color: fg, w: FontWeight.w800))])),
    );
Widget pillBtn(String t, Color bg, Color fg, IconData ic, VoidCallback f) => _pillBtn(t, bg, fg, ic, f);

/// Product picture with a 🍛 fallback.
Widget prodImg(dynamic url, double w, double h, {double r = 14}) {
  final u = (url ?? '').toString();
  final ph = Container(width: w, height: h, color: const Color(0xFFFFF3D6), alignment: Alignment.center, child: Text('🍛', style: TextStyle(fontSize: (w < h ? w : h) * .4)));
  return ClipRRect(borderRadius: BorderRadius.circular(r), child: u.startsWith('asset:') ? Image.asset('assets/food/${u.substring(6)}.webp', width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph) : (u.startsWith('http') ? Image.network(u, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph) : ph));
}
