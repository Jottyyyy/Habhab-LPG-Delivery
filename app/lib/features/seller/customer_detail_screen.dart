import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/launch.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'customer_form_screen.dart';
import 'seller_order_screen.dart';

class CustomerDetail {
  CustomerDetail(this.customer, this.ledger, this.orders, this.linkable);
  final Customer customer;
  final List<LedgerEntry> ledger;
  final List<Order> orders;
  final List<({String id, String name})> linkable;
}

/// One customer's listahan (store side): balance, history, record a payment, utang settings.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> with Loads<CustomerDetailScreen, CustomerDetail> {
  bool get _owner => session.user?.isOwner == true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<CustomerDetail> fetch() async {
    final r = await session.api.get('/customers/${widget.customerId}');
    return CustomerDetail(
      Customer.fromJson(r['customer'] as Json),
      (r['ledger'] as List).map((e) => LedgerEntry.fromJson(e as Json)).toList().reversed.toList(),
      (r['orders'] as List).map((e) => Order.fromJson(e as Json)).toList(),
      [for (final l in (r['linkable'] as List? ?? const [])) (id: (l as Json)['id'] as String, name: l['name'] as String)],
    );
  }

  Future<void> _recordPayment(Customer c) async {
    final amount = TextEditingController(text: c.balance > 0 ? toPesoInput(c.balance) : '');
    final ref = TextEditingController();
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setLocal) => AlertDialog(
          title: Text('Payment from ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'cash', label: Text('Cash')), ButtonSegment(value: 'gcash', label: Text('GCash'))],
              selected: {method},
              onSelectionChanged: (s) => setLocal(() => method = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount received', prefixText: '₱ ', helperText: 'Balance now ${formatPeso(c.balance)}'),
            ),
            if (method == 'gcash') ...[
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: const InputDecoration(labelText: 'GCash Ref No. (optional)')),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Back')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () => Navigator.pop(dc, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final cents = parsePeso(amount.text);
    if (cents == null || cents < 100) {
      showSnack(context, 'Enter the amount.', error: true);
      return;
    }
    final r = await runAction(
      context,
      () => session.api.post('/payments', {
        'customerId': c.id,
        'amount': cents,
        'method': method,
        if (ref.text.trim().isNotEmpty) 'gcashRef': ref.text.trim(),
      }),
    );
    if (r != null && mounted) {
      showSnack(context, 'Payment saved. Balance now ${formatPeso((r['balance'] as num).toInt())}.');
      reload(quiet: true);
    }
  }

  Future<void> _resetPassword(Customer c) async {
    final ok = await confirmDialog(context,
        title: 'Give ${c.name} a temporary password?', message: 'Use this when they forgot their password. They will choose a new one after signing in.', confirm: 'Make password');
    if (!ok || !mounted) return;
    final r = await runAction(context, () => session.api.post('/customers/${c.id}/reset-password'));
    if (r == null || !mounted) return;
    final pw = r['temporaryPassword'] as String;
    await showDialog<void>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Temporary password'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tell ${c.name} to sign in with:'),
          const SizedBox(height: 10),
          Text('Number: ${c.phone ?? ''}'),
          SelectableText('Password: $pw', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pw));
              showSnack(context, 'Copied.');
            },
            child: const Text('Copy'),
          ),
          if (c.phone != null) TextButton(onPressed: () => Launch.sms(c.phone!), child: const Text('Text them')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(80, 44)), onPressed: () => Navigator.pop(dc), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _link(Customer c, ({String id, String name}) old) async {
    final ok = await confirmDialog(
      context,
      title: 'Link old record?',
      message: '"${old.name}" (walk-in record with the same number) will be joined to ${c.name}\'s app account. '
          'Their old utang and history move to the app account.',
      confirm: 'Link',
    );
    if (!ok || !mounted) return;
    final r = await runAction(context, () => session.api.post('/customers/${c.id}/link', {'walkinId': old.id}), done: 'Linked.');
    if (r != null) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(data?.customer.name ?? 'Customer'),
        actions: [
          if (data != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final saved = await Navigator.of(context).push<Customer>(MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: data!.customer)));
                if (saved != null) reload(quiet: true);
              },
            ),
        ],
      ),
      body: loadBody((d) {
        final c = d.customer;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            children: [
              AppCard(
                color: c.balance > 0 ? C.navy : Colors.white,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.balance > 0 ? 'Utang balance' : (c.balance < 0 ? 'Credit (store owes them)' : 'No utang'),
                      style: TextStyle(color: c.balance > 0 ? Colors.white70 : C.muted, fontWeight: FontWeight.w600)),
                  Text(formatPeso(c.balance.abs(), alwaysDecimals: true),
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.balance > 0 ? Colors.white : C.green)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Pill(c.hasApp ? 'Has the app' : 'Walk-in suki', color: C.navy, tint: C.navyTint),
                    Pill(c.utangAllowed ? 'Utang allowed' : 'Utang off', color: c.utangAllowed ? C.green : C.muted, tint: c.utangAllowed ? C.greenTint : C.cream),
                    if (c.creditLimit != null) Pill('Limit ${formatPeso(c.creditLimit!)}', color: C.amber, tint: C.amberTint),
                    if (c.blocked) const Pill('Blocked', color: C.red, tint: C.redTint),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: C.flame),
                    onPressed: () => _recordPayment(c),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Record payment'),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (c.phone != null) Text(c.phone!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (c.address != null) Text(c.address!),
                  if (c.landmark != null) Text('Landmark: ${c.landmark}', style: const TextStyle(color: C.muted)),
                  if (c.notes != null) Text('Notes: ${c.notes}', style: const TextStyle(color: C.muted)),
                  if (c.hasPin) ...[const SizedBox(height: 8), SpotMap(lat: c.lat!, lng: c.lng!, height: 140)],
                  const SizedBox(height: 10),
                  Row(children: [
                    if (c.phone != null)
                      Expanded(child: OutlinedButton.icon(onPressed: () => Launch.call(c.phone!), icon: const Icon(Icons.call), label: const Text('Call'))),
                    if (c.phone != null && c.hasPin) const SizedBox(width: 10),
                    if (c.hasPin)
                      Expanded(
                        child: OutlinedButton.icon(onPressed: () => Launch.directions(c.lat!, c.lng!), icon: const Icon(Icons.navigation_outlined), label: const Text('Navigate')),
                      ),
                  ]),
                ]),
              ),
              if (_owner && d.linkable.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final old in d.linkable)
                  NoteBanner(
                    text: 'Old walk-in record "${old.name}" has the same number.',
                    icon: Icons.link,
                    color: C.navy,
                    tint: C.navyTint,
                    action: TextButton(onPressed: () => _link(c, old), child: const Text('Link')),
                  ),
              ],
              const SectionTitle('Listahan history'),
              if (d.ledger.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No entries yet.', style: TextStyle(color: C.muted))),
              for (final e in d.ledger)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(e.kind == 'payment' ? Icons.payments_outlined : (e.kind == 'opening' ? Icons.menu_book : Icons.propane_tank_outlined),
                      color: e.kind == 'payment' ? C.green : C.flame),
                  title: Text('${e.label}${e.ref != null ? ' · ${e.ref}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${formatDateTime(e.at)}${e.status == 'pending' ? ' · GCash being checked' : ''}${e.status == 'rejected' ? ' · rejected' : ''}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      e.status == 'pending' || e.status == 'rejected' ? '—' : '${e.amount < 0 ? '−' : '+'}${formatPeso(e.amount.abs())}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: e.amount < 0 ? C.green : C.ink),
                    ),
                    Text('Bal ${formatPeso(e.balance)}', style: const TextStyle(fontSize: 11, color: C.muted)),
                  ]),
                ),
              const SectionTitle('Recent orders'),
              if (d.orders.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No orders yet.', style: TextStyle(color: C.muted))),
              for (final o in d.orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OrderTile(o, onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SellerOrderScreen(orderId: o.id)));
                    reload(quiet: true);
                  }),
                ),
              if (_owner && c.hasApp) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () => _resetPassword(c), icon: const Icon(Icons.key_outlined), label: const Text('Forgot password? Make a temporary one')),
              ],
            ],
          ),
        );
      }),
    );
  }
}
