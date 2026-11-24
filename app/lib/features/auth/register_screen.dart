import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/widgets.dart';

/// Customer sign-up: name, number, password, address and a map pin of the house.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  PickedSpot? _pin;
  bool _hide = true;
  String? _error;

  Future<void> _pickPin() async {
    final p = await MapPickerScreen.open(context, lat: _pin?.lat, lng: _pin?.lng);
    if (p != null) setState(() => _pin = p);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (_name.text.trim().length < 2 || _phone.text.trim().isEmpty || _password.text.isEmpty || _address.text.trim().length < 5) {
      setState(() => _error = 'Please fill in your name, mobile number, password and address.');
      return;
    }
    if (_pin == null) {
      final ok = await confirmDialog(
        context,
        title: 'No map pin yet',
        message: 'A pin helps the rider find your house fast. Continue without it? You can add it later in Account.',
        confirm: 'Continue',
      );
      if (!ok) return;
    }
    try {
      await session.register({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'password': _password.text,
        'address': _address.text.trim(),
        'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        'lat': _pin?.lat,
        'lng': _pin?.lng,
      });
      // The router opens the customer app.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile number', hintText: '0917 123 4567', prefixIcon: Icon(Icons.phone_android)),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hide,
              decoration: InputDecoration(
                labelText: 'Password (at least 6 characters)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SectionTitle('Delivery address'),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'House no., street, purok, barangay, town', prefixIcon: Icon(Icons.home_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _landmark,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Landmark (optional)', hintText: 'e.g. beside the chapel, blue gate', prefixIcon: Icon(Icons.flag_outlined)),
            ),
            const SizedBox(height: 12),
            if (_pin != null) ...[
              SpotMap(lat: _pin!.lat, lng: _pin!.lng, height: 170),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _pickPin,
              icon: Icon(_pin == null ? Icons.add_location_alt_outlined : Icons.edit_location_alt_outlined),
              label: Text(_pin == null ? 'Pin my house on the map' : 'Change the pin'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              NoteBanner(text: _error!, color: C.red, tint: C.redTint, icon: Icons.error_outline),
            ],
            const SizedBox(height: 20),
            BusyButton(label: 'Create account', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
