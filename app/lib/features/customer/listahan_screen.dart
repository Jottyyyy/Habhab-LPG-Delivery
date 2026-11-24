import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';
import 'pay_gcash_screen.dart';

class LedgerData {
  LedgerData(this.balance, this.entries, this.utangAllowed, this.creditLimit);
  final int balance;
  final List<LedgerEntry> entries;
  final bool utangAllowed;
  final int? creditLimit;
}

/// The customer's own listahan: balance, utang orders and payments, and "Pay via GCash".
class ListahanScreen extends StatefulWidget {
  const ListahanScreen({super.key, required this.active});
  final bool active;
  @override
  State<ListahanScreen> createState() => _ListahanScreenState();
}

class _ListahanScreenState extends State<ListahanScreen> with Loads<ListahanScreen, LedgerData> {
  @override
  void initState() {
    super.initState();
    if (widget.active) reload();
  }

  @override
  void didUpdateWidget(ListahanScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) WidgetsBinding.instance.addPostFrameCallback((_) => reload(quiet: data != null));
  }

  @override
  Future<LedgerData> fetch() async {
    final r = await session.api.get('/me/ledger');
    return LedgerData(
      (r['balance'] as num?)?.toInt() ?? 0,
      (r['entries'] as List).map((e) => LedgerEntry.fromJson(e as Json)).toList().reversed.toList(),
      r['utangAllowed'] == true,
      (r['creditLimit'] as num?)?.toInt(),
    );
  }

  Future<void> _pay(int balance) async {
    final store = await runAction(context, () async => StoreInfo.fromJson((await session.api.get('/store'))['store'] as Json));
    if (store == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PayGcashScreen(store: store, amount: balance)));
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My listahan')),
      body: !widget.active && data == null
          ? const SizedBox.shrink()
          : loadBody((d) => RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                  children: [
                    AppCard(
                      color: d.balance > 0 ? C.navy : Colors.white,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.balance > 0 ? 'Utang balance' : (d.balance < 0 ? 'You have credit' : 'Walang utang'),
                            style: TextStyle(color: d.balance > 0 ? Colors.white70 : C.muted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(formatPeso(d.balance.abs(), alwaysDecimals: true),
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: d.balance > 0 ? Colors.white : C.green)),
                        const SizedBox(height: 6),
                        Text(
                          d.utangAllowed
                              ? (d.creditLimit != null ? 'Utang limit: ${formatPeso(d.creditLimit!)}' : 'You can order on utang.')
                              : 'Utang is not turned on for your account.',
                          style: TextStyle(color: d.balance > 0 ? Colors.white70 : C.muted),
                        ),
                        if (d.balance > 0) ...[
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: C.flame),
                            onPressed: () => _pay(d.balance),
                            icon: const Icon(Icons.account_balance_wallet_outlined),
                            label: const Text('Pay via GCash'),
                          ),
                        ],
                      ]),
                    ),
                    const SectionTitle('History'),
                    if (d.entries.isEmpty)
                      const EmptyState(icon: Icons.menu_book_outlined, title: 'Nothing here yet', message: 'Utang orders and payments will show here.'),
                    for (final e in d.entries) _EntryTile(e),
                  ],
                ),
              )),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.e);
  final LedgerEntry e;

  @override
  Widget build(BuildContext context) {
    final isPay = e.kind == 'payment';
    final pending = e.status == 'pending';
    final rejected = e.status == 'rejected';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(isPay ? Icons.payments_outlined : Icons.propane_tank_outlined, color: isPay ? C.green : C.flame),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e.label}${e.ref != null ? ' · ${e.ref}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(formatDateTime(e.at), style: const TextStyle(color: C.muted, fontSize: 13)),
              if (pending) const Text('Being checked by the store', style: TextStyle(color: C.amber, fontSize: 13, fontWeight: FontWeight.w600)),
              if (rejected) const Text('Not accepted', style: TextStyle(color: C.red, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              pending || rejected ? 'pending' : '${e.amount < 0 ? '−' : '+'}${formatPeso(e.amount.abs())}',
              style: TextStyle(fontWeight: FontWeight.w800, color: pending || rejected ? C.muted : (e.amount < 0 ? C.green : C.ink)),
            ),
            if (!pending && !rejected) Text('Bal ${formatPeso(e.balance)}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }
}
