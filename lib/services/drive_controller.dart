import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/speed_limit.dart';
import '../core/vehicles.dart';
import 'alerts.dart';
import 'brightness.dart';
import 'demo.dart';
import 'location_service.dart';
import 'settings.dart';
import 'speed_limit_service.dart';
import 'vehicle_detector.dart';

/// Holds everything the dashboard shows and wires the sensors together.
class DriveController extends ChangeNotifier {
  DriveController(this.settings);

  final Settings settings;
  final location = LocationService();
  final limits = SpeedLimitService();
  final detector = VehicleDetector();
  final alerts = Alerts();
  final brightness = AutoBrightness();
  final _overspeed = OverspeedTracker();
  final _departure = DepartureMonitor();

  // What the dashboard shows.
  double speedKmh = 0;
  bool hasGps = false;
  GpsStatus gpsStatus = GpsStatus.starting;
  SpeedLimit? limit;
  String? roadName;
  bool get overspeed => _overspeed.isOver;
  List<RoadObject> road = const [];
  RoadObject? get lead => road.where((r) => r.isLead).firstOrNull;
  DateTime? departureAlertAt;
  int inferenceMs = 0;
  bool get demo => settings.demoMode;

  bool get showDepartureBanner =>
      departureAlertAt != null && DateTime.now().difference(departureAlertAt!) < const Duration(seconds: 4);

  StreamSubscription<GpsFix>? _gpsSub;
  StreamSubscription<FrameResult>? _camSub;
  Timer? _demoTimer;
  Timer? _brightnessTimer;
  DemoDrive? _demo;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    await alerts.init();
    _brightnessTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      brightness.apply(enabled: settings.autoBrightness);
      notifyListeners();
    });
    if (settings.demoMode) {
      _startDemo();
    } else {
      await _startSensors();
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _demoTimer?.cancel();
    _brightnessTimer?.cancel();
    await _gpsSub?.cancel();
    await _camSub?.cancel();
    await location.stop();
    await detector.stop();
    await brightness.reset();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> restart() async {
    await stop();
    _reset();
    await start();
  }

  void _reset() {
    speedKmh = 0;
    hasGps = false;
    limit = null;
    roadName = null;
    road = const [];
    departureAlertAt = null;
    _departure.reset();
    _demo = null;
  }

  Future<void> _startSensors() async {
    gpsStatus = await location.start();
    _gpsSub = location.fixes.listen(_onFix);
    if (settings.cameraEnabled) {
      detector.rotationOverride = settings.cameraRotation;
      await detector.start();
      _camSub = detector.results.listen(_onFrame);
    }
  }

  void _startDemo() {
    _demo = DemoDrive();
    gpsStatus = GpsStatus.ok;
    hasGps = true;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final d = _demo!;
      _applySpeed(d.speedKmh, d.limit, d.roadName);
      _applyFrame(d.detections, portrait: false);
      brightness.addSample(d.luma);
      notifyListeners();
    });
  }

  void _onFix(GpsFix f) {
    hasGps = true;
    gpsStatus = GpsStatus.ok;
    final m = limits.update(LatLon(f.lat, f.lon), headingDeg: f.headingDeg);
    final newLimit = m == null ? null : limitFromTags(m.way.tags, forward: m.forward);
    _applySpeed(f.speedKmh, newLimit, m?.way.name);
    notifyListeners();
  }

  void _applySpeed(double kmh, SpeedLimit? newLimit, String? name) {
    speedKmh = kmh;
    roadName = name;
    if (newLimit != limit) {
      final before = limit;
      limit = newLimit;
      if (before != null && newLimit?.kmh != null && settings.announceLimit) {
        alerts.say('limit', 'Tempolimit ${newLimit!.kmh}', voice: settings.voice, cooldown: const Duration(seconds: 3));
      }
    }
    if (_overspeed.update(kmh, limit, settings.toleranceKmh)) {
      alerts.say('over', 'Zu schnell. Erlaubt sind ${limit!.kmh}.', voice: settings.voice, cooldown: const Duration(seconds: 20));
    }
  }

  void _onFrame(FrameResult r) {
    inferenceMs = r.inferenceMs;
    brightness.addSample(r.luma);
    _applyFrame(r.detections, portrait: r.portrait);
    notifyListeners();
  }

  void _applyFrame(List<Detection> dets, {required bool portrait}) {
    road = placeOnRoad(dets, portrait: portrait);
    if (!settings.departureAlert) return;
    final leadDet = lead?.detection;
    if (_departure.update(DateTime.now(), speedKmh, leadDet)) {
      departureAlertAt = DateTime.now();
      alerts.say('depart', 'Vorderfahrzeug fährt an', voice: settings.voice, cooldown: const Duration(seconds: 5));
    }
  }

  @override
  void dispose() {
    stop();
    detector.dispose();
    alerts.dispose();
    super.dispose();
  }
}
