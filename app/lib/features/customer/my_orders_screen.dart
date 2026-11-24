import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'customer_shell.dart';
import 'order_screen.dart';

/// The customer's orders, newest first.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, required this.active});
  final bool active;
  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with Loads<MyOrdersScreen, List<Order>> {
  @override
  void initState() {
    super.initState();
    if (widget.active) reload();
  }

  @override
  void didUpdateWidget(MyOrdersScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) WidgetsBinding.instance.addPostFrameCallback((_) => reload(quiet: data != null));
  }

  @override
  Future<List<Order>> fetch() async {
    final r = await session.api.get('/me/orders');
    return (r['orders'] as List).map((e) => Order.fromJson(e as Json)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: !widget.active && data == null
          ? const SizedBox.shrink()
          : loadBody((orders) => RefreshIndicator(
                onRefresh: reload,
                child: orders.isEmpty
                    ? ListView(children: [
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No orders yet',
                          message: 'Your gasul orders will show here.',
                          action: SizedBox(
                            width: 200,
                            child: FilledButton(onPressed: () => CustomerShell.goTo(context, 0), child: const Text('Order gasul')),
                          ),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => OrderTile(
                          orders[i],
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: orders[i].id)));
                            reload(quiet: true);
                          },
                        ),
                      ),
              )),
    );
  }
}
