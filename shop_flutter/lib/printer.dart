import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/shop_ui.dart';

/// What goes on a printed slip. Hindi works because the slip is drawn as a picture (with the bundled Mukta font)
/// and sent to the printer as an ESC/POS raster image — printers' own fonts cannot print Devanagari.
class Receipt {
  final String shop, sub, billNo, payLabel, footer;
  final String? heading, customer, phone, address, qr, code, note;
  final DateTime at;
  final List<(String, num, num)> items; // name, price, qty
  final num subtotal, discount, total;
  const Receipt({required this.shop, this.sub = 'Happy Food पार्टनर', required this.billNo, required this.at, required this.items, required this.subtotal, this.discount = 0, required this.total, this.payLabel = '', this.footer = 'धन्यवाद! घर बैठे मँगाने के लिए Happy Food ऐप', this.heading, this.customer, this.phone, this.address, this.qr, this.code, this.note});
}

class Printer {
  static const _kMac = 'printer_mac', _kName = 'printer_name', _kWidth = 'printer_mm';
  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();
  static Future<int> paperMm() async => (await _p).getInt(_kWidth) ?? 58;
  static Future<void> setPaperMm(int mm) async => (await _p).setInt(_kWidth, mm);
  static Future<(String?, String?)> saved() async { final p = await _p; return (p.getString(_kMac), p.getString(_kName)); }
  static Future<void> save(String mac, String name) async { final p = await _p; await p.setString(_kMac, mac); await p.setString(_kName, name); }

  static int dots(int mm) => mm >= 80 ? 576 : 384;

