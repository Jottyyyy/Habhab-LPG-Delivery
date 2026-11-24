import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/widgets.dart';
import 'cart.dart';
import 'pay_gcash_screen.dart';

/// Review the cart, choose where to deliver and how to pay, then send the order.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.store, required this.utangAllowed, required this.balance, this.creditLimit});
  final StoreInfo store;
  final bool utangAllowed;
  final int balance;
  final int? creditLimit;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  Customer? _profile;
  bool _otherAddress = false;
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _notes = TextEditingController();
  PickedSpot? _pin;
  String _method = 'cash';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final r = await session.api.get('/me/profile');
      if (mounted) setState(() => _profile = Customer.fromJson(r['profile'] as Json));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  int get _total => cart.subtotal + widget.store.deliveryFee;

  Future<void> _place() async {
    setState(() => _error = null);
    if (cart.isEmpty) return;
    if (_otherAddress && _address.text.trim().length < 5) {
      setState(() => _error = 'Enter the delivery address.');
      return;
    }
    try {
      final body = <String, dynamic>{
        'items': cart.toJson(),
        'paymentMethod': _method,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        if (_otherAddress) ...{
          'address': _address.text.trim(),
          'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
          'lat': _pin?.lat,
          'lng': _pin?.lng,
        },
      };
      final r = await session.api.post('/orders', body);
      final order = Order.fromJson(r['order'] as Json);
      cart.clear();
      if (!mounted) return;
      if (_method == 'gcash') {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PayGcashScreen(store: widget.store, amount: order.total, order: order),
        ));
      }
      if (mounted) Navigator.of(context).pop(order);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final over = widget.creditLimit != null && widget.balance + _total > widget.creditLimit!;
    return Scaffold(
      appBar: AppBar(title: const Text('Review order')),
      body: ListenableBuilder(
        listenable: cart,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          children: [
            AppCard(
              child: Column(children: [
                for (final (prod, qty) in cart.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(prod.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${formatPeso(prod.price ?? 0)} each', style: const TextStyle(color: C.muted, fontSize: 13)),
                        ]),
                      ),
                      QtyStepper(qty: qty, max: prod.stock != null ? prod.stock!.clamp(1, 99) : 99, onChanged: (q) => cart.set(prod, q)),
                    ]),
                  ),
                const Divider(height: 20),
                if (widget.store.deliveryFee > 0) ...[
                  InfoRow('Subtotal', formatPeso(cart.subtotal)),
                  InfoRow('Delivery fee', formatPeso(widget.store.deliveryFee)),
                ] else
                  const InfoRow('Delivery', 'Free', color: C.green),
                InfoRow('Total', formatPeso(_total), bold: true),
              ]),
            ),
            const SectionTitle('Deliver to'),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p == null && _error == null) const LinearProgressIndicator(),
                if (p != null && !_otherAddress) ...[
                  Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(p.address ?? 'No address yet'),
                  if (p.landmark != null) Text('Landmark: ${p.landmark}', style: const TextStyle(color: C.muted)),
                  if (p.hasPin) ...[const SizedBox(height: 8), SpotMap(lat: p.lat!, lng: p.lng!, height: 130)],
                  if (!p.hasPin)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Tip: add a map pin in Account so the rider finds you faster.', style: TextStyle(color: C.amber)),
                    ),
                ],
                if (_otherAddress) ...[
                  TextField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Address for this order'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _landmark, decoration: const InputDecoration(labelText: 'Landmark (optional)')),
                  const SizedBox(height: 10),
                  if (_pin != null) ...[SpotMap(lat: _pin!.lat, lng: _pin!.lng, height: 130), const SizedBox(height: 8)],
                  OutlinedButton.icon(
                    onPressed: () async {
                      final x = await MapPickerScreen.open(context, lat: _pin?.lat, lng: _pin?.lng, title: 'Pin the delivery spot');
                      if (x != null) setState(() => _pin = x);
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(_pin == null ? 'Pin it on the map' : 'Change the pin'),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _otherAddress,
                  onChanged: (v) => setState(() => _otherAddress = v),
                  title: const Text('Deliver somewhere else this time'),
                ),
              ]),
            ),
            const SectionTitle('Payment'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: RadioGroup<String>(
                groupValue: _method,
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
                child: Column(children: [
                  const RadioListTile<String>(
                    value: 'cash',
                    title: Text('Cash on delivery'),
                    subtitle: Text('Pay the rider when the gasul arrives'),
                  ),
                  RadioListTile<String>(
                    value: 'gcash',
                    title: const Text('GCash'),
                    subtitle: Text(widget.store.gcashNumber != null
                        ? 'Send to ${widget.store.gcashNumber}, then attach the screenshot'
                        : 'Send by GCash, then attach the screenshot'),
                  ),
                  if (widget.utangAllowed)
                    RadioListTile<String>(
                      value: 'utang',
                      title: const Text('Utang (listahan)'),
                      subtitle: Text(widget.creditLimit != null
                          ? 'Balance ${formatPeso(widget.balance)} · limit ${formatPeso(widget.creditLimit!)}'
                          : 'Balance now ${formatPeso(widget.balance)}'),
                    )
                  else
                    const ListTile(
                      enabled: false,
                      leading: Icon(Icons.lock_outline),
                      title: Text('Utang (listahan)'),
                      subtitle: Text('Ask the store to turn on utang for your account'),
                    ),
                ]),
              ),
            ),
            if (_method == 'utang' && over) ...[
              const SizedBox(height: 10),
              const NoteBanner(text: 'This order is over your utang limit. Pay part of your listahan first, or choose cash/GCash.', color: C.red, tint: C.redTint),
            ],
            const SectionTitle('Note to the store (optional)'),
            TextField(
              controller: _notes,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Pakitawag pagdating, may aso sa gate'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              NoteBanner(text: _error!, color: C.red, tint: C.redTint, icon: Icons.error_outline),
            ],
            const SizedBox(height: 14),
            BusyButton(
              label: 'Place order · ${formatPeso(_total)}',
              icon: Icons.local_fire_department,
              color: C.flame,
              onPressed: cart.isEmpty || p == null ? null : _place,
            ),
          ],
        ),
      ),
    );
  }
}
