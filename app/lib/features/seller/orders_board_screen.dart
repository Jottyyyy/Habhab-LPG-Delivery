import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/theme.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';
import 'board.dart';
import 'seller_order_screen.dart';

/// App orders: New · Preparing · On the way · Done (today and yesterday).
class OrdersBoardScreen extends StatelessWidget {
  const OrdersBoardScreen({super.key, required this.board});
  final Board board;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ListenableBuilder(
        listenable: board,
        builder: (context, _) {
          List<Order> by(OrderStatus s) => board.active.where((o) => o.status == s).toList();
          final lists = [by(OrderStatus.pending), by(OrderStatus.confirmed), by(OrderStatus.onTheWay), board.done];
          String tab(String t, int n) => n > 0 ? '$t ($n)' : t;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Orders'),
              actions: [
                IconButton(
                  tooltip: board.keepAwake ? 'Screen stays on' : 'Keep screen on',
                  onPressed: () {
                    board.setKeepAwake(!board.keepAwake);
                    showSnack(context, board.keepAwake ? 'Screen will stay on while this app is open.' : 'Screen can turn off normally.');
                  },
                  icon: Icon(board.keepAwake ? Icons.light_mode : Icons.light_mode_outlined),
                ),
                IconButton(tooltip: 'Refresh', onPressed: board.refresh, icon: const Icon(Icons.refresh)),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: C.flame,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: tab('New', lists[0].length)),
                  Tab(text: tab('Preparing', lists[1].length)),
                  Tab(text: tab('On the way', lists[2].length)),
                  const Tab(text: 'Done'),
                ],
              ),
            ),
            body: !board.loaded
                ? (board.error != null ? ErrorRetry(message: board.error!, onRetry: board.refresh) : const Center(child: CircularProgressIndicator()))
                : Column(children: [
                    if (board.error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: NoteBanner(text: board.error!, icon: Icons.wifi_off, color: C.red, tint: C.redTint),
                      ),
                    Expanded(
                      child: TabBarView(children: [
                        for (var i = 0; i < 4; i++)
                          RefreshIndicator(
                            onRefresh: board.refresh,
                            child: lists[i].isEmpty
                                ? ListView(children: [
                                    EmptyState(
                                      icon: i == 0 ? Icons.notifications_none : Icons.inbox_outlined,
                                      title: ['No new orders', 'Nothing to prepare', 'No deliveries on the way', 'No finished orders yet'][i],
                                      message: i == 0 ? 'New orders ring here. Keep the app open.' : null,
                                    ),
                                  ])
                                : ListView.separated(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: lists[i].length,
                                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                                    itemBuilder: (context, j) => OrderTile(
                                      lists[i][j],
                                      showCustomer: true,
                                      onTap: () async {
                                        await Navigator.of(context).push(MaterialPageRoute<void>(
                                          builder: (_) => SellerOrderScreen(orderId: lists[i][j].id, riders: board.riders),
                                        ));
                                        board.refresh();
                                      },
                                    ),
                                  ),
                          ),
                      ]),
                    ),
                  ]),
          );
        },
      ),
    );
  }
}
