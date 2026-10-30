import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Mobile number → 4-digit OTP → (first time) name. Same server login as the other apps.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int step = 0; // 0 phone, 1 otp, 2 name
  final phone = TextEditingController(), otp = TextEditingController(), name = TextEditingController(), city = TextEditingController();
  bool busy = false;
  String err = '';
  int left = 0;
  Timer? t;
  bool demo = false;

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  void startTimer() {
    left = 30;
    t?.cancel();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => left = left > 0 ? left - 1 : 0);
      if (left == 0) t?.cancel();
    });
  }

  String code(Map d) {
    switch (d['code']) {
      case 'rate_limited':
        return 'बहुत बार OTP माँगा — 10 मिनट बाद कोशिश करें';
      case 'bad_phone':
        return 'सही 10 अंकों का नंबर डालें';
      case 'wrong_code':
        return 'OTP गलत है${d['left'] != null ? ' — ${d['left']} कोशिश बाकी' : ''}';
      case 'expired':
        return 'OTP पुराना हो गया — दोबारा भेजें';
      case 'too_many_tries':
        return 'बहुत गलत कोशिशें — नया OTP मँगाएँ';
      default:
        return 'कुछ गड़बड़ हुई (${d['code'] ?? ''})';
    }
  }

  Future<void> send() async {
    final p = phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(p)) return setState(() => err = 'सही 10 अंकों का मोबाइल नंबर डालें');
    setState(() { busy = true; err = ''; });
    try {
      final d = await Api.otp({'action': 'send', 'phone': p});
      if (d['ok'] != true) { setState(() => err = code(d)); return; }
      demo = d['demo'] == true;
      setState(() => step = 1);
      startTimer();
    } catch (e) {
      setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (otp.text.length < 4) return setState(() => err = '4 अंकों का OTP डालें');
    setState(() { busy = true; err = ''; });
    try {
      final d = await Api.otp({'action': 'verify', 'phone': phone.text, 'code': otp.text});
      if (d['ok'] != true) { setState(() { err = code(d); otp.clear(); }); return; }
      await Api.signInWithHash(d['token_hash']);
      final prof = await Api.myProfile();
      if ((prof['name'] ?? '').toString().isEmpty) { setState(() => step = 2); return; }
      if (mounted) goNext(context);
    } catch (e) {
      setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveName() async {
    if (name.text.trim().length < 2) return setState(() => err = 'अपना नाम लिखिए');
    setState(() { busy = true; err = ''; });
    try {
      await Api.rpc('ensure_profile', {'p_name': name.text.trim(), 'p_city': city.text.trim().isEmpty ? 'Delhi' : city.text.trim()});
      if (mounted) goNext(context);
    } catch (e) {
      setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFECD9A8), width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFE8761A), width: 2)),
      );

  @override
  Widget build(BuildContext context) {
    final titles = ['मोबाइल नंबर डालें', 'OTP डालें', 'आपका नाम क्या है?'];
    final subs = ['हम आपको 4 अंकों का OTP भेजेंगे', 'OTP भेजा गया +91 ${phone.text}', 'पहली बार आए हैं — स्वागत है 🎉'];
    return Scaffold(
      backgroundColor: HF.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 30), children: [
          Row(children: [
            Container(width: 58, height: 58, alignment: Alignment.center, decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), gradient: const LinearGradient(colors: [Color(0xFFFFF3CF), Color(0xFFF2C55C)])), child: const Text('🛵', style: TextStyle(fontSize: 30))),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RichText(text: TextSpan(style: HF.num(28), children: [const TextSpan(text: 'Happy '), TextSpan(text: 'Food', style: HF.num(28, color: HF.goldDeep))])),
              Text('डिलीवरी पार्टनर ऐप', style: HF.hi(13, color: HF.mut)),
            ]),
          ]),
          const SizedBox(height: 40),
          if (step > 0)
            Align(alignment: Alignment.centerLeft, child: GestureDetector(onTap: () => setState(() { step = step == 2 ? 2 : 0; err = ''; }), child: Container(width: 44, height: 44, decoration: const BoxDecoration(color: Color(0xFFEFE6D3), shape: BoxShape.circle), child: const Icon(Icons.chevron_left)))),
          const SizedBox(height: 10),
          Text(titles[step], style: HF.num(27)),
          const SizedBox(height: 4),
          Text(subs[step], style: HF.hi(14.5, color: HF.mut, w: FontWeight.w600)),
          const SizedBox(height: 20),
          if (step == 0)
            Row(children: [
              Container(height: 58, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFECD9A8), width: 2)), child: Text('🇮🇳 +91', style: HF.hi(16, w: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: phone, keyboardType: TextInputType.phone, maxLength: 10, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: HF.hi(18, w: FontWeight.w800), decoration: deco('मोबाइल नंबर').copyWith(counterText: ''), onSubmitted: (_) => send())),
            ]),
          if (step == 1)
            TextField(controller: otp, autofocus: true, keyboardType: TextInputType.number, maxLength: 4, textAlign: TextAlign.center, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: HF.num(30).copyWith(letterSpacing: 18), decoration: deco('••••').copyWith(counterText: ''), onChanged: (v) { if (v.length == 4) verify(); }),
          if (step == 2) ...[
            TextField(controller: name, autofocus: true, style: HF.hi(17, w: FontWeight.w700), decoration: deco('जैसे: राहुल शर्मा')),
            const SizedBox(height: 10),
            TextField(controller: city, style: HF.hi(17, w: FontWeight.w700), decoration: deco('इलाका (जैसे: सदर बाज़ार, दिल्ली)')),
          ],
          if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err, style: HF.hi(13.5, color: HF.bad))),
          const SizedBox(height: 16),
          GoldButton(busy ? 'एक पल…' : ['OTP भेजें', 'वेरिफ़ाई करें और लॉग-इन', 'आगे →'][step], onTap: busy ? null : [send, verify, saveName][step]),
          if (step == 1) ...[
            const SizedBox(height: 14),
            Center(child: TextButton(onPressed: left > 0 || busy ? null : send, child: Text(left > 0 ? 'OTP दोबारा भेजें 00:${left.toString().padLeft(2, '0')}' : 'OTP दोबारा भेजें', style: HF.hi(14.5, color: left > 0 ? HF.mut : const Color(0xFFE8761A))))),
            if (demo) Center(child: Text('डेमो सर्वर: OTP है 1234', style: HF.hi(12.5, color: HF.mut))),
          ],
          const SizedBox(height: 24),
          Text('आगे बढ़कर आप Happy Food की नियम व शर्तें और प्राइवेसी पॉलिसी से सहमत होते हैं।', textAlign: TextAlign.center, style: HF.hi(12.5, color: HF.mut, w: FontWeight.w600)),
        ]),
      ),
    );
  }
}
