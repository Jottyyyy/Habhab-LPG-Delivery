import 'package:flutter/material.dart';

import '../../core/update_check.dart';
import 'board.dart';
import 'customers_screen.dart';
import 'gcash_screen.dart';
import 'more_screen.dart';
import 'orders_board_screen.dart';
import 'pos_screen.dart';

/// Store app (owner + staff): Orders · POS · Listahan · GCash · More.
class SellerShell extends StatefulWidget {
  const SellerShell({super.key});
  @override
  State<SellerShell> createState() => _SellerShellState();
}

class _SellerShellState extends State<SellerShell> {
  final board = Board();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    board.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));
  }

  @override
  void dispose() {
    board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: _tab, children: [
          OrdersBoardScreen(board: board),
          PosScreen(active: _tab == 1),
          CustomersScreen(active: _tab == 2),
          GcashScreen(active: _tab == 3, board: board),
          MoreScreen(board: board),
        ]),
        bottomNavigationBar: ListenableBuilder(
          listenable: board,
          builder: (context, _) => NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: board.pending > 0, label: Text('${board.pending}'), child: const Icon(Icons.receipt_long_outlined)),
                selectedIcon: Badge(isLabelVisible: board.pending > 0, label: Text('${board.pending}'), child: const Icon(Icons.receipt_long)),
                label: 'Orders',
              ),
              const NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'POS'),
              const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Listahan'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: board.gcashToCheck > 0,
                  label: Text('${board.gcashToCheck}'),
                  child: const Icon(Icons.account_balance_wallet_outlined),
                ),
                selectedIcon: const Icon(Icons.account_balance_wallet),
                label: 'GCash',
              ),
              const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
            ],
          ),
        ),
      ),
    );
  }
}
