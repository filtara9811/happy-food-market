import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api.dart';
import 'push.dart';
import 'theme.dart';
import 'screens/login.dart';
import 'screens/home.dart';
import 'screens/register.dart';
import 'widgets/shop_open.dart';

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

class _SplashState extends State<Splash> {
  @override
  Widget build(BuildContext context) => ShopOpenSplash(onDone: () { if (mounted) goNext(context); });
}
