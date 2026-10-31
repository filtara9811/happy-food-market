import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

/// Remember the shop name / area so the opening animation can show it before login data loads.
class ShopNameCache {
  static Future<(String, String)> read() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getString('shop_name') ?? '', p.getString('shop_area') ?? '');
    } catch (_) {
      return ('', '');
    }
  }

  static Future<void> save(String name, String area) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('shop_name', name);
      await p.setString('shop_area', area);
    } catch (_) {}
  }
}

/// Opening screen: sign board drops in, awning, then the shutter rolls up, the tube light flickers on
/// and the OPEN board swings — the shopkeeper "opens the shop".
class ShopOpenSplash extends StatefulWidget {
  final VoidCallback onDone;
  const ShopOpenSplash({super.key, required this.onDone});
  @override
  State<ShopOpenSplash> createState() => _ShopOpenSplashState();
}

class _ShopOpenSplashState extends State<ShopOpenSplash> with TickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController sway = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  String name = '', area = '';
  bool done = false;

  @override
  void initState() {
    super.initState();
    ShopNameCache.read().then((v) { if (mounted) setState(() { name = v.$1; area = v.$2; }); });
    c.forward();
    Future.delayed(const Duration(milliseconds: 700), () => HapticFeedback.lightImpact());
    Future.delayed(const Duration(milliseconds: 1500), () => HapticFeedback.selectionClick());
    c.addStatusListener((s) { if (s == AnimationStatus.completed) _finish(); });
  }

  void _finish() {
    if (done) return;
    done = true;
    widget.onDone();
  }

  @override
  void dispose() { c.dispose(); sway.dispose(); super.dispose(); }

  double _iv(double a, double b, {Curve curve = Curves.easeOutBack}) => curve.transform(((c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _finish,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.3), radius: 1.1, colors: [Color(0xFF3A2410), Color(0xFF17130F)], stops: [0, .7])),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([c, sway]),
              builder: (_, __) => Stack(children: [
                Positioned(top: 18, left: 0, right: 0, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(gradient: HF.goldGrad, borderRadius: BorderRadius.circular(10)), child: const Text('😋', style: TextStyle(fontSize: 18))),
                  const SizedBox(width: 10),
                  RichText(text: TextSpan(style: HF.num(17, color: Colors.white, w: FontWeight.w800), children: const [TextSpan(text: 'Happy Food '), TextSpan(text: 'Shop', style: TextStyle(color: Color(0xFFF2B632)))])),
                ])),
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _store(),
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: _iv(.45, .7, curve: Curves.easeOut),
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - _iv(.45, .7, curve: Curves.easeOut))),
                      child: Column(children: [
                        Text(name.isEmpty ? 'आपकी दुकान' : name, textAlign: TextAlign.center, style: HF.num(27, color: Colors.white, w: FontWeight.w900)),
                        const SizedBox(height: 4),
                        RichText(text: TextSpan(style: HF.hi(14, color: Colors.white70, w: FontWeight.w600), children: const [TextSpan(text: 'Happy Food '), TextSpan(text: 'Shop', style: TextStyle(color: Color(0xFFF2B632), fontWeight: FontWeight.w800)), TextSpan(text: ' · दुकान खुल रही है…')])),
                      ]),
                    ),
                  ),
                ])),
                Positioned(bottom: 18, left: 0, right: 0, child: Text('टैप करके आगे बढ़ें', textAlign: TextAlign.center, style: HF.hi(12, color: Colors.white54, w: FontWeight.w700))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _store() {
    const w = 260.0;
    final sign = _iv(0, .22), awn = _iv(.06, .28);
    final up = Curves.easeInOutCubic.transform(((c.value - .28) / .4).clamp(0.0, 1.0)); // shutter goes up
    final lightT = ((c.value - .5) / .2).clamp(0.0, 1.0);
    final light = lightT == 0 ? .25 : (lightT < .3 ? .9 : (lightT < .45 ? .4 : 1.0)); // tube light flicker
    final lit = c.value > .6;
    return SizedBox(
      width: w + 24,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // sign board
        Opacity(opacity: sign.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -120 * (1 - sign)), child: Container(
          height: 50, margin: const EdgeInsets.symmetric(horizontal: 18), padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1F3B2A), Color(0xFF132A1D)]),
            borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFC9A24A), width: 3),
            boxShadow: lit ? const [BoxShadow(color: Color(0x73FFC85A), blurRadius: 24)] : null,
          ),
          child: Row(children: [
            Container(width: 30, height: 30, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFFFFE7A8), borderRadius: BorderRadius.circular(8)), child: const Text('🏪', style: TextStyle(fontSize: 17))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(name.isEmpty ? 'Happy Food Kitchen' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'serif', fontSize: 16.5, fontWeight: FontWeight.w700, color: Color(0xFFFFE7A8))),
              Text(area.isEmpty ? 'Sadar Bazaar, Delhi' : area, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFD6C08A), letterSpacing: .4)),
            ])),
          ]),
        ))),
        // awning
        Opacity(opacity: awn.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -120 * (1 - awn)), child: SizedBox(height: 40, width: w + 24, child: CustomPaint(painter: _Awning())))),
        // wall + door
        Container(
          width: w, height: 210, padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          decoration: const BoxDecoration(color: Color(0xFF8F4A28)),
          foregroundDecoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0x2E000000), Colors.transparent, Colors.transparent, Color(0x2E000000)], stops: [0, .05, .95, 1])),
          child: CustomPaint(
            painter: _Bricks(),
            child: Column(children: [
              Container(height: 16, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF77736B), Color(0xFF4A4740), Color(0xFF3A3833)]))),
              Expanded(child: Container(
                decoration: const BoxDecoration(color: Color(0xFF1A1410), border: Border.symmetric(vertical: BorderSide(color: Color(0xFF3D3A35), width: 7))),
                child: ClipRect(child: LayoutBuilder(builder: (_, box) => Stack(children: [
                  // inside the shop
                  Positioned.fill(child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(_bright(light)),
                    child: Container(
                      decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -1), radius: 1.3, colors: [Color(0xFFFFD98A), Color(0xFFD9963E), Color(0xFF6A4320)], stops: [0, .45, 1])),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        _shelf('🍛 🥟 🍢 🧆'),
                        _shelf('🍲 🥗 🍮 🥤'),
                        Container(height: 26, margin: const EdgeInsets.fromLTRB(10, 4, 10, 0), decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(4)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8A5A30), Color(0xFF5E3B1D)]))),
                      ]),
                    ),
                  )),
                  // tube light
                  if (lightT > .2) Positioned(top: 6, left: box.maxWidth * .24, right: box.maxWidth * .24, child: Container(height: 4, decoration: BoxDecoration(color: const Color(0xFFFFFBE8), borderRadius: BorderRadius.circular(3), boxShadow: const [BoxShadow(color: Color(0xCCFFF8C8), blurRadius: 14, spreadRadius: 4)]))),
                  // OPEN board
                  Positioned(top: 18, left: 0, right: 0, child: Center(child: Transform.rotate(
                    angle: lit ? (sway.value - .5) * .17 : 0, alignment: const Alignment(0, -2),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 50, height: 12, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF444444), width: 2), left: BorderSide(color: Color(0xFF444444), width: 2), right: BorderSide(color: Color(0xFF444444), width: 2)), borderRadius: BorderRadius.vertical(top: Radius.circular(40)))),
                      Container(width: 80, padding: const EdgeInsets.symmetric(vertical: 4), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF0F2A18), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF3EAF5C), width: 2), boxShadow: const [BoxShadow(color: Color(0xA63EAF5C), blurRadius: 16)]),
                          child: const Text('OPEN', style: TextStyle(color: Color(0xFF3EAF5C), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 3))),
                    ]),
                  ))),
                  // shutter
                  Positioned(left: 0, right: 0, top: -box.maxHeight * 1.01 * up, height: box.maxHeight, child: CustomPaint(painter: _Shutter())),
                ]))),
              )),
            ]),
          ),
        ),
        Container(height: 9, width: w + 16, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9A948A), Color(0xFF6E6A62)]))),
      ]),
    );
  }

  Widget _shelf(String t) => Container(
        padding: const EdgeInsets.only(bottom: 3), margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF6B4423), width: 3))),
        child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
      );

  List<double> _bright(double k) => [k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, 1, 0];
}

