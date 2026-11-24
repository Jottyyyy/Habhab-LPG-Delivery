import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api.dart';
import '../../core/chime.dart';
import '../../core/models.dart';
import '../../core/poller.dart';
import '../../core/session.dart';

/// The store's live board: open orders, today's finished ones and badge counts.
/// Checks the server every 15 seconds while the app is open, and rings when a new order
/// or a new GCash payment comes in.
class Board extends ChangeNotifier {
  List<Order> active = [];
  List<Order> done = [];
  List<StaffUser> riders = [];
  int pending = 0;
  int gcashToCheck = 0;
  String? error;
  bool loaded = false;
  bool keepAwake = false;

  final Set<String> _knownPending = {};
  int _lastGcash = 0;
  late final Poller _poller = Poller(const Duration(seconds: 15), refresh);

  static const _awakeKey = 'habhab.keepAwake';

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    keepAwake = prefs.getBool(_awakeKey) ?? false;
    if (keepAwake) await WakelockPlus.enable();
    _poller.start(now: true);
  }

  Future<void> setKeepAwake(bool on) async {
    keepAwake = on;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_awakeKey, on);
    on ? await WakelockPlus.enable() : await WakelockPlus.disable();
  }

  Future<void> refresh() async {
    try {
      final r = await session.api.get('/seller/orders');
      active = (r['active'] as List).map((e) => Order.fromJson(e as Json)).toList();
      done = (r['done'] as List).map((e) => Order.fromJson(e as Json)).toList();
      riders = (r['riders'] as List).map((e) => StaffUser.fromJson({...e as Json, 'phone': '', 'active': true})).toList();
      final counts = r['counts'] as Json;
      pending = (counts['pending'] as num).toInt();
      gcashToCheck = (counts['gcashToCheck'] as num).toInt();

      final pendingIds = active.where((o) => o.status == OrderStatus.pending).map((o) => o.id).toSet();
      final isNew = pendingIds.difference(_knownPending).isNotEmpty || gcashToCheck > _lastGcash;
      if (loaded && isNew) Chime.play();
      _knownPending
        ..clear()
        ..addAll(pendingIds);
      _lastGcash = gcashToCheck;
      loaded = true;
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _poller.dispose();
    WakelockPlus.disable();
    super.dispose();
  }
}
