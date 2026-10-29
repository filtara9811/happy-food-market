import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything the shop app asks the server. All calls go through Supabase RPC functions.
class Api {
  static SupabaseClient get sb => Supabase.instance.client;
  static bool get signedIn => _ready && sb.auth.currentSession != null;
  static bool _ready = false;
  static void markReady() => _ready = true;

  static Future<Map<String, dynamic>> otp(Map<String, dynamic> body) async {
    final r = await sb.functions.invoke('otp', body: body);
    final d = r.data;
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  }

  static Future<void> signInWithHash(String hash) async {
    await sb.auth.verifyOTP(tokenHash: hash, type: OtpType.magiclink);
  }

  static Future<dynamic> rpc(String fn, [Map<String, dynamic>? p]) => sb.rpc(fn, params: p ?? {});

  static Future<Map<String, dynamic>> myProfile() async {
    final d = await rpc('my_profile');
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> me() async {
    final d = await rpc('vendor_me');
    return d is Map<String, dynamic> ? d : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> catalog() async => _list(await rpc('vendor_catalog'));
  static Future<List<Map<String, dynamic>>> orders([int days = 31]) async => _list(await rpc('vendor_orders', {'p_days': days}));

  static List<Map<String, dynamic>> _list(dynamic d) => d is List ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  static Future<void> signOut() => sb.auth.signOut();
}

String errText(Object e) {
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) return 'इंटरनेट चेक कीजिए';
  return s.length > 90 ? s.substring(0, 90) : s;
}

/// Shop categories (same ids as the server and the customer app).
const stores = [
  ['food', '🍛', 'फ़ूड'],
  ['fruits', '🍎', 'फल'],
  ['veg', '🥦', 'सब्ज़ी'],
  ['kirana', '🛒', 'किराना'],
  ['dairy', '🥛', 'डेयरी'],
  ['dry', '🥜', 'ड्राई फ्रूट'],
  ['meat', '🍗', 'मीट'],
];
