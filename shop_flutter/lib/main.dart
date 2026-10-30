import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'push.dart';
import 'theme.dart';
import 'screens/login.dart';
import 'screens/home.dart';
import 'screens/register.dart';

const supabaseUrl = 'https://pboelnbjgyllqqlkqaqm.supabase.co';
// publishable (public) key — safe to ship in the app
const supabaseKey = 'sb_publishable_v7qyttkDD2DtFpSGSWAxrw__9K80eRz';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
    Api.markReady();
  } catch (_) {}
  await Push.init();
  runApp(const ShopApp());
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'Happy Food Shop', debugShowCheckedModeBanner: false, theme: HF.theme(), home: const Splash());
}

/// Where to go after the splash: login → (shop registration) → shop home.
Future<void> goNext(BuildContext context) async {
  Widget next;
  if (!Api.signedIn) {
    next = const LoginScreen();
  } else {
    try {
      final me = await Api.me();
      next = me['registered'] == true ? const ShopHome() : const RegisterScreen();
    } catch (_) {
      next = const ShopHome();
    }
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(PageRouteBuilder(pageBuilder: (_, __, ___) => next, transitionsBuilder: (_, a, __, w) => FadeTransition(opacity: a, child: w)), (_) => false);
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
    Future.delayed(const Duration(milliseconds: 1700), () { if (mounted) goNext(context); });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const icons = ['🧾', '🛒', '🍛', '💰', '🖨️', '⭐'];
    return Scaffold(
      backgroundColor: HF.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 240,
            height: 240,
            child: Stack(alignment: Alignment.center, children: [
              Container(width: 210, height: 210, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: HF.gold.withValues(alpha: .35)))),
              AnimatedBuilder(
                animation: c,
                builder: (_, __) => Transform.rotate(
                  angle: -c.value * 6.283,
                  child: Stack(alignment: Alignment.center, children: [
                    for (var i = 0; i < icons.length; i++)
                      Transform.translate(offset: Offset.fromDirection(i * 6.283 / icons.length, 105), child: Transform.rotate(angle: c.value * 6.283, child: Text(icons[i], style: const TextStyle(fontSize: 26)))),
                  ]),
                ),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF6D27A), Color(0xFFC8912A)]), boxShadow: [BoxShadow(color: Color(0x8CE2B04A), blurRadius: 44)]),
                child: const Center(child: Text('🏪', style: TextStyle(fontSize: 50))),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          RichText(text: TextSpan(style: HF.num(40), children: [const TextSpan(text: 'Happy '), TextSpan(text: 'Food', style: HF.num(40, color: HF.goldDeep))])),
          const SizedBox(height: 6),
          Text('दुकान पार्टनर', style: HF.hi(15, color: HF.mut)),
        ]),
      ),
    );
  }
}
