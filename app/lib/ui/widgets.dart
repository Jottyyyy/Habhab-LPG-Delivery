import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../theme/theme.dart';

/// Small building blocks shared by every screen.

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? C.red : C.ink));
}

/// Run an API action with a spinner-free button: shows the error as a snackbar.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? done}) async {
  try {
    final r = await action();
    if (done != null && context.mounted) showSnack(context, done);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showSnack(context, 'Something went wrong. Please try again.', error: true);
  }
  return null;
}

Future<bool> confirmDialog(BuildContext context, {required String title, String? message, String confirm = 'Yes', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44), backgroundColor: danger ? C.red : C.navy),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == true;
}

/// Ask for one line of text (cancel reason, reject reason).
Future<String?> askText(BuildContext context, {required String title, String? hint, String confirm = 'OK', String? initial}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Back')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == null || r.isEmpty ? null : r;
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.navy))),
          ?trailing,
        ]),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: bold ? 16 : 14.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? C.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style.copyWith(color: color ?? (bold ? C.ink : C.muted)))),
        Text(value, style: style),
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, required this.tint, this.icon});
  final String text;
  final Color color;
  final Color tint;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      );
}

String statusLabel(OrderStatus s, {bool walkin = false}) => switch (s) {
      OrderStatus.pending => 'Waiting for store',
      OrderStatus.confirmed => 'Preparing',
      OrderStatus.onTheWay => 'On the way',
      OrderStatus.delivered => walkin ? 'Sold' : 'Delivered',
      OrderStatus.cancelled => 'Cancelled',
    };

class StatusPill extends StatelessWidget {
  const StatusPill(this.order, {super.key});
  final Order order;
  @override
  Widget build(BuildContext context) {
    final (c, t, i) = switch (order.status) {
      OrderStatus.pending => (C.amber, C.amberTint, Icons.schedule),
      OrderStatus.confirmed => (C.navy, C.navyTint, Icons.inventory_2_outlined),
      OrderStatus.onTheWay => (C.flame, C.amberTint, Icons.delivery_dining),
      OrderStatus.delivered => (C.green, C.greenTint, Icons.check_circle_outline),
      OrderStatus.cancelled => (C.red, C.redTint, Icons.cancel_outlined),
    };
    return Pill(statusLabel(order.status, walkin: order.isWalkin), color: c, tint: t, icon: i);
  }
}

String methodLabel(String m) => switch (m) {
      'cash' => 'Cash',
      'gcash' => 'GCash',
      'utang' => 'Utang (listahan)',
      _ => m,
    };

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: C.gold),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load',
        message: message,
        action: SizedBox(width: 180, child: FilledButton(onPressed: onRetry, child: const Text('Try again'))),
      );
}

class NoteBanner extends StatelessWidget {
  const NoteBanner({super.key, required this.text, this.icon = Icons.info_outline, this.color = C.amber, this.tint = C.amberTint, this.action});
  final String text;
  final IconData icon;
  final Color color;
  final Color tint;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
          ?action,
        ]),
      );
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onChanged, this.max = 99});
  final int qty;
  final int max;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12), color: Colors.white),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
            icon: const Icon(Icons.remove),
            tooltip: 'Less',
          ),
          SizedBox(width: 28, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: qty < max ? () => onChanged(qty + 1) : null,
            icon: const Icon(Icons.add),
            tooltip: 'More',
          ),
        ]),
      );
}

/// Loading / error / data for screens that fetch from the API.
mixin Loads<W extends StatefulWidget, T> on State<W> {
  T? data;
  String? error;
  bool loading = false;

  Future<T> fetch();

  Future<void> reload({bool quiet = false}) async {
    if (loading) return;
    loading = true;
    // (No setState when there is nothing to clear, so this is safe to call from initState.)
    if (!quiet && mounted && error != null) setState(() => error = null);
    try {
      final d = await fetch();
      if (!mounted) return;
      setState(() {
        data = d;
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted && (data == null || !quiet)) setState(() => error = e.message);
    } finally {
      loading = false;
    }
  }

  Widget loadBody(Widget Function(T data) builder) {
    final d = data;
    if (d != null) return builder(d);
    if (error != null) return ErrorRetry(message: error!, onRetry: reload);
    return const Center(child: CircularProgressIndicator());
  }
}

/// A big filled button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.color});
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final Color? color;
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed;
    return FilledButton(
      style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
      onPressed: busy || onPressed == null
          ? null
          : () async {
              setState(() => busy = true);
              try {
                await onPressed();
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.icon != null) ...[Icon(widget.icon), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ]),
    );
  }
}
