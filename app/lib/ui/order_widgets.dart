import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../core/money.dart';
import '../core/session.dart';
import '../theme/theme.dart';
import 'widgets.dart';

/// Pending → Preparing → On the way → Delivered, with the time of each step.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline(this.order, {super.key});
  final Order order;

  @override
  Widget build(BuildContext context) {
    if (order.status == OrderStatus.cancelled) {
      return NoteBanner(
        icon: Icons.cancel_outlined,
        color: C.red,
        tint: C.redTint,
        text: 'Cancelled${order.cancelledAt != null ? ' · ${formatDateTime(order.cancelledAt!)}' : ''}${order.cancelReason != null ? '\n${order.cancelReason}' : ''}',
      );
    }
    final steps = [
      ('Order sent', 'The store got your order', order.createdAt),
      ('Preparing', 'The store accepted your order', order.confirmedAt),
      ('On the way', order.riderName != null ? '${order.riderName} is bringing it' : 'Your gasul is on the way', order.outAt),
      ('Delivered', 'Salamat po!', order.deliveredAt),
    ];
    final current = switch (order.status) {
      OrderStatus.pending => 0,
      OrderStatus.confirmed => 1,
      OrderStatus.onTheWay => 2,
      _ => 3,
    };
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= current ? (i == current && current < 3 ? C.flame : C.green) : Colors.white,
                      border: Border.all(color: i <= current ? Colors.transparent : C.line, width: 2),
                    ),
                    child: i < current || current == 3
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : (i == current ? const Icon(Icons.circle, size: 8, color: Colors.white) : null),
                  ),
                  if (i < steps.length - 1) Expanded(child: Container(width: 2, color: i < current ? C.green : C.line)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(steps[i].$1,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: i <= current ? C.ink : C.muted)),
                      ),
                      if (steps[i].$3 != null && i <= current)
                        Text(formatTime(steps[i].$3!), style: const TextStyle(color: C.muted, fontSize: 13)),
                    ]),
                    if (i <= current) Text(steps[i].$2, style: const TextStyle(color: C.muted, fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Items + totals, receipt style.
class OrderLines extends StatelessWidget {
  const OrderLines(this.order, {super.key, this.showPaid = true});
  final Order order;
  final bool showPaid;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in order.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 34, child: Text('${i.qty}×', style: const TextStyle(fontWeight: FontWeight.w700))),
            Expanded(child: Text(i.name)),
            Text(formatPeso(i.lineTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      const Divider(height: 18),
      if (order.deliveryFee > 0) ...[
        InfoRow('Subtotal', formatPeso(order.subtotal)),
        InfoRow('Delivery fee', formatPeso(order.deliveryFee)),
      ],
      InfoRow('Total', formatPeso(order.total), bold: true),
      InfoRow('Payment', methodLabel(order.paymentMethod)),
      if (showPaid && order.status != OrderStatus.cancelled) ...[
        if (order.paid > 0) InfoRow('Paid', formatPeso(order.paid), color: C.green),
        if (order.pendingPaid > 0) InfoRow('GCash being checked', formatPeso(order.pendingPaid), color: C.amber),
      ],
    ]);
  }
}

/// An image the API protects (GCash screenshot, store QR), loaded with the sign-in token.
class AuthImage extends StatefulWidget {
  const AuthImage(this.path, {super.key, this.height = 260, this.fit = BoxFit.contain});
  final String path;
  final double height;
  final BoxFit fit;
  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await session.api.bytes(widget.path);
      if (mounted) setState(() => _bytes = b);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    return SizedBox(
      height: widget.height,
      child: b != null
          ? GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => Dialog(
                  insetPadding: const EdgeInsets.all(12),
                  child: InteractiveViewer(child: Image.memory(b)),
                ),
              ),
              child: Image.memory(b, fit: widget.fit),
            )
          : Center(
              child: _error != null
                  ? Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted))
                  : const CircularProgressIndicator(),
            ),
    );
  }
}

/// Pick a photo (screenshot from the gallery, or take one), compressed for upload.
Future<Uint8List?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose screenshot / photo'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 2400, imageQuality: 80);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (bytes.length > 3900000) {
      if (context.mounted) showSnack(context, 'That photo is too large. Choose a smaller one.', error: true);
      return null;
    }
    return bytes;
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not open the photo.', error: true);
    return null;
  }
}

/// One order in a list.
class OrderTile extends StatelessWidget {
  const OrderTile(this.order, {super.key, required this.onTap, this.showCustomer = false});
  final Order order;
  final VoidCallback onTap;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(order.ref, style: const TextStyle(fontWeight: FontWeight.w800, color: C.navy)),
          const SizedBox(width: 8),
          Expanded(child: Text(formatDateTime(order.createdAt), style: const TextStyle(color: C.muted, fontSize: 13))),
          StatusPill(order),
        ]),
        const SizedBox(height: 8),
        if (showCustomer) Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(order.itemsSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (showCustomer && order.address != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(order.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
          ),
        const SizedBox(height: 6),
        Row(children: [
          Text(formatPeso(order.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 8),
          Text('· ${methodLabel(order.paymentMethod)}', style: const TextStyle(color: C.muted)),
          const Spacer(),
          const Icon(Icons.chevron_right, color: C.muted),
        ]),
      ]),
    );
  }
}
