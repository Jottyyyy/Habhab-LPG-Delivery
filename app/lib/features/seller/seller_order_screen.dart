import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api.dart';
import '../../core/dates.dart';
import '../../core/launch.dart';
import '../../core/location.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../../core/poller.dart';
import '../../core/session.dart';
import '../../theme/theme.dart';
import '../../ui/maps.dart';
import '../../ui/order_widgets.dart';
import '../../ui/widgets.dart';

/// One order, store side: accept, start the delivery (shares this phone's GPS with the
/// customer while this screen is open), navigate, mark delivered, or cancel.
class SellerOrderScreen extends StatefulWidget {
  const SellerOrderScreen({super.key, required this.orderId, this.riders = const []});
  final String orderId;
  final List<StaffUser> riders;
  @override
  State<SellerOrderScreen> createState() => _SellerOrderScreenState();
}

class _SellerOrderScreenState extends State<SellerOrderScreen> with Loads<SellerOrderScreen, Order> {
  late final Poller _poller = Poller(const Duration(seconds: 20), () => reload(quiet: true));
  StreamSubscription<Position>? _gps;
  Position? _lastPos;
  DateTime? _lastSent;
  String? _gpsProblem;
  Timer? _sendTimer;

  @override
  void initState() {
    super.initState();
    reload().then((_) => _syncSharing());
    _poller.start();
  }

  @override
  void dispose() {
    _stopSharing();
    _poller.dispose();
    super.dispose();
  }

  @override
  Future<Order> fetch() async {
    final r = await session.api.get('/orders/${widget.orderId}');
    return Order.fromJson(r['order'] as Json);
  }

  bool get _mineToDeliver {
    final o = data;
    if (o == null || o.status != OrderStatus.onTheWay) return false;
    return o.riderId == null || o.riderId == session.user?.id;
  }

  /// Share GPS only while this order is on the way, this phone is the rider, and this screen is open.
  Future<void> _syncSharing() async {
    if (!mounted) return;
    if (_mineToDeliver) {
      if (_gps != null) return;
      final problem = await Gps.ensureReady();
      if (!mounted) return;
      if (problem != null) {
        setState(() => _gpsProblem = problem);
        return;
      }
      setState(() => _gpsProblem = null);
      await WakelockPlus.enable();
      final first = await Gps.current();
      if (first != null) {
        _lastPos = first;
        await _send();
      }
      _gps = Gps.stream().listen((p) {
        _lastPos = p;
        // At most every 10 seconds.
        if (_lastSent == null || DateTime.now().difference(_lastSent!).inSeconds >= 10) _send();
      }, onError: (_) {});
      // Also resend every 15s when standing still (keeps "updated Xs ago" fresh).
      _sendTimer = Timer.periodic(const Duration(seconds: 15), (_) => _send());
    } else {
      _stopSharing();
    }
  }

  Future<void> _send() async {
    final p = _lastPos;
    if (p == null) return;
    try {
      final r = await session.api.post('/orders/${widget.orderId}/location', {'lat': p.latitude, 'lng': p.longitude});
      _lastSent = DateTime.now();
      if (mounted) setState(() {});
      if (r['status'] != 'on_the_way') {
        _stopSharing();
        reload(quiet: true);
      }
    } catch (_) {
      // Weak signal: the next position will try again.
    }
  }

  void _stopSharing() {
    _gps?.cancel();
    _gps = null;
    _sendTimer?.cancel();
    _sendTimer = null;
    WakelockPlus.disable();
  }

  Future<void> _act(String action, [Json? body, String? done]) async {
    final r = await runAction(context, () => session.api.post('/orders/${widget.orderId}/$action', body ?? {}), done: done);
    if (r != null && mounted) {
      setState(() => data = Order.fromJson(r['order'] as Json));
      await _syncSharing();
    }
  }

