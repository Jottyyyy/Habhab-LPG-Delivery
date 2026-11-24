import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';

/// Owner: store accounts (riders / helpers). They sign in with their number and a temporary
/// password, then choose their own. Staff can take orders, deliver, use the POS and record
/// payments, but not change prices, settings or see reports.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> with Loads<StaffScreen, List<StaffUser>> {
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<List<StaffUser>> fetch() async => ((await session.api.get('/users'))['users'] as List).map((e) => StaffUser.fromJson(e as Json)).toList();

  Future<void> _showPassword(String name, String phone, String pw) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Login for $name'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Number: $phone'),
            SelectableText('Temporary password: $pw', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('They choose their own password after signing in.', style: TextStyle(color: C.muted)),
          ]),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: 'Habhab LPG app login\nNumber: $phone\nTemporary password: $pw')),
              child: const Text('Copy'),
            ),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(80, 44)), onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add rider / helper'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(80, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await runAction(context, () => session.api.post('/users', {'name': name.text.trim(), 'phone': phone.text.trim(), 'role': 'staff'}));
    if (r == null || !mounted) return;
    final u = StaffUser.fromJson(r['user'] as Json);
    reload(quiet: true);
    await _showPassword(u.name, u.phone, r['temporaryPassword'] as String);
  }

  Future<void> _manage(StaffUser u) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.key_outlined), title: const Text('New temporary password'), onTap: () => Navigator.pop(c, 'reset')),
          if (u.id != session.user?.id)
            ListTile(
              leading: Icon(u.active ? Icons.block : Icons.check_circle_outline, color: u.active ? C.red : C.green),
              title: Text(u.active ? 'Turn off this account' : 'Turn on this account'),
              onTap: () => Navigator.pop(c, 'toggle'),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final body = action == 'reset' ? {'resetPassword': true} : {'active': !u.active};
    final r = await runAction(context, () => session.api.patch('/users/${u.id}', body), done: action == 'toggle' ? 'Saved.' : null);
    if (r == null || !mounted) return;
    reload(quiet: true);
    if (r['temporaryPassword'] is String) await _showPassword(u.name, u.phone, r['temporaryPassword'] as String);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff & riders')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt), label: const Text('Add')),
      body: loadBody((list) => ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            children: [
              const NoteBanner(
                icon: Icons.info_outline,
                color: C.navy,
                tint: C.navyTint,
                text: 'Staff can accept and deliver orders, use the POS and record payments. Only the owner can change prices, settings and see reports.',
              ),
              const SizedBox(height: 10),
              for (final u in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => _manage(u),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Icon(u.role == 'owner' ? Icons.star : Icons.delivery_dining, color: u.active ? C.navy : C.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u.name, style: TextStyle(fontWeight: FontWeight.w700, color: u.active ? C.ink : C.muted)),
                          Text('${u.role == 'owner' ? 'Owner' : 'Staff'} · ${u.phone}', style: const TextStyle(color: C.muted, fontSize: 13)),
                        ]),
                      ),
                      if (!u.active) const Pill('Off', color: C.red, tint: C.redTint),
                    ]),
                  ),
                ),
            ],
          )),
    );
  }
}
