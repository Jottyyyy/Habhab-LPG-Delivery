import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/widgets.dart';

/// Owner: products, prices and stock. Hidden products (or no price) are not shown to customers.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> with Loads<ProductsScreen, List<Product>> {
  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<List<Product>> fetch() async =>
      ((await session.api.get('/products'))['products'] as List).map((e) => Product.fromJson(e as Json)).toList();

  Future<void> _edit([Product? p]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _ProductForm(product: p)));
    if (saved == true) reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products & prices')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add product')),
      body: loadBody((ps) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              children: [
                if (ps.any((p) => p.price == null || !p.active))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: NoteBanner(text: 'Products marked "Hidden" are not shown to customers. Tap one, set the price and turn on "Show to customers".'),
                  ),
                for (final p in ps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => _edit(p),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Icon(p.kind == 'accessory' ? Icons.build_circle_outlined : Icons.propane_tank_outlined, color: p.active ? C.flame : C.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.active ? C.ink : C.muted)),
                            Text('${p.kindLabel}${p.stock != null ? ' · ${p.stock} in stock' : ''}', style: const TextStyle(color: C.muted, fontSize: 13)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(p.price != null ? formatPeso(p.price!) : 'No price', style: TextStyle(fontWeight: FontWeight.w800, color: p.price != null ? C.navy : C.red)),
                          if (!p.active) const Pill('Hidden', color: C.muted, tint: C.cream),
                        ]),
                      ]),
                    ),
                  ),
              ],
            ),
          )),
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({this.product});
  final Product? product;
  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  late final p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _desc = TextEditingController(text: p?.description);
  late final _price = TextEditingController(text: p?.price != null ? toPesoInput(p!.price!) : '');
  late final _stock = TextEditingController(text: p?.stock?.toString() ?? '');
  late String _kind = p?.kind ?? 'refill';
  late bool _active = p?.active ?? true;
  late bool _trackStock = p?.stock != null;

  Future<void> _save() async {
    final price = _price.text.trim().isEmpty ? null : parsePeso(_price.text);
    if (_price.text.trim().isNotEmpty && price == null) {
      showSnack(context, 'Check the price.', error: true);
      return;
    }
    final stock = _trackStock ? int.tryParse(_stock.text.trim()) : null;
    if (_trackStock && stock == null) {
      showSnack(context, 'Enter how many are in stock.', error: true);
      return;
    }
    final body = {
      'name': _name.text.trim(),
      'kind': _kind,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'price': price,
      'stock': stock,
      'active': _active && price != null,
    };
    final r = await runAction(
      context,
      () => p == null ? session.api.post('/products', body) : session.api.patch('/products/${p!.id}', body),
      done: _active && price == null ? 'Saved (hidden until it has a price).' : 'Saved.',
    );
    if (r != null && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p == null ? 'Add product' : 'Edit product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Name (e.g. Petron Gasul 11 kg refill)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'refill', child: Text('Refill / palit tangke')),
              DropdownMenuItem(value: 'new_tank', child: Text('New tank (with cylinder)')),
              DropdownMenuItem(value: 'accessory', child: Text('Accessory (regulator, hose…)')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'refill'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Short description (optional)')),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Price', prefixText: '₱ '),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _trackStock,
            onChanged: (v) => setState(() => _trackStock = v),
            title: const Text('Count stock'),
            subtitle: const Text('Stock goes down with every sale. Customers can\'t order when it is 0.'),
          ),
          if (_trackStock)
            TextField(controller: _stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Full tanks / pieces in stock now')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Show to customers'),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Save', onPressed: _save),
        ],
      ),
    );
  }
}
