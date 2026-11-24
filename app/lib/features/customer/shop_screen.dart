import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/poller.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';
import 'cart.dart';
import 'checkout_screen.dart';
import 'customer_shell.dart';
import 'order_screen.dart';

class ShopData {
  ShopData(this.store, this.products, this.openOrders, this.balance, this.utangAllowed, this.creditLimit);
  final StoreInfo store;
  final List<Product> products;
  final List<Order> openOrders;
  final int balance;
  final bool utangAllowed;
  final int? creditLimit;
}

/// Customer home: store open/closed, the order in progress, and the products to order.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => ShopScreenState();
}

class ShopScreenState extends State<ShopScreen> with Loads<ShopScreen, ShopData> {
  late final Poller _poller = Poller(const Duration(seconds: 20), () => reload(quiet: true));

  @override
  void initState() {
    super.initState();
    reload();
    _poller.start();
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  @override
  Future<ShopData> fetch() async {
    final r = await Future.wait([session.api.get('/store'), session.api.get('/me/orders'), session.api.get('/me/profile')]);
    final products = (r[0]['products'] as List).map((e) => Product.fromJson(e as Json)).toList();
    cart.sync(products);
    final orders = (r[1]['orders'] as List).map((e) => Order.fromJson(e as Json)).where((o) => o.isOpen).toList();
    final profile = r[2]['profile'] as Json;
    return ShopData(
      StoreInfo.fromJson(r[0]['store'] as Json),
      products,
      orders,
      (profile['balance'] as num?)?.toInt() ?? 0,
      profile['utangAllowed'] == true,
      (profile['creditLimit'] as num?)?.toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = session.user?.name.split(' ').first ?? '';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(children: [
          Container(
            decoration: const BoxDecoration(color: C.cream, shape: BoxShape.circle),
            padding: const EdgeInsets.all(5),
            child: Image.asset('assets/brand/flame.png', height: 34),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Habhab LPG', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              Text('${greeting()}, $name!', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white70)),
            ]),
          ),
        ]),
      ),
      body: loadBody((d) => RefreshIndicator(
            onRefresh: reload,
            child: ListenableBuilder(
              listenable: cart,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
                children: [
                  if (!d.store.isOpen) ...[
                    NoteBanner(
                      icon: Icons.storefront_outlined,
                      color: C.red,
                      tint: C.redTint,
                      text: d.store.closedMessage ?? 'The store is closed right now. You can order again when it opens.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final o in d.openOrders) ...[
                    _ActiveOrderCard(order: o, onTap: () => _openOrder(o)),
                    const SizedBox(height: 10),
                  ],
                  if (d.balance > 0) ...[
                    AppCard(
                      onTap: () => CustomerShell.goTo(context, 2),
                      color: C.amberTint,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        const Icon(Icons.menu_book, color: C.amber),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Your listahan (utang)', style: TextStyle(fontWeight: FontWeight.w600))),
                        Text(formatPeso(d.balance), style: const TextStyle(fontWeight: FontWeight.w800, color: C.amber)),
                        const Icon(Icons.chevron_right, color: C.amber),
                      ]),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SectionTitle('Order gasul'),
                  if (d.products.isEmpty)
                    const EmptyState(
                      icon: Icons.local_fire_department_outlined,
                      title: 'No products yet',
                      message: 'The store is still setting up prices. Please check again later or call the store.',
                    ),
                  for (final p in d.products) ...[
                    _ProductCard(product: p, enabled: d.store.isOpen),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          )),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ListenableBuilder(
        listenable: cart,
        builder: (context, _) {
          final d = data;
          if (cart.isEmpty || d == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: C.flame, minimumSize: const Size.fromHeight(56)),
              onPressed: d.store.isOpen ? () => _checkout(d) : null,
              child: Row(children: [
                Badge(label: Text('${cart.count}'), backgroundColor: Colors.white, textColor: C.flame, child: const Icon(Icons.shopping_cart_outlined)),
                const SizedBox(width: 14),
                const Expanded(child: Text('Review order')),
                Text(formatPeso(cart.subtotal)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openOrder(Order o) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: o.id)));
    reload(quiet: true);
  }

  Future<void> _checkout(ShopData d) async {
    final placed = await Navigator.of(context).push<Order>(
      MaterialPageRoute(builder: (_) => CheckoutScreen(store: d.store, utangAllowed: d.utangAllowed, balance: d.balance, creditLimit: d.creditLimit)),
    );
    if (placed != null && mounted) {
      await reload(quiet: true);
      if (mounted) await _openOrder(placed);
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.enabled});
  final Product product;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final qty = cart.qtyOf(p.id);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: C.cream, borderRadius: BorderRadius.circular(14)),
          child: Icon(
            p.kind == 'accessory' ? Icons.build_circle_outlined : Icons.propane_tank_outlined,
            color: p.kind == 'accessory' ? C.navy : C.flame,
            size: 32,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (p.description != null) Text(p.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Row(children: [
              Text(formatPeso(p.price ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: C.navy)),
              if (p.outOfStock) ...[const SizedBox(width: 8), const Pill('Out of stock', color: C.red, tint: C.redTint)],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (!p.outOfStock && enabled)
          qty == 0
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(76, 44), backgroundColor: C.flame),
                  onPressed: () => cart.set(p, 1),
                  child: const Text('Add'),
                )
              : QtyStepper(qty: qty, max: p.stock != null ? p.stock!.clamp(1, 99) : 99, onChanged: (q) => cart.set(p, q)),
      ]),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onTap});
  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onTheWay = order.status == OrderStatus.onTheWay;
    return AppCard(
      onTap: onTap,
      color: onTheWay ? C.navy : Colors.white,
      child: Row(children: [
        Icon(onTheWay ? Icons.delivery_dining : Icons.receipt_long, color: onTheWay ? Colors.white : C.navy, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              onTheWay ? 'Paparating na! Your gasul is on the way' : 'Order ${order.ref}: ${statusLabel(order.status)}',
              style: TextStyle(fontWeight: FontWeight.w800, color: onTheWay ? Colors.white : C.ink),
            ),
            Text(
              onTheWay ? 'Tap to see the rider on the map' : order.itemsSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onTheWay ? Colors.white70 : C.muted),
            ),
          ]),
        ),
        if (!onTheWay) StatusPill(order) else const Icon(Icons.chevron_right, color: Colors.white),
      ]),
    );
  }
}
