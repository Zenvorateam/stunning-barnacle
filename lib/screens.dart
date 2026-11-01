import 'package:flutter/material.dart';
import 'config.dart';
import 'core.dart';
import 'admin.dart';

// ───────────── Login / Sign up ─────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final n = TextEditingController(), e = TextEditingController(), p = TextEditingController();
  bool signup = false, busy = false, hide = true;
  String? err;

  Future<void> go() async {
    setState(() { busy = true; err = null; });
    try {
      if (signup) {
        await sb.auth.signUp(email: e.text.trim(), password: p.text, data: {'name': n.text.trim()});
        if (sb.auth.currentSession == null) err = 'Account created. Confirm your email, then log in.';
      } else {
        await sb.auth.signInWithPassword(email: e.text.trim(), password: p.text);
      }
    } catch (x) {
      err = errText(x);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 40),
            Container(
                width: 64, height: 64, alignment: Alignment.center,
                decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(18)),
                child: const Text('R.', style: TextStyle(color: lime, fontSize: 28, fontWeight: FontWeight.w800))),
            const SizedBox(height: 20),
            Text(signup ? 'Create account' : 'Welcome back', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const Text('Good finds, better living', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            if (signup) ...[TextField(controller: n, decoration: const InputDecoration(labelText: 'Full name')), const SizedBox(height: 12)],
            TextField(controller: e, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(
                controller: p, obscureText: hide,
                decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)))),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 20),
            FilledButton(onPressed: busy ? null : go, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(signup ? 'Sign up' : 'Log in')),
            TextButton(onPressed: () => setState(() { signup = !signup; err = null; }), child: Text(signup ? 'Already have an account? Log in' : 'New here? Create account')),
          ]),
        ),
      );
}

// ───────────── Home ─────────────
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeState();
}

class _HomeState extends State<HomeTab> {
  List<J> items = [], banners = [], cats = [];
  String q = '', cat = '';
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      items = List<J>.from(await sb.from('products').select().eq('active', true).order('id', ascending: false));
      for (final p in items) { products[p['id'] as int] = p; }
      banners = List<J>.from(await sb.from('banners').select().eq('active', true).order('sort'));
      cats = List<J>.from(await sb.from('categories').select().eq('active', true).order('sort'));
    } catch (x) {
      if (mounted) snack(context, errText(x));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext c) {
    final list = items.where((p) => (cat.isEmpty || p['category'] == cat) && (q.isEmpty || '${p['name']} ${p['brand']} ${p['category']}'.toLowerCase().contains(q.toLowerCase()))).toList();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(children: [
                    const Text(storeName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ]))),
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search products, brands', prefixIcon: Icon(Icons.search))))),
          if (banners.isNotEmpty)
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 160,
                    child: PageView(controller: PageController(viewportFraction: .92), children: [
                      for (final b in banners)
                        Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: green),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(fit: StackFit.expand, children: [
                              img((b['mobile_image_url'] ?? '').toString().isNotEmpty ? b['mobile_image_url'] : b['image_url']),
                              Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${b['heading'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 6)])),
                                    Text('${b['body'] ?? ''}', style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 6)])),
                                  ])),
                            ])),
                    ]))),
          if (cats.isNotEmpty)
            SliverToBoxAdapter(
                child: SizedBox(
                    height: 48,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      for (final k in <J>[{'name': ''}, ...cats])
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(label: Text(k['name'] == '' ? 'All' : '${k['emoji'] ?? ''} ${k['name']}'), selected: cat == k['name'], onSelected: (_) => setState(() => cat = '${k['name']}'))),
                    ]))),
          if (loading) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty) const SliverFillRemaining(child: Center(child: Text('No products yet')))
          else SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .62, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: list.length,
                  itemBuilder: (c, i) => ProductCard(list[i]))),
        ]),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final J p;
  const ProductCard(this.p, {super.key});
  @override
  Widget build(BuildContext c) {
    final off = (p['mrp'] as num) > 0 ? (100 - (p['price'] as num) * 100 / (p['mrp'] as num)).round() : 0;
    final out = (p['stock'] as int) <= 0;
    return GestureDetector(
      onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ProductScreen(p))),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            img(imgs(p).isEmpty ? null : imgs(p).first),
            if (out) Container(color: Colors.white70, alignment: Alignment.center, child: const Text('Out of stock', style: TextStyle(fontWeight: FontWeight.w700))),
          ])),
          Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  Text(money(p['price'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  if (off > 0) Text(money(p['mrp'] as num), style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black45, fontSize: 12)),
                  if (off > 0) Text('  $off% off', style: const TextStyle(color: Color(0xFFB94C32), fontSize: 12)),
                ]),
              ])),
        ]),
      ),
    );
  }
}