  /// Draws the slip as a black-and-white picture [w] dots wide.
  static Future<ui.Image> render(Receipt r, int w) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const maxH = 4000.0;
    c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), maxH), Paint()..color = Colors.white);
    final k = w / 384; // scale fonts for 80 mm
    const pad = 6.0;
    final inner = w - pad * 2;
    double y = 6;
    TextStyle st(double s, {bool b = false}) => TextStyle(fontFamily: 'Mukta', fontFamilyFallback: const ['Outfit'], fontSize: s * k, fontWeight: b ? FontWeight.w800 : FontWeight.w500, color: Colors.black, height: 1.15);
    double text(String t, double s, {bool b = false, TextAlign a = TextAlign.left, double? x, double? width, bool draw = true}) {
      final tp = TextPainter(text: TextSpan(text: t, style: st(s, b: b)), textAlign: a, textDirection: TextDirection.ltr)..layout(minWidth: width ?? inner, maxWidth: width ?? inner);
      if (draw) tp.paint(c, Offset(x ?? pad, y));
      return tp.height;
    }
    void line({bool dash = false, double t = 2}) {
      final p = Paint()..color = Colors.black..strokeWidth = t;
      if (!dash) { c.drawLine(Offset(pad, y), Offset(w - pad, y), p); } else { for (double x = pad; x < w - pad; x += 10) { c.drawLine(Offset(x, y), Offset(x + 5, y), p); } }
      y += t + 6;
    }
    void row(String l, String rt, double s, {bool b = false}) {
      final lw = inner * .66;
      final h1 = text(l, s, b: b, width: lw);
      final h2 = text(rt, s, b: b, a: TextAlign.right, x: pad + lw, width: inner - lw);
      y += (h1 > h2 ? h1 : h2) + 2;
    }

    if (r.heading != null) { y += text(r.heading!, 24, b: true, a: TextAlign.center) + 2; line(); }
    y += text(r.shop, 26, b: true, a: TextAlign.center);
    y += text(r.sub, 16, a: TextAlign.center) + 4;
    line();
    row('बिल: ${r.billNo}', '', 20, b: true);
    final d = r.at;
    row('${d.day}/${d.month}/${d.year}, ${hm(d)}', r.payLabel, 17);
    if ((r.customer ?? '').isNotEmpty || (r.phone ?? '').isNotEmpty) row(r.customer ?? '', r.phone ?? '', 17);
    if ((r.address ?? '').isNotEmpty) y += text('पता: ${r.address}', 17) + 2;
    line();
    for (final i in r.items) {
      row(i.$1, rupee(i.$2 * i.$3), 20, b: true);
      y += text('   ${rupee(i.$2)} × ${i.$3}', 15) + 2;
    }
    line();
    row('जोड़', rupee(r.subtotal), 18);
    if (r.discount > 0) row('छूट', '−${rupee(r.discount)}', 18);
    row('कुल', rupee(r.total), 28, b: true);
    if (r.qr != null) {
      y += 6; line(dash: true);
      if (r.note != null) { y += text(r.note!, 17, b: true, a: TextAlign.center) + 4; }
      final qs = (w * .62).roundToDouble();
      c.save(); c.translate((w - qs) / 2, y);
      QrPainter(data: r.qr!, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black)).paint(c, Size(qs, qs));
      c.restore();
      y += qs + 6;
      if (r.code != null) y += text('पिकअप कोड: ${r.code}', 26, b: true, a: TextAlign.center) + 4;
    }
    y += 6; line(dash: true);
    y += text(r.footer, 15, a: TextAlign.center) + 4;
    y += text('Powered by Filipra Private Limited', 13, a: TextAlign.center) + 14;
    return rec.endRecording().toImage(w, y.ceil().clamp(40, maxH.toInt()));
  }

  /// Picture → ESC/POS "GS v 0" raster commands (sent in bands so small printers keep up).
  static Future<List<int>> escpos(ui.Image img) async {
    final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final w = img.width, h = img.height, bpr = (w + 7) ~/ 8;
    final out = <int>[0x1B, 0x40, 0x1B, 0x61, 0x01];
    for (var y0 = 0; y0 < h; y0 += 120) {
      final rows = (h - y0) < 120 ? h - y0 : 120;
      out.addAll([0x1D, 0x76, 0x30, 0x00, bpr & 0xff, bpr >> 8, rows & 0xff, rows >> 8]);
      for (var y = y0; y < y0 + rows; y++) {
        for (var bx = 0; bx < bpr; bx++) {
          var b = 0;
          for (var bit = 0; bit < 8; bit++) {
            final x = bx * 8 + bit;
            if (x < w) {
              final i = (y * w + x) * 4;
              final lum = (bd.getUint8(i) * 299 + bd.getUint8(i + 1) * 587 + bd.getUint8(i + 2) * 114) ~/ 1000;
              if (lum < 150 && bd.getUint8(i + 3) > 100) b |= 0x80 >> bit;
            }
          }
          out.add(b);
        }
      }
    }
    out.addAll([0x1B, 0x64, 0x04, 0x1D, 0x56, 0x42, 0x00]);
    return out;
  }

  static Future<Uint8List> png(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

  static Future<bool> _perms() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return r.values.every((s) => s.isGranted || s.isLimited) || (await Permission.bluetooth.status).isGranted || r.values.any((s) => s.isRestricted);
  }

  static Future<String?> sendBytes(List<int> bytes, String mac) async {
    if (!await PrintBluetoothThermal.bluetoothEnabled) return 'फ़ोन का Bluetooth बंद है — चालू करें';
    var ok = await PrintBluetoothThermal.connectionStatus;
    if (!ok) { ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac); }
    if (!ok) return 'प्रिंटर से जुड़ नहीं पाए। प्रिंटर चालू करें, पास रखें और फिर कोशिश करें — या नीचे RawBT ऐप से प्रिंट करें।';
    for (var i = 0; i < bytes.length; i += 4096) {
      final part = bytes.sublist(i, i + 4096 > bytes.length ? bytes.length : i + 4096);
      final w = await PrintBluetoothThermal.writeBytes(part);
      if (!w) return 'प्रिंट भेजते समय कनेक्शन टूट गया — फिर कोशिश करें';
    }
    return null;
  }

  /// Print with the saved printer straight away; returns an error text or null.
  static Future<String?> quickPrint(Receipt r) async {
    final (mac, _) = await saved();
    if (mac == null) return 'no_printer';
    if (!await _perms()) return 'Bluetooth की अनुमति दीजिए';
    final img = await render(r, dots(await paperMm()));
    return sendBytes(await escpos(img), mac);
  }
}

/// Printer sheet — same as the web shop panel: status, paper width, find & print, RawBT, preview.
Future<void> showPrinter(BuildContext context, Receipt r) => hfSheet(context, (c, ctl) => _PrinterSheet(r: r, ctl: ctl), size: .9);

class _PrinterSheet extends StatefulWidget {
  final Receipt r;
  final ScrollController ctl;
  const _PrinterSheet({required this.r, required this.ctl});
  @override
  State<_PrinterSheet> createState() => _PrinterSheetState();
}

class _PrinterSheetState extends State<_PrinterSheet> {
  int mm = 58;
  String? mac, name, err;
  bool busy = false;
  Uint8List? preview;

  @override
  void initState() {
    super.initState();
    () async {
      mm = await Printer.paperMm();
      final s = await Printer.saved(); mac = s.$1; name = s.$2;
      await _preview();
    }();
  }

  Future<void> _preview() async {
    final img = await Printer.render(widget.r, Printer.dots(mm));
    final b = await Printer.png(img);
    if (mounted) setState(() => preview = b);
  }

