import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';

/// "I paid by GCash": shows the store's GCash number/QR, then the customer enters the
/// reference number and attaches the screenshot. The store checks it before it counts.
class PayGcashScreen extends StatefulWidget {
  const PayGcashScreen({super.key, required this.store, this.amount, this.order});
  final StoreInfo store;
  final int? amount;
  final Order? order;

  @override
  State<PayGcashScreen> createState() => _PayGcashScreenState();
}

class _PayGcashScreenState extends State<PayGcashScreen> {
  late final _amount = TextEditingController(text: widget.amount != null && widget.amount! > 0 ? toPesoInput(widget.amount!) : '');
  final _ref = TextEditingController();
  Uint8List? _photo;
  String? _error;

  Future<void> _send() async {
    setState(() => _error = null);
    final amount = parsePeso(_amount.text);
    if (amount == null || amount < 100) {
      setState(() => _error = 'Enter the amount you sent.');
      return;
    }
    if (_ref.text.trim().length < 4) {
      setState(() => _error = 'Enter the GCash reference number (Ref No.) from your GCash receipt.');
      return;
    }
    if (_photo == null) {
      final ok = await confirmDialog(context,
          title: 'No screenshot', message: 'A screenshot helps the store confirm your payment faster. Send without it?', confirm: 'Send anyway');
      if (!ok) return;
    }
    try {
      final r = await session.api.post('/payments/gcash', {
        'amount': amount,
        'gcashRef': _ref.text.trim(),
        if (widget.order != null) 'orderId': widget.order!.id,
      });
      final payment = Payment.fromJson(r['payment'] as Json);
      if (_photo != null) {
        try {
          await session.api.upload('/uploads/proof', _photo!, query: {'paymentId': payment.id});
        } on ApiException catch (e) {
          if (mounted) showSnack(context, 'Payment sent, but the screenshot did not upload: ${e.message}', error: true);
        }
      }
      if (!mounted) return;
      showSnack(context, 'Sent! The store will check your GCash payment.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay with GCash')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('1. Send the payment in your GCash app', style: TextStyle(fontWeight: FontWeight.w800, color: C.navy)),
              const SizedBox(height: 10),
              if (s.gcashNumber == null && !s.hasGcashQr)
                const Text('The store has not added its GCash number yet. Please call the store or pay cash.', style: TextStyle(color: C.red)),
              if (s.gcashNumber != null)
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (s.gcashName != null) Text(s.gcashName!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(s.gcashNumber!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ]),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(90, 44)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.gcashNumber!));
                      showSnack(context, 'GCash number copied.');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                ]),
              if (widget.amount != null && widget.amount! > 0) ...[
                const SizedBox(height: 8),
                Text('Amount: ${formatPeso(widget.amount!)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
              if (s.hasGcashQr) ...[
                const SizedBox(height: 12),
                const Text('Or scan the store QR:', style: TextStyle(color: C.muted)),
                const SizedBox(height: 6),
                const AuthImage('/store/gcash-qr', height: 240),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('2. Tell the store you paid', style: TextStyle(fontWeight: FontWeight.w800, color: C.navy)),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount sent', prefixText: '₱ '),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'GCash Ref No.', hintText: 'e.g. 1234 567 890123'),
              ),
              const SizedBox(height: 12),
              if (_photo != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!, height: 220, fit: BoxFit.contain)),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final b = await pickPhoto(context);
                  if (b != null) setState(() => _photo = b);
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_photo == null ? 'Attach GCash screenshot' : 'Change screenshot'),
              ),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            NoteBanner(text: _error!, color: C.red, tint: C.redTint, icon: Icons.error_outline),
          ],
          const SizedBox(height: 16),
          BusyButton(label: 'Send to the store', icon: Icons.send, onPressed: _send),
          if (widget.order != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('I will pay later')),
          ],
        ],
      ),
    );
  }
}
