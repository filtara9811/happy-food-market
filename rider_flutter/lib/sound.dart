import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Ring / ding sounds bundled in the app (work offline).
class Sound {
  static final _p = AudioPlayer();
  static bool on = true;

  /// New request: a warm three-note bell, rung 3 times, with a strong buzz on each ring.
  static Future<void> ring3() async {
    if (on) {
      try {
        await _p.stop();
        await _p.play(AssetSource('sounds/ring3.wav'), volume: 1.0);
      } catch (_) {}
    }
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 160), HapticFeedback.heavyImpact);
      await Future.delayed(const Duration(milliseconds: 1150));
    }
  }

  static Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
  }

  static Future<void> ding() async {
    HapticFeedback.mediumImpact();
    if (!on) return;
    try {
      await _p.stop();
      await _p.play(AssetSource('sounds/ding.wav'), volume: .8);
    } catch (_) {}
  }
}
