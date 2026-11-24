import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'board.dart';

/// GCash payments sent by customers. Check each one in the store's GCash app (same amount and
/// Ref No.), then Confirm — only then does it count on their listahan — or Reject.
class GcashScreen extends StatefulWidget {
  const GcashScreen({super.key, required this.active, required this.board});
  final bool active;
  final Board board;
  @override
  State<GcashScreen> createState() => _GcashScreenState();
}

class _GcashScreenState extends State<GcashScreen> with Loads<GcashScreen, List<Payment>> {
  bool _showAll = false;
  int _seenCount = -1;

  @override
  void initState() {
    super.initState();
    widget.board.addListener(_boardChanged);
    if (widget.active) reload();
  }

  @override
  void dispose() {
    widget.board.removeListener(_boardChanged);
    super.dispose();
  }

  /// A new GCash payment arrived (board count went up): refresh the list if it is open.
  void _boardChanged() {
    final n = widget.board.gcashToCheck;
    if (_seenCount != -1 && n != _seenCount && widget.active) reload(quiet: true);
    _seenCount = n;
  }

  @override
  void didUpdateWidget(GcashScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) WidgetsBinding.instance.addPostFrameCallback((_) => reload(quiet: data != null));
  }

  @override
  Future<List<Payment>> fetch() async {
    final r = await session.api.get('/payments', query: _showAll ? null : {'status': 'pending'});
    return (r['payments'] as List).map((e) => Payment.fromJson(e as Json)).where((p) => _showAll || p.status == 'pending').toList();
  }

  Future<void> _confirm(Payment p) async {
    final ok = await confirmDialog(context,
        title: 'Confirm ${formatPeso(p.amount)}?', message: 'Only confirm if you see this amount and Ref No. ${p.gcashRef ?? ''} in your GCash.', confirm: 'Confirm');
    if (!ok || !mounted) return;
    final r = await runAction(context, () => session.api.post('/payments/${p.id}/confirm'), done: 'Confirmed.');
    if (r != null) {
      reload(quiet: true);
      widget.board.refresh();
    }
  }

  Future<void> _reject(Payment p) async {
    final reason = await askText(context, title: 'Reject ${formatPeso(p.amount)}?', hint: 'Reason (e.g. not received)', confirm: 'Reject');
    if (reason == null || !mounted) return;
    final r = await runAction(context, () => session.api.post('/payments/${p.id}/reject', {'reason': reason}), done: 'Rejected.');
    if (r != null) {
      reload(quiet: true);
      widget.board.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GCash to check'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _showAll = !_showAll);
              reload();
            },
            child: Text(_showAll ? 'Waiting only' : 'Show all', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: !widget.active && data == null
          ? const SizedBox.shrink()
          : loadBody((list) => RefreshIndicator(
                onRefresh: reload,
                child: list.isEmpty
                    ? ListView(children: const [
                        EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Nothing to check', message: 'GCash payments from customers show here.'),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = list[i];
                          return AppCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p.customerName ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                    Text('${p.ref} · ${formatDateTime(p.createdAt)}${p.orderRef != null ? ' · for ${p.orderRef}' : ' · for utang'}',
                                        style: const TextStyle(color: C.muted, fontSize: 13)),
                                  ]),
                                ),
                                Text(formatPeso(p.amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: C.navy)),
                              ]),
                              const SizedBox(height: 6),
                              Text('Ref No.: ${p.gcashRef ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              if (p.method == 'cash') const Text('Cash', style: TextStyle(color: C.muted)),
                              if (p.hasProof) ...[
                                const SizedBox(height: 8),
                                ClipRRect(borderRadius: BorderRadius.circular(10), child: AuthImage('/proof/${p.id}', height: 200)),
                                const Text('Tap the screenshot to zoom', textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
                              ] else if (p.method == 'gcash')
                                const Text('No screenshot attached', style: TextStyle(color: C.amber)),
                              const SizedBox(height: 10),
                              if (p.status == 'pending')
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(foregroundColor: C.red, side: const BorderSide(color: C.red)),
                                      onPressed: () => _reject(p),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: C.green, minimumSize: const Size.fromHeight(48)),
                                      onPressed: () => _confirm(p),
                                      child: const Text('Confirm'),
                                    ),
                                  ),
                                ])
                              else
                                Pill(
                                  p.status == 'confirmed' ? 'Confirmed' : 'Rejected${p.rejectReason != null ? ': ${p.rejectReason}' : ''}',
                                  color: p.status == 'confirmed' ? C.green : C.red,
                                  tint: p.status == 'confirmed' ? C.greenTint : C.redTint,
                                ),
                            ]),
                          );
                        },
                      ),
              )),
    );
  }
}
