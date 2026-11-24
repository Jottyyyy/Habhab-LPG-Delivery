import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';

/// Owner: open/closed, store contact, GCash details + QR, delivery fee.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with Loads<SettingsScreen, StoreInfo> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _gcashName = TextEditingController();
  final _gcashNumber = TextEditingController();
  final _fee = TextEditingController();
  final _closed = TextEditingController();
  bool _open = true;
  int _qrVersion = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<StoreInfo> fetch() async {
    final s = StoreInfo.fromJson((await session.api.get('/settings'))['settings'] as Json);
    _name.text = s.name;
    _phone.text = s.phone ?? '';
    _address.text = s.address ?? '';
    _gcashName.text = s.gcashName ?? '';
    _gcashNumber.text = s.gcashNumber ?? '';
    _fee.text = toPesoInput(s.deliveryFee);
    _closed.text = s.closedMessage ?? '';
    _open = s.isOpen;
    return s;
  }

  Future<void> _setOpen(bool v) async {
    setState(() => _open = v);
    final r = await runAction(context, () => session.api.patch('/settings', {'isOpen': v}), done: v ? 'Store is OPEN. Customers can order.' : 'Store is CLOSED. Customers cannot order.');
    if (r == null && mounted) setState(() => _open = !v);
  }

  Future<void> _save() async {
    final fee = parsePeso(_fee.text.trim().isEmpty ? '0' : _fee.text);
    if (fee == null) {
      showSnack(context, 'Check the delivery fee.', error: true);
      return;
    }
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    await runAction(
      context,
      () => session.api.patch('/settings', {
        'name': _name.text.trim(),
        'phone': t(_phone),
        'address': t(_address),
        'gcashName': t(_gcashName),
        'gcashNumber': t(_gcashNumber),
        'deliveryFee': fee,
        'closedMessage': t(_closed),
      }),
      done: 'Saved.',
    );
  }

  Future<void> _uploadQr() async {
    final bytes = await pickPhoto(context);
    if (bytes == null || !mounted) return;
    final r = await runAction(context, () => session.api.upload('/settings/gcash-qr', bytes), done: 'GCash QR saved.');
    if (r != null) {
      setState(() => _qrVersion++);
      reload(quiet: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store settings')),
      body: loadBody((s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              AppCard(
                color: _open ? C.greenTint : C.redTint,
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _open,
                  onChanged: _setOpen,
                  title: Text(_open ? 'Store is OPEN' : 'Store is CLOSED', style: TextStyle(fontWeight: FontWeight.w800, color: _open ? C.green : C.red)),
                  subtitle: Text(_open ? 'Customers can order in the app.' : 'Customers see your closed message and cannot order.'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _closed, decoration: const InputDecoration(labelText: 'Closed message (optional)', hintText: 'e.g. Sarado po ngayon. Bukas 7AM.')),
              const SectionTitle('Store'),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Store name')),
              const SizedBox(height: 12),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Store phone (customers call this)')),
              const SizedBox(height: 12),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'Store address (optional)')),
              const SizedBox(height: 12),
              TextField(
                controller: _fee,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Delivery fee per order', prefixText: '₱ ', helperText: '0 = free delivery'),
              ),
              const SectionTitle('GCash (for customers who pay by GCash)'),
              TextField(controller: _gcashName, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'GCash account name')),
              const SizedBox(height: 12),
              TextField(controller: _gcashNumber, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'GCash number')),
              const SizedBox(height: 12),
              if (s.hasGcashQr) ...[
                AuthImage('/store/gcash-qr', key: ValueKey(_qrVersion), height: 200),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _uploadQr,
                icon: const Icon(Icons.qr_code_2),
                label: Text(s.hasGcashQr ? 'Change GCash QR' : 'Upload GCash QR (screenshot from GCash)'),
              ),
              const SizedBox(height: 20),
              BusyButton(label: 'Save settings', onPressed: _save),
            ],
          )),
    );
  }
}