  Future<void> _deliver(Order o) async {
    // What is still to collect: GCash the customer already sent (being checked) counts.
    final due = o.total - o.paid - o.pendingPaid;
    final paid = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Delivered ${o.ref} · ${formatPeso(o.total)}\nHow did the customer pay?',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined, color: C.green),
            title: const Text('Paid cash'),
            subtitle: Text(due > 0 ? 'Received ${formatPeso(due)}' : 'Nothing more to collect'),
            onTap: () => Navigator.pop(c, 'cash'),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined, color: C.navy),
            title: const Text('Paid by GCash'),
            subtitle: Text(o.pendingPaid > 0 ? 'Check it in the GCash tab' : 'I received it in GCash'),
            onTap: () => Navigator.pop(c, 'gcash'),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined, color: C.amber),
            title: const Text('Utang (listahan)'),
            subtitle: const Text('Not paid yet; add to their listahan'),
            onTap: () => Navigator.pop(c, 'utang'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (paid != null) await _act('deliver', {'paid': paid}, 'Delivered. Salamat!');
  }

  Future<void> _cancel(Order o) async {
    final reason = await askText(context, title: 'Cancel ${o.ref}?', hint: 'Reason (the customer sees this)', confirm: 'Cancel order');
    if (reason != null) await _act('cancel', {'reason': reason}, 'Order cancelled.');
  }

  Future<void> _assign(Order o) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Who will deliver?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          for (final r in widget.riders)
            ListTile(
              leading: const Icon(Icons.delivery_dining),
              title: Text(r.name),
              trailing: r.id == o.riderId ? const Icon(Icons.check, color: C.green) : null,
              onTap: () => Navigator.pop(c, r.id),
            ),
        ]),
      ),
    );
    if (id != null) await _act('assign', {'riderId': id}, 'Rider set.');
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = session.user?.isOwner == true;
    return Scaffold(
      appBar: AppBar(title: Text(data != null ? '${data!.isWalkin ? 'Sale' : 'Order'} ${data!.ref}' : 'Order')),
      body: loadBody((o) {
        final sharing = _gps != null;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
            children: [
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(o.customerName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                    StatusPill(o),
                  ]),
                  if (o.customerPhone != null) Text(o.customerPhone!, style: const TextStyle(color: C.muted)),
                  if (o.address != null) ...[
                    const SizedBox(height: 8),
                    Text(o.address!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (o.landmark != null) Text('Landmark: ${o.landmark}', style: const TextStyle(color: C.muted)),
                  ],
                  if (o.notes != null) ...[
                    const SizedBox(height: 6),
                    NoteBanner(text: 'Note: ${o.notes}', icon: Icons.sticky_note_2_outlined, color: C.navy, tint: C.navyTint),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    if (o.customerPhone != null)
                      Expanded(
                        child: OutlinedButton.icon(onPressed: () => Launch.call(o.customerPhone!), icon: const Icon(Icons.call), label: const Text('Call')),
                      ),
                    if (o.customerPhone != null && o.hasPin) const SizedBox(width: 10),
                    if (o.hasPin)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Launch.directions(o.lat!, o.lng!),
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('Navigate'),
                        ),
                      ),
                  ]),
                ]),
              ),
              if (o.hasPin && !o.isWalkin) ...[
                const SizedBox(height: 10),
                SpotMap(
                  lat: o.lat!,
                  lng: o.lng!,
                  riderLat: o.status == OrderStatus.onTheWay ? (_lastPos?.latitude ?? o.rider?.lat) : null,
                  riderLng: o.status == OrderStatus.onTheWay ? (_lastPos?.longitude ?? o.rider?.lng) : null,
                  height: 200,
                  interactive: true,
                ),
              ] else if (!o.isWalkin) ...[
                const SizedBox(height: 10),
                const NoteBanner(text: 'No map pin for this order. Call the customer for directions.'),
              ],
              if (o.status == OrderStatus.onTheWay) ...[
                const SizedBox(height: 10),
                if (_gpsProblem != null)
                  NoteBanner(
                    text: _gpsProblem!,
                    color: C.red,
                    tint: C.redTint,
                    icon: Icons.location_off,
                    action: TextButton(onPressed: () async {
                      await Gps.openSettings();
                      _syncSharing();
                    }, child: const Text('Fix')),
                  )
                else if (sharing)
                  NoteBanner(
                    icon: Icons.my_location,
                    color: C.green,
                    tint: C.greenTint,
                    text: 'Sharing your location with the customer${_lastSent != null ? ' · sent ${agoText(_lastSent)}' : ''}.\nKeep this screen open while delivering.',
                  )
                else
                  NoteBanner(text: o.riderName != null ? '${o.riderName} is delivering this order.' : 'On the way.', icon: Icons.delivery_dining, color: C.navy, tint: C.navyTint),
              ],
              const SizedBox(height: 12),
              AppCard(child: OrderLines(o)),
              const SizedBox(height: 12),
              AppCard(child: StatusTimeline(o)),
              const SizedBox(height: 16),
              ..._actions(o, isOwner),
            ],
          ),
        );
      }),
    );
  }

  List<Widget> _actions(Order o, bool isOwner) {
    const gap = SizedBox(height: 10);
    switch (o.status) {
      case OrderStatus.pending:
        return [
          BusyButton(label: 'Accept order', icon: Icons.check, onPressed: () => _act('confirm', null, 'Accepted. The customer can see it.')),
          gap,
          OutlinedButton.icon(onPressed: () => _act('start'), icon: const Icon(Icons.delivery_dining), label: const Text('Accept and deliver now')),
          gap,
          TextButton(style: TextButton.styleFrom(foregroundColor: C.red), onPressed: () => _cancel(o), child: const Text('Cancel order')),
        ];
      case OrderStatus.confirmed:
        return [
          BusyButton(label: 'Start delivery', icon: Icons.delivery_dining, color: C.flame, onPressed: () => _act('start', null, 'On the way! Your location is shared.')),
          gap,
          if (isOwner && widget.riders.length > 1) ...[
            OutlinedButton.icon(onPressed: () => _assign(o), icon: const Icon(Icons.person_pin_circle_outlined), label: Text(o.riderName != null ? 'Rider: ${o.riderName}' : 'Choose rider')),
            gap,
          ],
          TextButton(style: TextButton.styleFrom(foregroundColor: C.red), onPressed: () => _cancel(o), child: const Text('Cancel order')),
        ];
      case OrderStatus.onTheWay:
        return [
          BusyButton(label: 'Delivered', icon: Icons.check_circle, color: C.green, onPressed: () => _deliver(o)),
          gap,
          if (isOwner && widget.riders.length > 1) ...[
            OutlinedButton.icon(onPressed: () => _assign(o), icon: const Icon(Icons.person_pin_circle_outlined), label: Text(o.riderName != null ? 'Rider: ${o.riderName}' : 'Choose rider')),
            gap,
          ],
          TextButton(style: TextButton.styleFrom(foregroundColor: C.red), onPressed: () => _cancel(o), child: const Text('Cancel order')),
        ];
      case OrderStatus.delivered:
        return [
          if (isOwner)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: C.red),
              onPressed: () async {
                final reason = await askText(context, title: 'Void ${o.ref}?', hint: 'Why? (e.g. wrong entry)', confirm: 'Void sale');
                if (reason != null) await _act('cancel', {'reason': reason}, 'Voided. Stock and listahan corrected.');
              },
              child: const Text('Void this sale (owner)'),
            ),
        ];
      case OrderStatus.cancelled:
        return const [];
    }
  }
}
