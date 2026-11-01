import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Spoken German alerts plus vibration.
class Alerts {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  final Map<String, DateTime> _last = {};

  Future<void> init() async {
    try {
      await _tts.setLanguage('de-DE');
      await _tts.setSpeechRate(0.55);
      await _tts.awaitSpeakCompletion(false);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Speaks [text] unless the same [key] was spoken within [cooldown].
  Future<void> say(String key, String text, {required bool voice, Duration cooldown = const Duration(seconds: 8)}) async {
    final now = DateTime.now();
    final last = _last[key];
    if (last != null && now.difference(last) < cooldown) return;
    _last[key] = now;
    HapticFeedback.heavyImpact();
    if (voice && _ready) {
      await _tts.stop();
      await _tts.speak(text);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  void dispose() => _tts.stop();
}
