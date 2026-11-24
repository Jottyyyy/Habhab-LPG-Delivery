import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

class CustomerList {
  CustomerList(this.customers, this.totalUtang);
  final List<Customer> customers;
  final int totalUtang;
}

/// Listahan: every customer (app + walk-in suki), with who owes the most on top.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.active});
  final bool active;
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> with Loads<CustomersScreen, CustomerList> {
  String _q = '';
  bool _owingOnly = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.active) reload();
  }

  @override
  void didUpdateWidget(CustomersScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) WidgetsBinding.instance.addPostFrameCallback((_) => reload(quiet: data != null));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Future<CustomerList> fetch() async {
    final r = await session.api.get('/customers', query: {'q': _q});
    final list = (r['customers'] as List).map((e) => Customer.fromJson(e as Json)).toList()
      ..sort((a, b) => b.balance != a.balance ? b.balance.compareTo(a.balance) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return CustomerList(list, (r['totalUtang'] as num?)?.toInt() ?? 0);
  }

  Future<void> _open(Customer c) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CustomerDetailScreen(customerId: c.id)));
    reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listahan')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addSuki',
        onPressed: () async {
          final c = await Navigator.of(context).push<Customer>(MaterialPageRoute(builder: (_) => const CustomerFormScreen()));
          if (c != null) {
            reload(quiet: true);
            if (mounted) _open(c);
          }
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add suki'),
      ),
      body: !widget.active && data == null
          ? const SizedBox.shrink()
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, number or address', isDense: true),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 350), () {
                      _q = v.trim();
                      reload(quiet: true);
                    });
                  },
                ),
              ),
              Expanded(
                child: loadBody((d) {
                  final list = _owingOnly ? d.customers.where((c) => c.balance > 0).toList() : d.customers;
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                      children: [
                        AppCard(
                          color: C.navy,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(children: [
                            const Expanded(child: Text('Total utang to collect', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
                            Text(formatPeso(d.totalUtang), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          FilterChip(label: const Text('With utang only'), selected: _owingOnly, onSelected: (v) => setState(() => _owingOnly = v)),
                          const Spacer(),
                          Text('${list.length} customers', style: const TextStyle(color: C.muted)),
                        ]),
                        const SizedBox(height: 6),
                        if (list.isEmpty) const EmptyState(icon: Icons.people_outline, title: 'No customers found'),
                        for (final c in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              onTap: () => _open(c),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(children: [
                                CircleAvatar(
                                  backgroundColor: c.hasApp ? C.navyTint : C.cream,
                                  child: Icon(c.hasApp ? Icons.phone_android : Icons.storefront, color: c.hasApp ? C.navy : C.gold, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                      if (c.blocked) ...[const SizedBox(width: 6), const Pill('Blocked', color: C.red, tint: C.redTint)],
                                    ]),
                                    Text([c.phone, c.address].whereType<String>().join(' · '),
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 13)),
                                  ]),
                                ),
                                if (c.balance != 0)
                                  Text(formatPeso(c.balance), style: TextStyle(fontWeight: FontWeight.w800, color: c.balance > 0 ? C.amber : C.green)),
                              ]),
                            ),
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
