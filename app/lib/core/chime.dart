import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// "Ding-dong" + vibration when a new order or GCash payment arrives (store side).
class Chime {
  Chime._();
  static final _player = AudioPlayer(playerId: 'habhab-chime');

  static Future<void> play() async {
    try {
      await HapticFeedback.heavyImpact();
      await _player.stop();
      await _player.play(AssetSource('sounds/chime.wav'), volume: 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Sound is a nice-to-have.
    }
  }
}
