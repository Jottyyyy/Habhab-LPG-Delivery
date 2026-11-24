import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs [tick] every [every] while the app is open and in front; pauses in the background
/// (keeps the free server limits low and saves battery) and runs once when the app comes back.
class Poller {
  Poller(this.every, this.tick);

  final Duration every;
  final Future<void> Function() tick;
  Timer? _timer;
  AppLifecycleListener? _life;
  bool _busy = false;

  void start({bool now = false}) {
    _life ??= AppLifecycleListener(onResume: () {
      _run();
      _schedule();
    }, onPause: _stopTimer, onHide: _stopTimer);
    _schedule();
    if (now) _run();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => _run());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run() async {
    if (_busy) return;
    _busy = true;
    try {
      await tick();
    } catch (_) {
      // The screen shows its own error; keep polling.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _stopTimer();
    _life?.dispose();
    _life = null;
  }
}
