import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First time: register the shop (one category; more need admin approval).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final shop = TextEditingController(), addr = TextEditingController();
  String store = 'food';
  bool busy = false;
  String err = '';

  Future<void> save() async {
    if (shop.text.trim().length < 2) return setState(() => err = 'दुकान का नाम लिखिए');
    if (addr.text.trim().length < 4) return setState(() => err = 'दुकान का पता लिखिए');
    setState(() { busy = true; err = ''; });
    try {
      await Api.rpc('vendor_register', {'p_shop': shop.text.trim(), 'p_address': addr.text.trim(), 'p_store': store});
      if (mounted) goNext(context);
    } catch (e) {
      setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint, filled: true, fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFECD9A8), width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: HF.gold, width: 2)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: HF.bg,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 30), children: [
            const Text('🏪', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text('अपनी दुकान जोड़ें', style: HF.num(28)),
            Text('एडमिन मंज़ूरी के बाद दुकान खुल जाएगी', style: HF.hi(14, color: HF.mut, w: FontWeight.w600)),
            const SizedBox(height: 22),
            TextField(controller: shop, style: HF.hi(17, w: FontWeight.w700), decoration: deco('दुकान का नाम')),
            const SizedBox(height: 10),
            TextField(controller: addr, maxLines: 2, style: HF.hi(16, w: FontWeight.w600), decoration: deco('पूरा पता (गली, इलाका)')),
            const SizedBox(height: 18),
            Text('आपकी दुकान किस कैटेगरी की है?', style: HF.hi(15, w: FontWeight.w800)),
            Text('एक दुकान = एक कैटेगरी। दूसरी चाहिए तो बाद में एडमिन से माँगें।', style: HF.hi(12, color: HF.mut)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in stores)
                GestureDetector(
                  onTap: () => setState(() => store = s[0]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: store == s[0] ? HF.goldLight : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: store == s[0] ? HF.goldDeep : const Color(0xFFECD9A8), width: 2)),
                    child: Text('${s[1]} ${s[2]}', style: HF.hi(14.5, w: FontWeight.w800)),
                  ),
                ),
            ]),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err, style: HF.hi(13.5, color: HF.bad))),
            const SizedBox(height: 22),
            GoldButton(busy ? 'एक पल…' : 'दुकान जोड़ें', onTap: busy ? null : save),
          ]),
        ),
      );
}
