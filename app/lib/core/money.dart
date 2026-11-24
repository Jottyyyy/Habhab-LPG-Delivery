/// Money helpers. All amounts are integer centavos (₱ 1.00 = 100). Mirrors api/_lib/money.ts.
library;

import 'package:intl/intl.dart';

final _group = NumberFormat('#,##0', 'en_US');

/// "₱ 1,050" (centavos only when not zero) or "₱ 1,050.00" with [alwaysDecimals].
String formatPeso(int c, {bool alwaysDecimals = false}) {
  final sign = c < 0 ? '-' : '';
  final abs = c.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  final showFrac = alwaysDecimals || frac != 0;
  return '$sign₱ ${_group.format(whole)}${showFrac ? '.${frac.toString().padLeft(2, '0')}' : ''}';
}

/// Parse a typed amount ("1,050.50", "950", "₱ 1,000") into centavos; null when not valid.
int? parsePeso(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₱,\s]'), '');
  if (cleaned.isEmpty || cleaned == '.') return null;
  if (!RegExp(r'^\d*(\.\d{0,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
  final frac = parts.length > 1 ? int.parse('${parts[1]}00'.substring(0, 2)) : 0;
  return whole * 100 + frac;
}

/// Centavos → text for an input field ("950", "950.50").
String toPesoInput(int c) {
  final frac = c % 100;
  return frac == 0 ? '${c ~/ 100}' : '${c ~/ 100}.${frac.toString().padLeft(2, '0')}';
}