  Future<void> _print({bool choose = false}) async {
    setState(() { busy = true; err = null; });
    try {
      if (!await Printer._perms()) { setState(() => err = 'Bluetooth की अनुमति दीजिए — सेटिंग में ऐप की "Nearby devices" अनुमति चालू करें'); return; }
      if (!await PrintBluetoothThermal.bluetoothEnabled) { setState(() => err = 'फ़ोन का Bluetooth बंद है — चालू करके फिर दबाएँ'); return; }
      if (mac == null || choose) {
        final list = await PrintBluetoothThermal.pairedBluetooths;
        if (!mounted) return;
        if (list.isEmpty) { setState(() => err = 'कोई पेयर किया हुआ प्रिंटर नहीं मिला। फ़ोन की Bluetooth सेटिंग में प्रिंटर को पेयर करें (PIN अक्सर 0000 या 1234), फिर यहाँ वापस आएँ।'); return; }
        final pick = await showModalBottomSheet<BluetoothInfo>(
          context: context,
          backgroundColor: HF.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
          builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('प्रिंटर चुनें', style: HF.hi(18, w: FontWeight.w800))),
            for (final d in list) ListTile(leading: const Icon(Icons.print), title: Text(d.name, style: HF.hi(15, w: FontWeight.w700)), subtitle: Text(d.macAdress), onTap: () => Navigator.pop(c, d)),
            const SizedBox(height: 10),
          ])),
        );
        if (pick == null) return;
        await PrintBluetoothThermal.disconnect;
        mac = pick.macAdress; name = pick.name;
        await Printer.save(mac!, name!);
      }
      final img = await Printer.render(widget.r, Printer.dots(mm));
      final e = await Printer.sendBytes(await Printer.escpos(img), mac!);
      if (!mounted) return;
      if (e != null) { setState(() => err = e); } else { hfToast(context, 'प्रिंट हो गया 🖨️'); }
    } catch (e) {
      if (mounted) setState(() => err = 'प्रिंट नहीं हुआ: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _rawbt() async {
    final img = await Printer.render(widget.r, Printer.dots(mm));
    final b64 = base64Encode(await Printer.escpos(img));
    final ok = await launchUrl(Uri.parse('rawbt:base64,$b64'), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok) await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=ru.a402d.rawbtprinter'), mode: LaunchMode.externalApplication).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) => ListView(controller: widget.ctl, padding: const EdgeInsets.fromLTRB(0, 0, 0, 30), children: [
        sheetHead(context, '🖨️ प्रिंटर'),
        if (err != null)
          Container(margin: const EdgeInsets.fromLTRB(16, 4, 16, 0), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(18)), child: Text('⚠️ $err', style: HF.hi(14, color: HF.bad, w: FontWeight.w700))),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(child: Text(mac == null ? '⚪ कोई प्रिंटर नहीं जुड़ा' : '🟢 प्रिंटर: ${name ?? mac}', style: HF.hi(15, w: FontWeight.w800))),
            if (mac != null) TextButton(onPressed: busy ? null : () => _print(choose: true), child: Text('बदलें', style: HF.hi(14, color: HF.goldDeep))),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 6), child: Text('काग़ज़ की चौड़ाई', style: HF.hi(15, w: FontWeight.w700))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final m in [58, 80])
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () async { setState(() => mm = m); await Printer.setPaperMm(m); _preview(); },
                  child: Container(height: 54, alignment: Alignment.center, decoration: BoxDecoration(color: mm == m ? const Color(0xFFECFDF3) : HF.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: mm == m ? const Color(0xFF16A34A) : HF.line, width: mm == m ? 2 : 1)), child: Text('$m mm', style: HF.num(16, color: mm == m ? const Color(0xFF166534) : HF.tx, w: FontWeight.w800))),
                ),
              )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: GestureDetector(
            onTap: busy ? null : () => _print(),
            child: Container(height: 58, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF16120B), borderRadius: BorderRadius.circular(18)), child: Text(busy ? 'प्रिंट हो रहा है…' : (mac == null ? 'ᛒ प्रिंटर खोजें और प्रिंट करें' : '🖨️ प्रिंट करें'), style: HF.hi(16, color: HF.goldLight, w: FontWeight.w800))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: GestureDetector(
            onTap: _rawbt,
            child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: HF.card2, borderRadius: BorderRadius.circular(18)), child: Text('📲  RawBT ऐप से प्रिंट (पुराने Bluetooth प्रिंटर के लिए)', style: HF.hi(14.5, w: FontWeight.w700))),
          ),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 6), child: Text('झलक', style: HF.hi(15, w: FontWeight.w700))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 30),
          decoration: BoxDecoration(color: const Color(0xFFE7E5E4), borderRadius: BorderRadius.circular(18)),
          child: preview == null ? const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(color: HF.goldDeep))) : Container(decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10)]), child: Image.memory(preview!, filterQuality: FilterQuality.medium)),
        ),
      ]);
}
