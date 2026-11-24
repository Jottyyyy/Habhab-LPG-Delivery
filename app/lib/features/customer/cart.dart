import 'package:flutter/foundation.dart';

import '../../core/models.dart';

/// What the customer is about to order (kept while they move between tabs).
class Cart extends ChangeNotifier {
  final Map<String, int> _qty = {};
  final Map<String, Product> _products = {};

  int qtyOf(String productId) => _qty[productId] ?? 0;
  bool get isEmpty => _qty.isEmpty;
  int get count => _qty.values.fold(0, (a, b) => a + b);

  List<(Product, int)> get lines => [
        for (final e in _qty.entries)
          if (_products[e.key] != null) (_products[e.key]!, e.value),
      ];

  int get subtotal => lines.fold(0, (sum, l) => sum + (l.$1.price ?? 0) * l.$2);

  void set(Product p, int qty) {
    _products[p.id] = p;
    if (qty <= 0) {
      _qty.remove(p.id);
    } else {
      _qty[p.id] = qty;
    }
    notifyListeners();
  }

  /// Keep prices fresh and drop items the store no longer sells.
  void sync(List<Product> current) {
    final byId = {for (final p in current) p.id: p};
    var changed = false;
    for (final id in _qty.keys.toList()) {
      final p = byId[id];
      if (p == null || p.outOfStock) {
        _qty.remove(id);
        changed = true;
      } else {
        _products[id] = p;
      }
    }
    if (changed) notifyListeners();
  }

  void clear() {
    _qty.clear();
    notifyListeners();
  }

  List<Map<String, Object>> toJson() => [for (final e in _qty.entries) {'productId': e.key, 'qty': e.value}];
}

final cart = Cart();
