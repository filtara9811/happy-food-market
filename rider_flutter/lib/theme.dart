import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours and type taken from the HTML prototype (partner panel, light mode).
class HF {
  static const gold = Color(0xFFE2B04A);
  static const goldDeep = Color(0xFFA8741B);
  static const goldLight = Color(0xFFFDE68A);
  static const ink = Color(0xFF1A1305);
  static const bg = Color(0xFFF6F1E7);
  static const card = Color(0xFFFFFFFF);
  static const card2 = Color(0xFFF1EADB);
  static const line = Color(0x1F1A1305);
  static const tx = Color(0xFF1A1A24);
  static const mut = Color(0xFF6B6B7B);
  static const ok = Color(0xFF16A34A);
  static const bad = Color(0xFFDC2626);
  static const heroTop = Color(0xFF15110A);
  static const heroBottom = Color(0xFF3A2A0C);

  static TextStyle num(double size, {Color color = tx, FontWeight w = FontWeight.w900}) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: w, color: color, height: 1.1);
  static TextStyle hi(double size, {Color color = tx, FontWeight w = FontWeight.w700}) =>
      GoogleFonts.mukta(fontSize: size, fontWeight: w, color: color, height: 1.25);

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, primary: goldDeep, surface: card),
        textTheme: GoogleFonts.muktaTextTheme(),
      );

  static const goldGrad = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [goldLight, Color(0xFFE2A92C)]);
}

String rupee(num n) {
  final s = n.round().toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

String hm(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}
