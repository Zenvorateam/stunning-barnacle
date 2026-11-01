import 'dart:convert';
import 'package:flutter/material.dart';
import 'core.dart';

// ───────────── Admin home ─────────────
class AdminHome extends StatelessWidget {
  final String role;
  const AdminHome({super.key, required this.role});

  @override
  Widget build(BuildContext c) {
    final admin = role == 'admin';
    final tabs = <String, Widget>{
      'Orders': StatusAdmin(table: 'orders', select: '*, order_items(*)', statuses: const ['placed', 'confirmed', 'packed', 'shipped', 'out_for_delivery', 'delivered', 'cancelled'],
          title: (o) => '#${o['id'].toString().substring(0, 8)}  ·  ${money(o['total'] as num)}  ·  ${o['payment_method']}',
          sub: (o) => '${(o['order_items'] as List).map((i) => '${i['qty']}× ${i['name']}').join(', ')}\n${o['address']?['name'] ?? ''}, ${o['address']?['phone'] ?? ''}\n${o['address']?['line1'] ?? ''}, ${o['address']?['city'] ?? ''} ${o['address']?['pincode'] ?? ''}'),
      'Requests': StatusAdmin(table: 'service_requests', select: '*', statuses: const ['pending', 'approved', 'rejected', 'completed', 'withdrawn'],
          title: (r) => '${r['kind']}  ·  order #${r['order_id'].toString().substring(0, 8)}', sub: (r) => '${r['reason']}\n${r['message'] ?? ''}'),
      'Reviews': StatusAdmin(table: 'reviews', select: '*', statuses: const ['pending', 'approved', 'hidden'],
          title: (r) => '${'★' * (r['rating'] as int)}  ${r['user_name']}', sub: (r) => '${r['body']}'),
      if (admin) ...{
        'Products': const RowsAdmin(table: 'products', pk: 'id', order: 'id', label: 'name', sub: 'category', fields: [
          F('name', 'Name'), F('brand', 'Brand'), F('category', 'Category'), F('price', 'Price', 'n'), F('mrp', 'MRP', 'n'), F('stock', 'Stock', 'n'), F('gst_pct', 'GST %', 'n'),
          F('images', 'Image links (comma separated)', 'l'), F('description', 'Description', 'x'), F('active', 'Visible in app', 'b')]),
        'Banners': const RowsAdmin(table: 'banners', pk: 'id', order: 'id', label: 'heading', sub: 'link', fields: [
          F('heading', 'Heading'), F('body', 'Text'), F('button_text', 'Button text'), F('image_url', 'Image link'), F('mobile_image_url', 'Mobile image link'), F('link', 'Link'),
          F('bg_color', 'Background colour (#hex)'), F('text_color', 'Text colour (#hex)'), F('sort', 'Order number', 'n'), F('active', 'Visible', 'b')]),
        'Categories': const RowsAdmin(table: 'categories', pk: 'id', order: 'id', label: 'name', sub: 'emoji', fields: [
          F('name', 'Name'), F('emoji', 'Emoji'), F('bg_color', 'Background colour (#hex)'), F('text_color', 'Text colour (#hex)'), F('sort', 'Order number', 'n'), F('active', 'Visible', 'b')]),
        'Coupons': const RowsAdmin(table: 'coupons', pk: 'code', order: 'code', label: 'code', sub: 'kind', fields: [
          F('code', 'Code'), F('kind', 'Type: percent or flat'), F('value', 'Value', 'n'), F('min_order', 'Minimum order', 'n'), F('usage_limit', 'Total usage limit', 'n'),
          F('per_user_limit', 'Uses per customer', 'n'), F('assigned_email', 'Only for this email (optional)'), F('expires_at', 'Expires (2026-12-31T23:59:00Z)', 'd'), F('active', 'Active', 'b')]),
        'Settings': const RowsAdmin(table: 'app_settings', pk: 'key', order: 'key', label: 'key', sub: '', fields: [F('key', 'Key'), F('value', 'Value (JSON)', 'j')]),
        'Users': const UsersAdmin(),
        'Notify': const NotifyAdmin(),
      },
    };
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(title: Text(admin ? 'Admin panel' : 'Staff panel'), bottom: TabBar(isScrollable: true, tabs: [for (final k in tabs.keys) Tab(text: k)])),
        body: TabBarView(children: tabs.values.toList()),
      ),
    );
  }
}

// ───────────── Generic list with a status dropdown (orders, requests, reviews) ─────────────
class StatusAdmin extends StatefulWidget {
  final String table, select;
  final List<String> statuses;
  final String Function(J) title, sub;
  const StatusAdmin({super.key, required this.table, required this.select, required this.statuses, required this.title, required this.sub});
  @override
  State<StatusAdmin> createState() => _StatusState();
}