// ───────────── Product page ─────────────
class ProductScreen extends StatefulWidget {
  final J p;
  const ProductScreen(this.p, {super.key});
  @override
  State<ProductScreen> createState() => _ProductState();
}

class _ProductState extends State<ProductScreen> {
  bool liked = false;
  List<J> reviews = [];
  int get id => widget.p['id'] as int;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      liked = (await sb.from('wishlist').select().eq('product_id', id).maybeSingle()) != null;
      reviews = List<J>.from(await sb.from('reviews').select().eq('product_id', id).eq('status', 'approved').order('created_at', ascending: false));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> like() async {
    try {
      if (liked) { await sb.from('wishlist').delete().eq('product_id', id); }
      else { await sb.from('wishlist').insert({'user_id': sb.auth.currentUser!.id, 'product_id': id}); }
      setState(() => liked = !liked);
    } catch (x) { snack(context, errText(x)); }
  }

  @override
  Widget build(BuildContext c) {
    final p = widget.p, im = imgs(p), out = (p['stock'] as int) <= 0;
    return Scaffold(
      appBar: AppBar(actions: [IconButton(icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.red : null), onPressed: like)]),
      body: ListView(children: [
        AspectRatio(aspectRatio: 3 / 4, child: im.isEmpty ? img(null) : PageView(children: [for (final u in im) img(u)])),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['brand']}', style: const TextStyle(color: Colors.black54)),
              Text('${p['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('${money(p['price'] as num)}   ${money(p['mrp'] as num)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text('${p['description'] ?? ''}'),
              const Divider(height: 32),
              const Text('Reviews', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (reviews.isEmpty) const Text('No reviews yet', style: TextStyle(color: Colors.black54)),
              for (final r in reviews)
                ListTile(contentPadding: EdgeInsets.zero, title: Text('${'★' * (r['rating'] as int)}  ${r['user_name']}'), subtitle: Text('${r['body']}')),
            ])),
      ]),
      bottomNavigationBar: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(onPressed: out ? null : () { addToCart(id); snack(context, 'Added to cart'); }, child: Text(out ? 'Out of stock' : 'Add to cart')))),
    );
  }
}

// ───────────── Cart + checkout ─────────────
class CartTab extends StatefulWidget {
  const CartTab({super.key});
  @override
  State<CartTab> createState() => _CartState();
}

class _CartState extends State<CartTab> {
  final cc = TextEditingController();
  String coupon = '';
  num couponOff = 0;

  num subtotal(Map<int, int> m) => m.entries.fold<num>(0, (a, e) => a + ((products[e.key]?['price'] ?? 0) as num) * e.value);

  Future<void> apply(Map<int, int> m) async {
    try {
      final r = await sb.rpc('validate_coupon', params: {'p_code': cc.text.trim(), 'p_subtotal': subtotal(m)});
      setState(() { coupon = cc.text.trim(); couponOff = r as num; });
      if (mounted) snack(context, 'Coupon applied');
    } catch (x) {
      setState(() { coupon = ''; couponOff = 0; });
      if (mounted) snack(context, errText(x));
    }
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: ValueListenableBuilder<Map<int, int>>(
          valueListenable: cart,
          builder: (c, m, _) {
            if (m.isEmpty) return const Center(child: Text('Your cart is empty'));
            final sub = subtotal(m);
            return Column(children: [
              const Padding(padding: EdgeInsets.all(16), child: Align(alignment: Alignment.centerLeft, child: Text('Cart', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)))),
              Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final e in m.entries)
                  if (products[e.key] != null)
                    Card(
                        color: Colors.white, elevation: 0,
                        child: ListTile(
                            leading: SizedBox(width: 52, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: img(imgs(products[e.key]!).isEmpty ? null : imgs(products[e.key]!).first))),
                            title: Text('${products[e.key]!['name']}', maxLines: 1),
                            subtitle: Text(money((products[e.key]!['price'] as num) * e.value)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => addToCart(e.key, -1)),
                              Text('${e.value}'),
                              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => addToCart(e.key)),
                            ]))),
                Row(children: [
                  Expanded(child: TextField(controller: cc, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Coupon code'))),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => apply(m), child: const Text('Apply')),
                ]),
              ])),
              Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal'), Text(money(sub))]),
                    if (couponOff > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Coupon $coupon'), Text('- ${money(couponOff)}')]),
                    const Text('Delivery and member discounts are added at checkout', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CheckoutScreen(coupon))), child: const Text('Checkout')),
                  ])),
            ]);
          },
        ),
      );
}

