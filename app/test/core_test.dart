import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habhab_lpg/core/models.dart';
import 'package:habhab_lpg/core/money.dart';
import 'package:habhab_lpg/core/update_check.dart';
import 'package:habhab_lpg/theme/theme.dart';
import 'package:habhab_lpg/ui/order_widgets.dart';

void main() {
  group('money', () {
    test('formats pesos like the server', () {
      expect(formatPeso(95000), '₱ 950');
      expect(formatPeso(192050), '₱ 1,920.50');
      expect(formatPeso(0, alwaysDecimals: true), '₱ 0.00');
      expect(formatPeso(-5000), '-₱ 50');
    });
    test('parses what people type', () {
      expect(parsePeso('950'), 95000);
      expect(parsePeso('₱ 1,050.5'), 105050);
      expect(parsePeso('1.234'), isNull);
      expect(parsePeso(''), isNull);
      expect(toPesoInput(105050), '1050.50');
      expect(toPesoInput(95000), '950');
    });
  });

  test('update check compares versions', () {
    expect(isNewer('1.0.1', '1.0.0'), isTrue);
    expect(isNewer('1.1.0', '1.0.9'), isTrue);
    expect(isNewer('1.0.0', '1.0.0'), isFalse);
    expect(isNewer('1.0.0+5', '1.0.0'), isFalse);
    expect(isNewer('0.9.9', '1.0.0'), isFalse);
  });

  group('order JSON', () {
    final json = {
      'id': 'o1',
      'ref': 'O-0001',
      'channel': 'app',
      'status': 'on_the_way',
      'paymentMethod': 'cash',
      'customerName': 'Ana',
      'subtotal': 190000,
      'deliveryFee': 2000,
      'total': 192000,
      'paid': 0,
      'pendingPaid': 0,
      'riderName': 'Ben',
      'rider': {'lat': 14.61, 'lng': 121.01, 'at': '2026-11-24T08:00:00.000Z'},
      'createdAt': '2026-11-24T07:00:00.000Z',
      'items': [
        {'productId': 'p1', 'name': 'LPG 11 kg', 'unitPrice': 95000, 'qty': 2, 'lineTotal': 190000},
      ],
    };

    test('reads status, rider location and items', () {
      final o = Order.fromJson(json);
      expect(o.status, OrderStatus.onTheWay);
      expect(o.isOpen, isTrue);
      expect(o.rider!.lat, 14.61);
      expect(o.itemsSummary, '2× LPG 11 kg');
      expect(o.unpaid, 192000);
    });

    testWidgets('timeline shows the steps done so far', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: StatusTimeline(Order.fromJson(json)))));
      expect(find.text('Order sent'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text('Ben is bringing it'), findsOneWidget);
      expect(find.text('Salamat po!'), findsNothing); // not delivered yet
    });

    testWidgets('receipt lines show totals', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(body: OrderLines(Order.fromJson(json)))));
      expect(find.text('₱ 1,920'), findsOneWidget);
      expect(find.text('Delivery fee'), findsOneWidget);
    });
  });
}