class _StatusState extends State<StatusAdmin> {
  List<J> rows = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try { rows = List<J>.from(await sb.from(widget.table).select(widget.select).order('created_at', ascending: false).limit(200)); }
    catch (x) { if (mounted) snack(context, errText(x)); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> setStatus(J r, String s) async {
    try { await sb.from(widget.table).update({'status': s}).eq('id', r['id']); setState(() => r['status'] = s); }
    catch (x) { if (mounted) snack(context, errText(x)); }
  }

  @override
  Widget build(BuildContext c) => loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(10), children: [
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Nothing here yet'))),
          for (final r in rows)
            Card(
                color: Colors.white, elevation: 0,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.title(r), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(widget.sub(r)),
                      DropdownButton<String>(isExpanded: true, value: widget.statuses.contains(r['status']) ? r['status'] as String : null,
                          items: [for (final s in widget.statuses) DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' ')))], onChanged: (v) => setStatus(r, v!)),
                    ]))),
        ]),
      );
}

// ───────────── Generic add / edit / delete screen for any table ─────────────
class F {
  final String k, label, t; // t: t text, x long text, n number, b on/off, l list, d date, j json
  const F(this.k, this.label, [this.t = 't']);
}

class RowsAdmin extends StatefulWidget {
  final String table, pk, order, label, sub;
  final List<F> fields;
  const RowsAdmin({super.key, required this.table, required this.pk, required this.order, required this.label, required this.sub, required this.fields});
  @override
  State<RowsAdmin> createState() => _RowsState();
}

class _RowsState extends State<RowsAdmin> {
  List<J> rows = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try { rows = List<J>.from(await sb.from(widget.table).select().order(widget.order, ascending: false)); }
    catch (x) { if (mounted) snack(context, errText(x)); }
    if (mounted) setState(() => loading = false);
  }

  String show(dynamic v, String t) => v == null ? '' : t == 'l' ? (v as List).join(', ') : t == 'j' ? jsonEncode(v) : '$v';

  Future<void> edit(J? row) async {
    final cs = {for (final f in widget.fields) f.k: TextEditingController(text: show(row?[f.k], f.t))};
    final bs = {for (final f in widget.fields.where((f) => f.t == 'b')) f.k: (row?[f.k] ?? true) as bool};
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.fields)
              f.t == 'b'
                  ? SwitchListTile(title: Text(f.label), value: bs[f.k]!, onChanged: (v) => set(() => bs[f.k] = v))
                  : Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: cs[f.k], keyboardType: f.t == 'n' ? TextInputType.number : TextInputType.text, maxLines: (f.t == 'x' || f.t == 'j') ? 4 : 1, decoration: InputDecoration(labelText: f.label))),
            FilledButton(onPressed: () async {
              try {
                final d = <String, dynamic>{};
                for (final f in widget.fields) {
                  final s = cs[f.k]!.text.trim();
                  if (f.t == 'b') { d[f.k] = bs[f.k]; }
                  else if (f.t == 'n') { if (s.isNotEmpty) d[f.k] = num.parse(s); }
                  else if (f.t == 'l') { d[f.k] = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(); }
                  else if (f.t == 'd') { d[f.k] = s.isEmpty ? null : s; }
                  else if (f.t == 'j') { d[f.k] = jsonDecode(s); }
                  else { d[f.k] = s; }
                }
                if (row == null) { await sb.from(widget.table).insert(d); }
                else { await sb.from(widget.table).update(d).eq(widget.pk, row[widget.pk]); }
                if (ctx.mounted) Navigator.pop(ctx);
                await load();
              } catch (x) { if (ctx.mounted) snack(ctx, errText(x)); }
            }, child: const Text('Save')),
          ])))));
  }

  Future<void> del(J r) async {
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
          title: const Text('Delete this?'),
          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))]));
    if (ok != true) return;
    try { await sb.from(widget.table).delete().eq(widget.pk, r[widget.pk]); await load(); }
    catch (x) { if (mounted) snack(context, '${errText(x)}  (tip: switch it off instead of deleting)'); }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(onPressed: () => edit(null), backgroundColor: lime, child: const Icon(Icons.add, color: green)),
        body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
          onRefresh: load,
          child: ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 90), children: [
            for (final r in rows)
              Card(
                  color: Colors.white, elevation: 0,
                  child: ListTile(
                      title: Text('${r[widget.label] ?? ''}'), subtitle: widget.sub.isEmpty ? null : Text('${r[widget.sub] ?? ''}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => del(r)), onTap: () => edit(r))),
          ]),
        ),
      );
}

