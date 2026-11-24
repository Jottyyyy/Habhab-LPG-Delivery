import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import 'customer_form_screen.dart';

/// Search sheet to choose a customer (POS utang sale), or add a new suki.
Future<Customer?> pickCustomer(BuildContext context) => showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _Picker()),
    );

class _Picker extends StatefulWidget {
  const _Picker();
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  List<Customer> _list = [];
  String? _error;
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await session.api.get('/customers', query: {'q': q});
      if (!mounted) return;
      setState(() {
        _list = (r['customers'] as List).map((e) => Customer.fromJson(e as Json)).toList();
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, number or address'),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
          },
        ),
      ),
      ListTile(
        leading: const CircleAvatar(backgroundColor: C.navyTint, child: Icon(Icons.person_add_alt, color: C.navy)),
        title: const Text('Add new suki', style: TextStyle(fontWeight: FontWeight.w700)),
        onTap: () async {
          final c = await Navigator.of(context).push<Customer>(MaterialPageRoute(builder: (_) => const CustomerFormScreen()));
          if (c != null && context.mounted) Navigator.pop(context, c);
        },
      ),
      const Divider(),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: C.red))),
      Expanded(
        child: ListView.builder(
          itemCount: _list.length,
          itemBuilder: (context, i) {
            final c = _list[i];
            return ListTile(
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([c.phone, c.address].whereType<String>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: c.balance > 0 ? Text(formatPeso(c.balance), style: const TextStyle(color: C.amber, fontWeight: FontWeight.w700)) : null,
              onTap: () => Navigator.pop(context, c),
            );
          },
        ),
      ),
    ]);
  }
}
