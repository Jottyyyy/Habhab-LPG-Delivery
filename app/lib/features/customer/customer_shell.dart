import 'package:flutter/material.dart';

import '../../core/update_check.dart';
import 'account_screen.dart';
import 'cart.dart';
import 'listahan_screen.dart';
import 'my_orders_screen.dart';
import 'shop_screen.dart';

/// Customer app: Order · My orders · Listahan · Account.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  /// Switch tab from inside a screen (e.g. after placing an order → My orders).
  static void goTo(BuildContext context, int tab) => context.findAncestorStateOfType<_CustomerShellState>()?._go(tab);

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;
  final _keys = List.generate(4, (_) => GlobalKey());

  void _go(int i) => setState(() => _tab = i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdate(context));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _tab, children: [
          ShopScreen(key: _keys[0]),
          MyOrdersScreen(key: _keys[1], active: _tab == 1),
          ListahanScreen(key: _keys[2], active: _tab == 2),
          AccountScreen(key: _keys[3]),
        ]),
        bottomNavigationBar: ListenableBuilder(
          listenable: cart,
          builder: (context, _) => NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _go,
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: !cart.isEmpty, label: Text('${cart.count}'), child: const Icon(Icons.local_fire_department_outlined)),
                selectedIcon: const Icon(Icons.local_fire_department),
                label: 'Order',
              ),
              const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'My orders'),
              const NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Listahan'),
              const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
            ],
          ),
        ),
      ),
    );
  }
}
