import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/dates.dart';
import '../../core/launch.dart';
import '../../core/models.dart';
import '../../core/poller.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'pay_gcash_screen.dart';

/// One order, for the customer: live status, the rider on the map while on the way,
/// pay by GCash, or cancel while the store hasn't accepted it yet.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with Loads<OrderScreen, Order> {
  // Every 10s while on the way (rider moves), otherwise every 20s.
  late final Poller _fast = Poller(const Duration(seconds: 10), () async {
    if (data?.status == OrderStatus.onTheWay) await reload(quiet: true);
  });
  late final Poller _slow = Poller(const Duration(seconds: 20), () async {
    if (data != null && data!.isOpen && data!.status != OrderStatus.onTheWay) await reload(quiet: true);
  });
  StoreInfo? _store;

  @override
  void initState() {
    super.initState();
    reload();
    _fast.start();
    _slow.start();
  }

  @override
  void dispose() {
    _fast.dispose();
    _slow.dispose();
    super.dispose();
  }

  @override
  Future<Order> fetch() async {
    final r = await session.api.get('/orders/${widget.orderId}');
    return Order.fromJson(r['order'] as Json);
  }

  Future<StoreInfo> _storeInfo() async {
    return _store ??= StoreInfo.fromJson((await session.api.get('/store'))['store'] as Json);
  }

  Future<void> _payGcash(Order o) async {
    final store = await runAction(context, _storeInfo);
    if (store == null || !mounted) return;
    final due = o.total - o.paid - o.pendingPaid;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PayGcashScreen(store: store, amount: due, order: o)));
    reload(quiet: true);
  }

  Future<void> _cancel(Order o) async {
    final ok = await confirmDialog(context, title: 'Cancel order ${o.ref}?', confirm: 'Cancel order', danger: true);
    if (!ok || !mounted) return;
    final r = await runAction(context, () => session.api.post('/orders/${o.id}/cancel', {}), done: 'Order cancelled.');
    if (r != null) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(data != null ? 'Order ${data!.ref}' : 'Order')),
      body: loadBody((o) {
        final onTheWay = o.status == OrderStatus.onTheWay;
        final due = o.total - o.paid - o.pendingPaid;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            children: [
              if (onTheWay) ...[
                if (o.hasPin)
                  SpotMap(lat: o.lat!, lng: o.lng!, riderLat: o.rider?.lat, riderLng: o.rider?.lng, height: 300, interactive: true)
                else if (o.rider != null)
                  SpotMap(lat: o.rider!.lat, lng: o.rider!.lng, riderLat: o.rider!.lat, riderLng: o.rider!.lng, height: 300, interactive: true),
                const SizedBox(height: 8),
                AppCard(
                  color: C.navy,
                  child: Row(children: [
                    const Icon(Icons.delivery_dining, color: Colors.white, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.riderName != null ? '${o.riderName} is on the way' : 'Paparating na!',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          o.rider?.at != null ? 'Rider location updated ${agoText(o.rider!.at)}' : 'Waiting for the rider\'s location…',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ]),
                    ),
                    if (o.riderPhone != null)
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: C.flame),
                        onPressed: () => Launch.call(o.riderPhone!),
                        icon: const Icon(Icons.call),
                        tooltip: 'Call the rider',
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              AppCard(child: StatusTimeline(o)),
              const SizedBox(height: 12),
              AppCard(child: OrderLines(o)),
              const SizedBox(height: 12),
              if (o.address != null)
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Deliver to', style: TextStyle(fontWeight: FontWeight.w700, color: C.navy)),
                    const SizedBox(height: 4),
                    Text(o.address!),
                    if (o.landmark != null) Text('Landmark: ${o.landmark}', style: const TextStyle(color: C.muted)),
                    if (o.notes != null) Text('Note: ${o.notes}', style: const TextStyle(color: C.muted)),
                    if (o.hasPin && !onTheWay) ...[const SizedBox(height: 8), SpotMap(lat: o.lat!, lng: o.lng!, height: 140)],
                  ]),
                ),
              const SizedBox(height: 16),
              if (o.status != OrderStatus.cancelled && o.paymentMethod == 'gcash' && due > 0) ...[
                BusyButton(label: 'Send GCash payment', icon: Icons.account_balance_wallet_outlined, onPressed: () => _payGcash(o)),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  final s = await runAction(context, _storeInfo);
                  await Launch.call(s?.phone ?? AppConfig.defaultStorePhone);
                },
                icon: const Icon(Icons.call_outlined),
                label: const Text('Call the store'),
              ),
              if (o.status == OrderStatus.pending) ...[
                const SizedBox(height: 10),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: C.red),
                  onPressed: () => _cancel(o),
                  child: const Text('Cancel this order'),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}
