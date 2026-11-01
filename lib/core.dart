import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef J = Map<String, dynamic>;
SupabaseClient get sb => Supabase.instance.client;
const green = Color(0xFF17251F), lime = Color(0xFFD7F76B), cream = Color(0xFFFAF9F5), lilac = Color(0xFFE9E0F4);

final cart = ValueNotifier<Map<int, int>>({});
final products = <int, J>{};

String money(num n) => '₹${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)}';
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
String errText(Object e) => e is PostgrestException ? e.message : (e is AuthException ? e.message : e.toString());
void addToCart(int id, [int q = 1]) {
  final m = {...cart.value};
  m[id] = (m[id] ?? 0) + q;
  if (m[id]! <= 0) m.remove(id);
  cart.value = m;
}

Future<String> myRole() async {
  final u = sb.auth.currentUser;
  if (u == null) return 'customer';
  final r = await sb.from('profiles').select('role').eq('id', u.id).maybeSingle();
  return (r?['role'] ?? 'customer') as String;
}

Widget img(dynamic url, {BoxFit fit = BoxFit.cover}) {
  final ph = Container(color: lilac, child: const Icon(Icons.image_outlined, color: Colors.black26));
  if (url == null || url.toString().isEmpty) return ph;
  return Image.network(url.toString(), fit: fit, errorBuilder: (_, __, ___) => ph);
}
List<String> imgs(J p) => ((p['images'] ?? []) as List).map((e) => e.toString()).toList();