class _Awning extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    const n = 12;
    final sw = s.width / n, h = s.height - 10;
    for (var i = 0; i < n; i++) {
      final p = Paint()..color = i.isEven ? const Color(0xFFF47B20) : const Color(0xFFFFE2BD);
      c.drawRect(Rect.fromLTWH(i * sw, 0, sw + .5, h), p);
      c.drawArc(Rect.fromLTWH(i * sw, h - sw / 2, sw, sw), 0, math.pi, true, p);
    }
    c.drawRect(Rect.fromLTWH(0, h - 2, s.width, 2), Paint()..color = const Color(0x22000000));
  }

  @override
  bool shouldRepaint(_) => false;
}

class _Bricks extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final a = Paint()..color = const Color(0xFFB4643A);
    for (double y = 0; y < s.height; y += 15) { c.drawRect(Rect.fromLTWH(-12, y, s.width + 24, 13), a); }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _Shutter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    for (double y = 0; y < s.height; y += 12) {
      final r = Rect.fromLTWH(0, y, s.width, 12);
      c.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFDCD9D2), Color(0xFFC4C1B9), Color(0xFFA29F97), Color(0xFF7F7C75), Color(0xFF55524C)], stops: [0, .25, .55, .85, 1]).createShader(r));
    }
    c.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(colors: [Color(0x38000000), Color(0x1FFFFFFF), Color(0x00FFFFFF), Color(0x14000000), Color(0x40000000)], stops: [0, .18, .4, .7, 1]).createShader(Offset.zero & s));
    final bar = Rect.fromLTWH(0, s.height - 15, s.width, 15);
    c.drawRect(bar, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6F6C65), Color(0xFF4B4842), Color(0xFF3A3833)]).createShader(bar));
    final h = Paint()..color = const Color(0xFF2E2C28);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width * .18, s.height - 10, 22, 7), const Radius.circular(3)), h);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s.width * .82 - 22, s.height - 10, 22, 7), const Radius.circular(3)), h);
  }

  @override
  bool shouldRepaint(_) => false;
}
