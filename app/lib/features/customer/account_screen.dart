import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/launch.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/widgets.dart';
import '../auth/change_password_screen.dart';

/// Customer account: name, address and map pin, password, contact the store, sign out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with Loads<AccountScreen, Customer> {
  String _version = '';
  String? _storePhone;

  @override
  void initState() {
    super.initState();
    reload();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
    session.api.get('/store').then((r) {
      if (mounted) setState(() => _storePhone = StoreInfo.fromJson(r['store'] as Json).phone);
    }).catchError((_) {});
  }

  @override
  Future<Customer> fetch() async => Customer.fromJson((await session.api.get('/me/profile'))['profile'] as Json);

  Future<void> _editAddress(Customer c) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _EditAddressScreen(c)));
    if (saved == true) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final phone = _storePhone ?? AppConfig.defaultStorePhone;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: loadBody((c) => ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            children: [
              AppCard(
                child: Row(children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: C.navyTint,
                    child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.navy)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(c.phone ?? session.user?.phone ?? '', style: const TextStyle(color: C.muted)),
                    ]),
                  ),
                ]),
              ),
              const SectionTitle('Delivery address'),
              AppCard(
                onTap: () => _editAddress(c),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c.address ?? 'No address yet', style: const TextStyle(fontWeight: FontWeight.w600))),
                    const Icon(Icons.edit_outlined, color: C.navy),
                  ]),
                  if (c.landmark != null) Text('Landmark: ${c.landmark}', style: const TextStyle(color: C.muted)),
                  const SizedBox(height: 8),
                  if (c.hasPin)
                    SpotMap(lat: c.lat!, lng: c.lng!, height: 150)
                  else
                    const NoteBanner(text: 'No map pin yet. Tap here to pin your house so the rider finds you fast.'),
                ]),
              ),
              const SectionTitle('Store'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ListTile(leading: const Icon(Icons.call_outlined, color: C.navy), title: const Text('Call the store'), subtitle: Text(phone), onTap: () => Launch.call(phone)),
                  const Divider(),
                  ListTile(leading: const Icon(Icons.sms_outlined, color: C.navy), title: const Text('Text the store'), onTap: () => Launch.sms(phone)),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.share_outlined, color: C.navy),
                    title: const Text('Share the app with a friend'),
                    onTap: () => SharePlus.instance.share(ShareParams(
                      text: 'Order gasul from Habhab LPG Trading! Download the app: ${AppConfig.siteOrigin}',
                    )),
                  ),
                ]),
              ),
              const SectionTitle('Security'),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline, color: C.navy),
                    title: const Text('Change password'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen())),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: C.red),
                    title: const Text('Sign out', style: TextStyle(color: C.red)),
                    onTap: () async {
                      if (await confirmDialog(context, title: 'Sign out?', confirm: 'Sign out')) await session.logout();
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Center(child: Text('Habhab LPG app $_version', style: const TextStyle(color: C.muted, fontSize: 12))),
            ],
          )),
    );
  }
}

class _EditAddressScreen extends StatefulWidget {
  const _EditAddressScreen(this.c);
  final Customer c;
  @override
  State<_EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends State<_EditAddressScreen> {
  late final _name = TextEditingController(text: widget.c.name);
  late final _address = TextEditingController(text: widget.c.address);
  late final _landmark = TextEditingController(text: widget.c.landmark);
  late PickedSpot? _pin = widget.c.hasPin ? PickedSpot(widget.c.lat!, widget.c.lng!) : null;

  Future<void> _save() async {
    final r = await runAction(
      context,
      () => session.api.patch('/me/profile', {
        'name': _name.text.trim(),
        'address': _address.text.trim(),
        'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        'lat': _pin?.lat,
        'lng': _pin?.lng,
      }),
      done: 'Saved.',
    );
    if (r != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My address')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'House no., street, purok, barangay, town'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _landmark, decoration: const InputDecoration(labelText: 'Landmark (optional)')),
          const SizedBox(height: 12),
          if (_pin != null) ...[SpotMap(lat: _pin!.lat, lng: _pin!.lng, height: 170), const SizedBox(height: 8)],
          OutlinedButton.icon(
            onPressed: () async {
              final p = await MapPickerScreen.open(context, lat: _pin?.lat, lng: _pin?.lng);
              if (p != null) setState(() => _pin = p);
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(_pin == null ? 'Pin my house on the map' : 'Change the pin'),
          ),
          const SizedBox(height: 20),
          BusyButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}
