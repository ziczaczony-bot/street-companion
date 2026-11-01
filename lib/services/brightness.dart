import 'package:screen_brightness/screen_brightness.dart';

/// Sets the app's screen brightness from the light the camera sees.
/// Dark tunnel or night -> dim screen; bright day -> full brightness.
class AutoBrightness {
  double? _ambient; // smoothed camera luminance 0..255
  double _applied = -1;

  double? get ambient => _ambient;

  /// True when it is dark outside (used for night colours).
  bool get isDark => (_ambient ?? 128) < 55;

  void addSample(double luma) {
    _ambient = _ambient == null ? luma : _ambient! * 0.9 + luma * 0.1;
  }

  static double brightnessFor(double luma) {
    if (luma <= 30) return 0.15;
    if (luma >= 150) return 1.0;
    return 0.15 + (luma - 30) / 120 * 0.85;
  }

  Future<void> apply({required bool enabled}) async {
    try {
      if (!enabled) {
        if (_applied >= 0) {
          _applied = -1;
          await ScreenBrightness.instance.resetApplicationScreenBrightness();
        }
        return;
      }
      final a = _ambient;
      final target = a == null ? _timeOfDayBrightness() : brightnessFor(a);
      if ((target - _applied).abs() < 0.05) return;
      _applied = target;
      await ScreenBrightness.instance.setApplicationScreenBrightness(target);
    } catch (_) {
      // Not supported on this device: ignore.
    }
  }

  static double _timeOfDayBrightness() {
    final h = DateTime.now().hour;
    return (h >= 7 && h < 19) ? 1.0 : 0.35;
  }

  Future<void> reset() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
    _applied = -1;
  }
}
