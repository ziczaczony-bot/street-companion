import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User settings, saved on the phone.
class Settings extends ChangeNotifier {
  Settings._(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  bool get acceptedDisclaimer => _p.getBool('disclaimer') ?? false;
  set acceptedDisclaimer(bool v) => _set('disclaimer', v);

  /// km/h above the limit before the warning starts.
  int get toleranceKmh => _p.getInt('tolerance') ?? 3;
  set toleranceKmh(int v) => _set('tolerance', v);

  bool get voice => _p.getBool('voice') ?? true;
  set voice(bool v) => _set('voice', v);

  bool get announceLimit => _p.getBool('announceLimit') ?? false;
  set announceLimit(bool v) => _set('announceLimit', v);

  bool get departureAlert => _p.getBool('departure') ?? true;
  set departureAlert(bool v) => _set('departure', v);

  bool get cameraEnabled => _p.getBool('camera') ?? true;
  set cameraEnabled(bool v) => _set('camera', v);

  bool get showPreview => _p.getBool('preview') ?? false;
  set showPreview(bool v) => _set('preview', v);

  bool get autoBrightness => _p.getBool('autoBrightness') ?? true;
  set autoBrightness(bool v) => _set('autoBrightness', v);

  /// -1 = automatic, else 0/90/180/270 degrees.
  int get cameraRotation => _p.getInt('rotation') ?? -1;
  set cameraRotation(int v) => _set('rotation', v);

  bool get demoMode => _p.getBool('demo') ?? false;
  set demoMode(bool v) => _set('demo', v);

  void _set(String k, Object v) {
    if (v is bool) _p.setBool(k, v);
    if (v is int) _p.setInt(k, v);
    notifyListeners();
  }
}
