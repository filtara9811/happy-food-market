import 'package:flutter/material.dart';

/// Colours and type copied from the HTML prototype's partner panel (light mode, --p-* variables).
class HF {
  static const gold = Color(0xFFE2B04A);
  static const goldDeep = Color(0xFF9A6A10); // --p-gold (light)
  static const goldLight = Color(0xFFFDE68A);
  static const ink = Color(0xFF1A1305);
  static const bg = Color(0xFFF5F1E6); // --p-bg
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFEFE8D6); // --p-card2
  static const line = Color(0x1C000000); // rgba(0,0,0,.11)
  static const tx = Color(0xFF1A1A24);
  static const mut = Color(0xFF585870);
  static const ok = Color(0xFF15803D);
  static const okBright = Color(0xFF22C55E);
  static const bad = Color(0xFFB91C1C);
  static const heroTop = Color(0xFF2A2112);
  static const heroMid = Color(0xFF16120B);
  static const heroBottom = Color(0xFF0B0D14);

  static TextStyle num(double size, {Color color = tx, FontWeight w = FontWeight.w900}) => TextStyle(
      fontFamily: 'Outfit', fontFamilyFallback: const ['Mukta'], fontSize: size, fontWeight: w, color: color, height: 1.1,
      fontVariations: [FontVariation('wght', w.value.toDouble())]);
  static TextStyle hi(double size, {Color color = tx, FontWeight w = FontWeight.w700}) =>
      TextStyle(fontFamily: 'Mukta', fontFamilyFallback: const ['Outfit'], fontSize: size, fontWeight: w, color: color, height: 1.25);

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, primary: goldDeep, surface: card),
        fontFamily: 'Mukta',
      );

  static const goldGrad = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFDE68A), Color(0xFFF2B632)]);
  static const navGrad = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFDE68A), Color(0xFFE2A92C)]);
  // linear-gradient(165deg,#2a2112 0%,#16120b 55%,#0b0d14 100%)
  static const heroGrad = LinearGradient(begin: Alignment(-0.27, -1), end: Alignment(0.27, 1), colors: [heroTop, heroMid, heroBottom], stops: [0, .55, 1]);
  static const avGrad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFCE49D), Color(0xFFB88222)]);
}

String rupee(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return '${neg ? '−' : ''}₹$out';
}

String shortRupee(num n) => n >= 1000 ? '₹${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '₹${n.round()}';

String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

const hiDays = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
