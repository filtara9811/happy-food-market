import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// First time: become a delivery partner (name + vehicle number). Admin approves (or auto-approve).
class JoinScreen extends StatefulWidget {
  final String name;
  const JoinScreen({super.key, this.name = ''});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final name = TextEditingController(text: widget.name);
  final vehicle = TextEditingController();
  bool busy = false;
  String err = '';

  Future<void> save() async {
    if (name.text.trim().length < 2) return setState(() => err = 'अपना नाम लिखिए');
    if (vehicle.text.trim().length < 4) return setState(() => err = 'गाड़ी का नंबर लिखिए (जैसे DL 3S AB 1234)');
    setState(() { busy = true; err = ''; });
    try {
      await Api.rpc('rider_register', {'p_name': name.text.trim(), 'p_vehicle': vehicle.text.trim()});
      if (mounted) goNext(context);
    } catch (e) {
      setState(() => err = errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration deco(String h) => InputDecoration(hintText: h, filled: true, fillColor: Colors.white, enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFECD9A8), width: 2)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: HF.gold, width: 2)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: HF.bg,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(22, 30, 22, 30), children: [
            const Text('🛵', style: TextStyle(fontSize: 48)),
            Text('डिलीवरी पार्टनर बनें', style: HF.num(28)),
            Text('एडमिन की मंज़ूरी के बाद ऑनलाइन हो सकेंगे', style: HF.hi(14, color: HF.mut, w: FontWeight.w600)),
            const SizedBox(height: 22),
            TextField(controller: name, style: HF.hi(17, w: FontWeight.w700), decoration: deco('आपका नाम')),
            const SizedBox(height: 10),
            TextField(controller: vehicle, textCapitalization: TextCapitalization.characters, style: HF.hi(17, w: FontWeight.w700), decoration: deco('गाड़ी का नंबर')),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err, style: HF.hi(13.5, color: HF.bad))),
            const SizedBox(height: 22),
            GoldButton(busy ? 'एक पल…' : 'पार्टनर बनें', onTap: busy ? null : save),
          ]),
        ),
      );
}
