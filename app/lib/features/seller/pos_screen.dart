import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'customer_picker.dart';

/// Walk-in sale at the store: tap products, choose the customer (or Walk-in), how they pay, done.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key, required this.active});
  final bool active;
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with Loads<PosScreen, List<Product>> {
  final Map<String, int> _qty = {};
  Customer? _customer;
  String _method = 'cash';
  final _gcashRef = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.active) reload();
  }

  @override
  void didUpdateWidget(PosScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) WidgetsBinding.instance.addPostFrameCallback((_) => reload(quiet: data != null));
  }

  @override
  Future<List<Product>> fetch() async {
    final r = await session.api.get('/store');
    return (r['products'] as List).map((e) => Product.fromJson(e as Json)).toList();
  }

  int _total(List<Product> ps) => ps.fold(0, (s, p) => s + (p.price ?? 0) * (_qty[p.id] ?? 0));
  int get _count => _qty.values.fold(0, (a, b) => a + b);

  void _set(Product p, int q) => setState(() => q <= 0 ? _qty.remove(p.id) : _qty[p.id] = q);

  Future<void> _complete(List<Product> ps) async {
    if (_method == 'utang' && _customer == null) {
      showSnack(context, 'Choose the customer for an utang sale.', error: true);
      return;
    }
    if (_method == 'utang' && _customer != null && !_customer!.utangAllowed) {
      final ok = await confirmDialog(context,
          title: 'Utang is off for ${_customer!.name}', message: 'Add this sale to their listahan anyway?', confirm: 'Add to listahan');
      if (!ok || !mounted) return;
    }
    final r = await runAction(
      context,
      () => session.api.post('/pos/sales', {
        'customerId': _customer?.id,
        'items': [for (final e in _qty.entries) {'productId': e.key, 'qty': e.value}],
        'paymentMethod': _method,
        if (_method == 'gcash' && _gcashRef.text.trim().isNotEmpty) 'gcashRef': _gcashRef.text.trim(),
      }),
    );
    if (r == null || !mounted) return;
    final sale = Order.fromJson(r['order'] as Json);
    setState(() {
      _qty.clear();
      _customer = null;
      _method = 'cash';
      _gcashRef.clear();
    });
    reload(quiet: true);
    await _showReceipt(sale);
  }

  Future<void> _showReceipt(Order sale) async {
    final text = StringBuffer()
      ..writeln('HABHAB LPG TRADING')
      ..writeln('Sale ${sale.ref} · ${formatDate(sale.createdAt)} ${formatTime(sale.createdAt)}')
      ..writeln('Customer: ${sale.customerName}')
      ..writeln('');
    for (final i in sale.items) {
      text.writeln('${i.qty} x ${i.name}  ${formatPeso(i.lineTotal)}');
    }
    text
      ..writeln('')
      ..writeln('TOTAL: ${formatPeso(sale.total)}')
      ..writeln('Payment: ${methodLabel(sale.paymentMethod)}')
      ..writeln('Salamat po!');
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(children: [const Icon(Icons.check_circle, color: C.green), const SizedBox(width: 8), Text('Sold · ${sale.ref}')]),
        content: SingleChildScrollView(child: OrderLines(sale, showPaid: false)),
        actions: [
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: text.toString())),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share receipt'),
          ),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: () => Navigator.pop(c), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('POS · Walk-in sale')),
      body: !widget.active && data == null
          ? const SizedBox.shrink()
          : loadBody((ps) {
              final total = _total(ps);
              return Column(children: [
                Expanded(
                  child: ps.isEmpty
                      ? const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No products with prices yet',
                          message: 'Owner: go to More → Products, set the prices and turn them on.',
                        )
                      : RefreshIndicator(
                          onRefresh: reload,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.05,
                            ),
                            itemCount: ps.length,
                            itemBuilder: (context, i) {
                              final p = ps[i];
                              final q = _qty[p.id] ?? 0;
                              return Card(
                                color: q > 0 ? C.navyTint : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: q > 0 ? C.navy : C.line, width: q > 0 ? 2 : 1),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: p.outOfStock ? null : () => _set(p, q + 1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Icon(p.kind == 'accessory' ? Icons.build_circle_outlined : Icons.propane_tank_outlined, color: C.flame),
                                        const Spacer(),
                                        if (q > 0)
                                          CircleAvatar(radius: 14, backgroundColor: C.navy, child: Text('$q', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                                      ]),
                                      const SizedBox(height: 6),
                                      Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                                      Text(formatPeso(p.price ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: C.navy)),
                                      Text(
                                        p.outOfStock ? 'Out of stock' : (p.stock != null ? '${p.stock} in stock' : ' '),
                                        style: TextStyle(fontSize: 12, color: p.outOfStock ? C.red : C.muted),
                                      ),
                                      if (q > 0)
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                            onPressed: () => _set(p, q - 1),
                                            child: const Text('− less'),
                                          ),
                                        ),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
                if (_count > 0)
                  Material(
                    elevation: 8,
                    color: Colors.white,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            const Icon(Icons.person_outline, color: C.navy),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _customer == null ? 'Walk-in customer' : '${_customer!.name}${_customer!.balance > 0 ? ' · utang ${formatPeso(_customer!.balance)}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final c = await pickCustomer(context);
                                if (c != null) setState(() => _customer = c);
                              },
                              child: Text(_customer == null ? 'Choose suki' : 'Change'),
                            ),
                            if (_customer != null)
                              IconButton(onPressed: () => setState(() => _customer = null), icon: const Icon(Icons.close), tooltip: 'Walk-in'),
                          ]),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
                              ButtonSegment(value: 'gcash', label: Text('GCash'), icon: Icon(Icons.account_balance_wallet_outlined)),
                              ButtonSegment(value: 'utang', label: Text('Utang'), icon: Icon(Icons.menu_book_outlined)),
                            ],
                            selected: {_method},
                            onSelectionChanged: (s) => setState(() => _method = s.first),
                          ),
                          if (_method == 'gcash') ...[
                            const SizedBox(height: 8),
                            TextField(controller: _gcashRef, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GCash Ref No. (optional)', isDense: true)),
                          ],
                          const SizedBox(height: 10),
                          Row(children: [
                            TextButton(onPressed: () => setState(_qty.clear), child: const Text('Clear')),
                            const SizedBox(width: 8),
                            Expanded(
                              child: BusyButton(
                                label: 'Complete sale · ${formatPeso(total)}',
                                color: C.flame,
                                onPressed: () => _complete(ps),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
              ]);
            }),
    );
  }
}