// ───────────── Users: roles and Prime ─────────────
class UsersAdmin extends StatefulWidget {
  const UsersAdmin({super.key});
  @override
  State<UsersAdmin> createState() => _UsersState();
}

class _UsersState extends State<UsersAdmin> {
  List<J> rows = [];
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { rows = List<J>.from(await sb.from('profiles').select().order('created_at', ascending: false).limit(300)); }
    catch (x) { if (mounted) snack(context, errText(x)); }
    if (mounted) setState(() {});
  }

  Future<void> act(J u, String a) async {
    final d = <String, dynamic>{};
    if (a.startsWith('role:')) d['role'] = a.substring(5);
    if (a == 'prime') d['prime_until'] = DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
    if (a == 'noprime') d['prime_until'] = null;
    if (a == 'block') d['blocked'] = !(u['blocked'] == true);
    try { await sb.from('profiles').update(d).eq('id', u['id']); await load(); }
    catch (x) { if (mounted) snack(context, errText(x)); }
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.all(10), children: [
          for (final u in rows)
            Card(
                color: Colors.white, elevation: 0,
                child: ListTile(
                    title: Text('${u['name'] ?? ''}  (${u['role']})'),
                    subtitle: Text('${u['email'] ?? ''}${u['prime_until'] != null ? '\nPrime until ${u['prime_until'].toString().substring(0, 10)}' : ''}${u['blocked'] == true ? '\nBLOCKED' : ''}'),
                    trailing: PopupMenuButton<String>(onSelected: (a) => act(u, a), itemBuilder: (_) => const [
                          PopupMenuItem(value: 'role:admin', child: Text('Make admin')),
                          PopupMenuItem(value: 'role:staff', child: Text('Make staff')),
                          PopupMenuItem(value: 'role:customer', child: Text('Make customer')),
                          PopupMenuItem(value: 'prime', child: Text('Give Prime (30 days)')),
                          PopupMenuItem(value: 'noprime', child: Text('Remove Prime')),
                          PopupMenuItem(value: 'block', child: Text('Block / unblock')),
                        ]))),
        ]),
      );
}

// ───────────── Send notification ─────────────
class NotifyAdmin extends StatefulWidget {
  const NotifyAdmin({super.key});
  @override
  State<NotifyAdmin> createState() => _NotifyState();
}

class _NotifyState extends State<NotifyAdmin> {
  final t = TextEditingController(), b = TextEditingController(), i = TextEditingController(), e = TextEditingController();
  String target = 'all';
  bool busy = false;

  Future<void> send() async {
    if (t.text.trim().isEmpty) { snack(context, 'Write a title'); return; }
    setState(() => busy = true);
    try {
      final d = <String, dynamic>{'title': t.text.trim(), 'body': b.text.trim(), 'image_url': i.text.trim(), 'target': target, 'created_by': sb.auth.currentUser!.id};
      if (target == 'user') {
        final u = await sb.from('profiles').select('id').eq('email', e.text.trim()).maybeSingle();
        if (u == null) throw 'No user with this email';
        d['user_id'] = u['id'];
      }
      await sb.from('notifications').insert(d);
      t.clear(); b.clear(); i.clear();
      if (mounted) snack(context, 'Notification sent');
    } catch (x) { if (mounted) snack(context, errText(x)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: t, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 12),
        TextField(controller: b, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
        const SizedBox(height: 12),
        TextField(controller: i, decoration: const InputDecoration(labelText: 'Image link (optional)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: target, decoration: const InputDecoration(labelText: 'Send to'), items: const [
          DropdownMenuItem(value: 'all', child: Text('Everyone')), DropdownMenuItem(value: 'prime', child: Text('Prime members')), DropdownMenuItem(value: 'user', child: Text('One customer (email)'))],
            onChanged: (v) => setState(() => target = v!)),
        if (target == 'user') Padding(padding: const EdgeInsets.only(top: 12), child: TextField(controller: e, decoration: const InputDecoration(labelText: 'Customer email'))),
        const SizedBox(height: 20),
        FilledButton(onPressed: busy ? null : send, child: Text(busy ? 'Sending…' : 'Send notification')),
        const Padding(padding: EdgeInsets.only(top: 12), child: Text('Shows in every customer\'s Alerts tab. Phone push (when the app is closed) needs Firebase, which comes next.', style: TextStyle(color: Colors.black54, fontSize: 12))),
      ]);
}
