import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';

/// Owner's report: sales (app + walk-in), what sold, money collected, and utang to collect.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

enum _Period { today, yesterday, week, month, custom }

class _ReportsScreenState extends State<ReportsScreen> with Loads<ReportsScreen, Json> {
  _Period _period = _Period.today;
  DateTimeRange? _custom;

  @override
  void initState() {
    super.initState();
    reload();
  }

  DateTimeRange get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.today => DateTimeRange(start: today, end: today),
      _Period.yesterday => DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      _Period.week => DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today),
      _Period.month => DateTimeRange(start: DateTime(now.year, now.month), end: today),
      _Period.custom => _custom ?? DateTimeRange(start: today, end: today),
    };
  }

  @override
  Future<Json> fetch() => session.api.get('/reports', query: {'from': dayKey(_range.start), 'to': dayKey(_range.end)});

  Future<void> _choose(_Period p) async {
    if (p == _Period.custom) {
      final now = DateTime.now();
      final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: now, initialDateRange: _custom);
      if (r == null) return;
      _custom = r;
    }
    setState(() {
      _period = p;
      data = null;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    final label = r.start == r.end ? formatDate(r.start) : '${formatDate(r.start)} – ${formatDate(r.end)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final (p, t) in [
                (_Period.today, 'Today'),
                (_Period.yesterday, 'Yesterday'),
                (_Period.week, 'This week'),
                (_Period.month, 'This month'),
                (_Period.custom, 'Choose dates'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(t), selected: _period == p, onSelected: (_) => _choose(p)),
                ),
            ],
          ),
        ),
        Expanded(
          child: loadBody((d) {
            final sales = d['sales'] as Json;
            final collected = d['collected'] as Json;
            final utang = d['utang'] as Json;
            final items = (d['items'] as List).cast<Json>();
            final top = (utang['top'] as List).cast<Json>();
            int n(Object? v) => (v as num?)?.toInt() ?? 0;
            Widget stat(String title, int value, {String? sub, Color color = C.navy}) => Expanded(
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      FittedBox(child: Text(formatPeso(value), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color))),
                      if (sub != null) Text(sub, style: const TextStyle(color: C.muted, fontSize: 12)),
                    ]),
                  ),
                );
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
                  const SizedBox(height: 8),
                  Row(children: [
                    stat('Total sales', n(sales['total']), sub: plural(n(sales['count']), 'sale')),
                    const SizedBox(width: 8),
                    stat('Money collected', n(collected['total']), color: C.green, sub: 'Cash + GCash'),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    stat('App orders', n((sales['app'] as Json)['total']), sub: '${n((sales['app'] as Json)['count'])} delivered'),
                    const SizedBox(width: 8),
                    stat('Walk-in (POS)', n((sales['walkin'] as Json)['total']), sub: plural(n((sales['walkin'] as Json)['count']), 'sale')),
                  ]),
                  const SectionTitle('Collected'),
                  AppCard(
                    child: Column(children: [
                      InfoRow('Cash', formatPeso(n(collected['cash']))),
                      InfoRow('GCash (confirmed)', formatPeso(n(collected['gcash']))),
                      if (n(sales['deliveryFees']) > 0) InfoRow('Delivery fees in sales', formatPeso(n(sales['deliveryFees']))),
                      InfoRow('Sold on utang', formatPeso(n((sales['byMethod'] as Json)['utang'])), color: C.amber),
                    ]),
                  ),
                  const SectionTitle('What sold'),
                  AppCard(
                    child: items.isEmpty
                        ? const Text('No sales in this period.', style: TextStyle(color: C.muted))
                        : Column(children: [
                            for (final i in items)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  SizedBox(width: 40, child: Text('${n(i['qty'])}×', style: const TextStyle(fontWeight: FontWeight.w800))),
                                  Expanded(child: Text(i['name'] as String)),
                                  Text(formatPeso(n(i['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ]),
                              ),
                          ]),
                  ),
                  SectionTitle('Utang to collect (all time) · ${formatPeso(n(utang['total']))}'),
                  AppCard(
                    child: top.isEmpty
                        ? const Text('Walang utang. 🎉', style: TextStyle(color: C.muted))
                        : Column(children: [
                            for (final c in top) InfoRow(c['name'] as String, formatPeso(n(c['balance']))),
                            if (n(utang['customers']) > top.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('and ${n(utang['customers']) - top.length} more in Listahan', style: const TextStyle(color: C.muted)),
                              ),
                          ]),
                  ),
                ],
              ),
            );
          }),
        ),
      ]),
    );
  }
}