class CheckoutScreen extends StatefulWidget {
  final String coupon;
  const CheckoutScreen(this.coupon, {super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends State<CheckoutScreen> {
  final f = {for (final k in ['name', 'phone', 'line1', 'city', 'state', 'pincode']) k: TextEditingController()};
  bool busy = false;

  Future<void> place() async {
    if (f.values.any((t) => t.text.trim().isEmpty)) { snack(context, 'Please fill the full address'); return; }
    setState(() => busy = true);
    try {
      await sb.rpc('place_order', params: {
        'p_items': [for (final e in cart.value.entries) {'id': e.key, 'qty': e.value}],
        'p_address': {for (final e in f.entries) e.key: e.value.text.trim()},
        'p_method': 'cod',
        'p_coupon': widget.coupon,
      });
      cart.value = {};
      if (mounted) { Navigator.popUntil(context, (r) => r.isFirst); snack(context, 'Order placed 🎉'); }
    } catch (x) {
      if (mounted) { setState(() => busy = false); snack(context, errText(x)); }
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Delivery address')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final e in f.entries) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: e.value, decoration: InputDecoration(labelText: e.key == 'line1' ? 'Address' : e.key[0].toUpperCase() + e.key.substring(1)))),
          const ListTile(leading: Icon(Icons.payments_outlined), title: Text('Cash on delivery'), subtitle: Text('Online payment (Razorpay) comes next')),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : place, child: Text(busy ? 'Placing…' : 'Place order')),
        ]),
      );
}

// ───────────── Orders ─────────────
class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersState();
}

class _OrdersState extends State<OrdersTab> {
  List<J> orders = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try { orders = List<J>.from(await sb.from('orders').select('*, order_items(*)').eq('user_id', sb.auth.currentUser!.id).order('created_at', ascending: false)); }
    catch (x) { if (mounted) snack(context, errText(x)); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> cancel(J o) async {
    try { await sb.rpc('cancel_order', params: {'p_id': o['id']}); await load(); }
    catch (x) { if (mounted) snack(context, errText(x)); }
  }

  Future<void> request(J o, String kind) async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
          title: Text('Request $kind'),
          content: TextField(controller: t, decoration: const InputDecoration(hintText: 'Reason')),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Close')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send'))]));
    if (ok != true || t.text.trim().isEmpty) return;
    try {
      await sb.from('service_requests').insert({'order_id': o['id'], 'user_id': sb.auth.currentUser!.id, 'kind': kind, 'reason': t.text.trim()});
      if (mounted) snack(context, 'Request sent');
    } catch (x) { if (mounted) snack(context, errText(x)); }
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(12), children: [
            const Padding(padding: EdgeInsets.all(4), child: Text('My orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            if (orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No orders yet'))),
            for (final o in orders)
              Card(
                  color: Colors.white, elevation: 0,
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('#${o['id'].toString().substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Chip(label: Text('${o['status']}'.replaceAll('_', ' ')), backgroundColor: lime),
                        ]),
                        for (final i in (o['order_items'] as List)) Text('${i['qty']} × ${i['name']}'),
                        const SizedBox(height: 6),
                        Text('Total ${money(o['total'] as num)}  ·  ${o['payment_method'] == 'cod' ? 'Cash on delivery' : 'Paid online'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (o['status'] == 'out_for_delivery') Text('Delivery OTP: ${o['otp']}'),
                        Wrap(spacing: 8, children: [
                          if (['placed', 'confirmed'].contains(o['status'])) OutlinedButton(onPressed: () => cancel(o), child: const Text('Cancel order')),
                          if (['packed', 'shipped', 'out_for_delivery'].contains(o['status'])) OutlinedButton(onPressed: () => request(o, 'cancel'), child: const Text('Request cancel')),
                          if (o['status'] == 'delivered') OutlinedButton(onPressed: () => request(o, 'return'), child: const Text('Return')),
                          if (o['status'] == 'delivered') OutlinedButton(onPressed: () => request(o, 'refund'), child: const Text('Refund')),
                          if (o['status'] == 'delivered') OutlinedButton(onPressed: () => reviewDialog(o), child: const Text('Review')),
                        ]),
                      ]))),
          ]),
        ),
      );

  Future<void> reviewDialog(J o) async {
    final items = (o['order_items'] as List).cast<J>();
    int pid = items.first['product_id'] as int, stars = 5;
    final t = TextEditingController();
    await showDialog(context: context, builder: (d) => StatefulBuilder(builder: (d, set) => AlertDialog(
          title: const Text('Write a review'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<int>(isExpanded: true, value: pid, items: [for (final i in items) DropdownMenuItem(value: i['product_id'] as int, child: Text('${i['name']}', overflow: TextOverflow.ellipsis))], onChanged: (v) => set(() => pid = v!)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var s = 1; s <= 5; s++) IconButton(icon: Icon(s <= stars ? Icons.star : Icons.star_border, color: Colors.amber), onPressed: () => set(() => stars = s))]),
            TextField(controller: t, maxLines: 3, decoration: const InputDecoration(hintText: 'Your review')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
            FilledButton(onPressed: () async {
              try {
                await sb.rpc('submit_review', params: {'p_product': pid, 'p_rating': stars, 'p_body': t.text.trim()});
                if (d.mounted) Navigator.pop(d);
                if (mounted) snack(context, 'Thanks! Your review will show after approval.');
              } catch (x) { if (mounted) snack(context, errText(x)); }
            }, child: const Text('Submit'))])));
  }
}

