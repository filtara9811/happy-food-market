import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';
import 'screens/home.dart';

const supabaseUrl = 'https://pboelnbjgyllqqlkqaqm.supabase.co';
// publishable (public) key — safe to ship in the app
const supabaseKey = 'sb_publishable_v7qyttkDD2DtFpSGSWAxrw__9K80eRz';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  } catch (_) {
    // offline start is fine — the app works on cached / demo data
  }
  runApp(const RiderApp());
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Happy Food Partner',
      debugShowCheckedModeBanner: false,
      theme: HF.theme(),
      home: const Splash(),
    );
  }
}

class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_, __, ___) => const RiderHome(), transitionsBuilder: (_, a, __, w) => FadeTransition(opacity: a, child: w)));
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const icons = ['🛵', '📦', '🥟', '💰', '🗺️', '⭐'];
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D14),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 210, height: 210, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HF.gold.withOpacity(.25)))),
              AnimatedBuilder(
                animation: c,
                builder: (_, __) => Transform.rotate(
                  angle: -c.value * 6.283,
                  child: Stack(alignment: Alignment.center, children: [
                    for (var i = 0; i < icons.length; i++)
                      Transform.translate(
                        offset: Offset.fromDirection(i * 6.283 / icons.length, 105),
                        child: Transform.rotate(angle: c.value * 6.283, child: Text(icons[i], style: const TextStyle(fontSize: 26))),
                      ),
                  ]),
                ),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)]), boxShadow: [BoxShadow(color: Color(0x8CE2B04A), blurRadius: 44)]),
                child: const Center(child: Text('🛵', style: TextStyle(fontSize: 50))),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          RichText(text: TextSpan(style: HF.num(40, color: Colors.white), children: [const TextSpan(text: 'Happy '), TextSpan(text: 'Food', style: HF.num(40, color: HF.gold))])),
          const SizedBox(height: 6),
          Text('डिलीवरी पार्टनर', style: HF.hi(15, color: Colors.white70)),
        ]),
      ),
    );
  }
}
