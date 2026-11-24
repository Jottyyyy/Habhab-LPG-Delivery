import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../ui/maps.dart';
import '../../ui/widgets.dart';

/// Add a walk-in suki, or edit a customer's details. The owner also sets the old listahan
/// balance and whether they may get utang.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});
  final Customer? customer;
  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  late final c = widget.customer;
  late final _name = TextEditingController(text: c?.name);
  late final _phone = TextEditingController(text: c?.phone);
  late final _address = TextEditingController(text: c?.address);
  late final _landmark = TextEditingController(text: c?.landmark);
  late final _notes = TextEditingController(text: c?.notes);
  late final _opening = TextEditingController(text: c != null && c!.openingBalance > 0 ? toPesoInput(c!.openingBalance) : '');
  late final _limit = TextEditingController(text: c?.creditLimit != null ? toPesoInput(c!.creditLimit!) : '');
  late bool _utang = c?.utangAllowed ?? true;
  late bool _blocked = c?.blocked ?? false;
  late PickedSpot? _pin = c != null && c!.hasPin ? PickedSpot(c!.lat!, c!.lng!) : null;

  bool get _owner => session.user?.isOwner == true;

  Future<void> _save() async {
    final opening = _opening.text.trim().isEmpty ? 0 : parsePeso(_opening.text);
    final limit = _limit.text.trim().isEmpty ? null : parsePeso(_limit.text);
    if (opening == null || (_limit.text.trim().isNotEmpty && limit == null)) {
      showSnack(context, 'Check the peso amounts.', error: true);
      return;
    }
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'lat': _pin?.lat,
      'lng': _pin?.lng,
      if (_owner) ...{'openingBalance': opening, 'utangAllowed': _utang, 'creditLimit': limit},
      if (_owner && c != null) 'blocked': _blocked,
    };
    final r = await runAction(
      context,
      () => c == null ? session.api.post('/customers', body) : session.api.patch('/customers/${c!.id}', body),
      done: 'Saved.',
    );
    if (r != null && mounted) Navigator.of(context).pop(Customer.fromJson(r['customer'] as Json));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(c == null ? 'Add suki' : 'Edit ${c!.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number (optional)')),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Address (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _landmark, decoration: const InputDecoration(labelText: 'Landmark (optional)')),
          const SizedBox(height: 12),
          if (_pin != null) ...[SpotMap(lat: _pin!.lat, lng: _pin!.lng, height: 140), const SizedBox(height: 8)],
          OutlinedButton.icon(
            onPressed: () async {
              final p = await MapPickerScreen.open(context, lat: _pin?.lat, lng: _pin?.lng, title: 'Pin their house');
              if (p != null) setState(() => _pin = p);
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: Text(_pin == null ? 'Pin their house (optional)' : 'Change the pin'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
          if (_owner) ...[
            const SectionTitle('Utang (owner only)'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _utang,
              onChanged: (v) => setState(() => _utang = v),
              title: const Text('Allow utang'),
              subtitle: const Text('They can order on listahan (in the app and at the store)'),
            ),
            TextField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Utang limit (optional)', prefixText: '₱ ', helperText: 'Empty = no limit'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Old balance from the paper listahan', prefixText: '₱ '),
            ),
            if (c != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _blocked,
                onChanged: (v) => setState(() => _blocked = v),
                title: const Text('Block from ordering in the app'),
              ),
          ],
          const SizedBox(height: 20),
          BusyButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}
