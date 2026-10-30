import 'package:flutter/material.dart';
import '../theme.dart';

/// Small building blocks shared by the rider screens (same look as the prototype's partner panel).

class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, {super.key, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: HF.hi(12, color: fg, w: FontWeight.w800)),
      );
}

class HFCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  const HFCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.border});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? HF.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border ?? HF.line),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: box);
  }
}

class GoldButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  const GoldButton(this.text, {super.key, this.icon, this.onTap, this.height = 50});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .5 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: HF.goldGrad,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x59E2A92C), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: HF.ink), const SizedBox(width: 8)],
              Text(text, style: HF.hi(15, color: HF.ink, w: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

class EmojiDisc extends StatelessWidget {
  final String emoji;
  final double size;
  final bool check;
  const EmojiDisc(this.emoji, {super.key, this.size = 56, this.check = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size + 6,
        height: size + 6,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFF7E3),
              border: Border.all(color: const Color(0xFFF1E3C3), width: 3),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Text(emoji, style: TextStyle(fontSize: size * .5)),
          ),
          if (check)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: HF.gold, border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.check, size: 13, color: HF.ink),
              ),
            ),
        ]),
      );
}

/// The ✓—✓—✓ progress line under every order card.
class StepLine extends StatelessWidget {
  final List<(String label, String icon, bool done, bool cur)> steps;
  const StepLine(this.steps, {super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (i > 0)
                  Positioned(
                    top: 13,
                    right: 0,
                    left: 0,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: .5,
                      child: Container(height: 3, decoration: BoxDecoration(gradient: (steps[i].$3 || steps[i].$4) ? const LinearGradient(colors: [Color(0xFF22C55E), HF.gold]) : null, color: (steps[i].$3 || steps[i].$4) ? null : HF.line)),
                    ),
                  ),
                if (i < steps.length - 1)
                  Positioned(
                    top: 13,
                    right: 0,
                    left: 0,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerRight,
                      widthFactor: .5,
                      child: Container(height: 3, decoration: BoxDecoration(gradient: (steps[i + 1].$3 || steps[i + 1].$4) ? const LinearGradient(colors: [Color(0xFF22C55E), HF.gold]) : null, color: (steps[i + 1].$3 || steps[i + 1].$4) ? null : HF.line)),
                    ),
                  ),
                Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].$3 ? const Color(0xFFDCFCE7) : (steps[i].$4 ? HF.goldLight : HF.card2),
                      border: Border.all(color: steps[i].$3 ? const Color(0xFF22C55E) : (steps[i].$4 ? HF.gold : HF.line), width: 2),
                    ),
                    child: steps[i].$3 ? const Icon(Icons.check, size: 15, color: HF.ok) : Text(steps[i].$2, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i].$1, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: HF.hi(11, color: steps[i].$3 ? HF.ok : (steps[i].$4 ? HF.goldDeep : HF.mut), w: FontWeight.w800)),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}

class Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const Toggle(this.on, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: on ? HF.ok : const Color(0xFFD6D3D1), borderRadius: BorderRadius.circular(20)),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 24, height: 24, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3)])),
        ),
      );
}

void hfToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF14110B),
      margin: const EdgeInsets.fromLTRB(60, 0, 14, 110),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0x99E2B04A))),
      content: Row(children: [
        Container(width: 26, height: 26, decoration: const BoxDecoration(color: HF.gold, shape: BoxShape.circle), child: const Icon(Icons.check, size: 15, color: HF.ink)),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: HF.hi(13, color: Colors.white, w: FontWeight.w700))),
      ]),
      duration: const Duration(milliseconds: 2200),
    ));
}


/// Tiny Flutter logo on the profile picture — shows this screen is the Flutter (native) app.
class FlutterBadge extends StatelessWidget {
  final double size;
  const FlutterBadge({super.key, this.size = 18});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Flutter ऐप',
        child: Container(
          width: size, height: size, padding: EdgeInsets.all(size * .17),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1))]),
          child: const FlutterLogo(),
        ),
      );
}

/// Puts the Flutter badge on the top-left of an avatar.
Widget withFlutterBadge(Widget avatar, double s) => Stack(clipBehavior: Clip.none, children: [avatar, Positioned(left: -2, top: -2, child: FlutterBadge(size: (s * .34).clamp(14, 26).toDouble()))]);

/// Product picture: "asset:momos" keys are bundled in the app (assets/food), http links load from the web.
Widget foodImg(dynamic url, double w, double h, {double r = 14}) {
  final u = (url ?? '').toString();
  final ph = Container(width: w, height: h, color: const Color(0xFFFFF3D6), alignment: Alignment.center, child: Text('🍛', style: TextStyle(fontSize: (w.isFinite ? w : 60) * .4)));
  Widget img;
  if (u.startsWith('asset:')) {
    img = Image.asset('assets/food/${u.substring(6)}.webp', width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
  } else if (u.startsWith('http')) {
    img = Image.network(u, width: w, height: h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph);
  } else {
    img = ph;
  }
  return ClipRRect(borderRadius: BorderRadius.circular(r), child: img);
}
