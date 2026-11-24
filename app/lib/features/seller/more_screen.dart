import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';
import '../auth/change_password_screen.dart';
import 'board.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'staff_screen.dart';

/// Everything else: products and prices, reports, store settings, staff, account.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, required this.board});
  final Board board;
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final u = session.user!;
    Widget tile(IconData icon, String title, String? sub, VoidCallback onTap) => ListTile(
          leading: Icon(icon, color: C.navy),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          AppCard(
            child: Row(children: [
              Image.asset('assets/brand/badge.png', width: 56, height: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('${u.isOwner ? 'Owner' : 'Staff'} · ${u.phone}', style: const TextStyle(color: C.muted)),
                ]),
              ),
            ]),
          ),
          if (u.isOwner) ...[
            const SectionTitle('Store'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                tile(Icons.propane_tank_outlined, 'Products & prices', 'Prices, stock, show/hide', () => _push(const ProductsScreen())),
                const Divider(),
                tile(Icons.bar_chart, 'Reports', 'Sales, collections, utang', () => _push(const ReportsScreen())),
                const Divider(),
                tile(Icons.storefront_outlined, 'Store settings', 'Open/closed, GCash, delivery fee', () => _push(const SettingsScreen())),
                const Divider(),
                tile(Icons.badge_outlined, 'Staff & riders', 'Add or turn off store accounts', () => _push(const StaffScreen())),
              ]),
            ),
          ],
          const SectionTitle('This phone'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListenableBuilder(
                listenable: widget.board,
                builder: (context, _) => SwitchListTile(
                  secondary: const Icon(Icons.light_mode_outlined, color: C.navy),
                  title: const Text('Keep screen on', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('So new orders always ring at the store'),
                  value: widget.board.keepAwake,
                  onChanged: widget.board.setKeepAwake,
                ),
              ),
              const Divider(),
              tile(Icons.share_outlined, 'Share the app with customers', AppConfig.siteOrigin.replaceFirst('https://', ''), () {
                SharePlus.instance.share(ShareParams(
                  text: 'Order gasul from Habhab LPG Trading! Download our app (Android): ${AppConfig.siteOrigin}',
                ));
              }),
              const Divider(),
              tile(Icons.lock_outline, 'Change password', null, () => _push(const ChangePasswordScreen())),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: C.red),
                title: const Text('Sign out', style: TextStyle(color: C.red, fontWeight: FontWeight.w600)),
                onTap: () async {
                  if (await confirmDialog(context, title: 'Sign out?', message: 'New orders will not ring on this phone until you sign in again.', confirm: 'Sign out')) {
                    await session.logout();
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Center(child: Text('Habhab LPG app $_version', style: const TextStyle(color: C.muted, fontSize: 12))),
        ],
      ),
    );
  }
}