// ───────────── Notifications ─────────────
class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});
  @override
  State<AlertsTab> createState() => _AlertsState();
}

class _AlertsState extends State<AlertsTab> {
  List<J> list = [];
  Set<String> read = {};
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      list = List<J>.from(await sb.from('notifications').select().order('created_at', ascending: false).limit(50));
      read = (await sb.from('notification_reads').select('notification_id')).map<String>((r) => r['notification_id'] as String).toSet();
      final uid = sb.auth.currentUser!.id;
      final fresh = [for (final n in list) if (!read.contains(n['id'])) {'user_id': uid, 'notification_id': n['id']}];
      if (mounted) setState(() {});
      if (fresh.isNotEmpty) await sb.from('notification_reads').upsert(fresh);
    } catch (x) { if (mounted) snack(context, errText(x)); }
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(padding: const EdgeInsets.all(12), children: [
            const Padding(padding: EdgeInsets.all(4), child: Text('Alerts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No notifications'))),
            for (final n in list)
              Card(
                  color: Colors.white, elevation: 0,
                  child: ListTile(
                      leading: Icon(Icons.circle, size: 10, color: read.contains(n['id']) ? Colors.transparent : Colors.red),
                      title: Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${n['body']}'))),
          ]),
        ),
      );
}

// ───────────── Profile ─────────────
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileState();
}

class _ProfileState extends State<ProfileTab> {
  J? me;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { me = await sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).maybeSingle(); } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> gate() async {
    final role = (me?['role'] ?? 'customer') as String;
    if (role == 'customer') { snack(context, 'This account does not have admin access'); return; }
    final t = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
          title: const Text('Admin access'),
          content: TextField(controller: t, obscureText: true, decoration: const InputDecoration(hintText: 'Access code')),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Open'))]));
    if (ok != true) return;
    if (t.text != adminAccessCode) { if (mounted) snack(context, 'Wrong access code'); return; }
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => AdminHome(role: role)));
  }

  @override
  Widget build(BuildContext c) {
    final prime = me?['prime_until'] != null && DateTime.parse(me!['prime_until']).isAfter(DateTime.now());
    final staff = ['admin', 'staff'].contains(me?['role']);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Card(color: Colors.white, elevation: 0, child: ListTile(leading: const CircleAvatar(backgroundColor: lime, child: Icon(Icons.person, color: green)), title: Text('${me?['name'] ?? ''}'), subtitle: Text(sb.auth.currentUser?.email ?? ''))),
        if (prime) const Card(color: lime, elevation: 0, child: ListTile(leading: Icon(Icons.workspace_premium), title: Text('Realistic Prime is active'))),
        if (staff) Card(color: Colors.white, elevation: 0, child: ListTile(leading: const Icon(Icons.admin_panel_settings_outlined), title: const Text('Admin panel'), trailing: const Icon(Icons.chevron_right), onTap: gate)),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => sb.auth.signOut(), child: const Text('Log out')),
      ]),
    );
  }
}
