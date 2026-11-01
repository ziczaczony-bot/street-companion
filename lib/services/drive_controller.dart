import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/lanes.dart';
import '../core/link.dart';
import '../core/road_map.dart';
import '../core/speed_limit.dart';
import '../core/vehicles.dart';
import 'alerts.dart';
import 'brightness.dart';
import 'camera_link.dart';
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
  final receiver = LinkReceiver();
  final alerts = Alerts();
  final brightness = AutoBrightness();
  final _overspeed = OverspeedTracker();
  final _departure = DepartureMonitor();
  final _lanes = LaneTracker();
  int? _osmLanes;

  // What the dashboard shows.
  double speedKmh = 0;
  bool hasGps = false;
  GpsStatus gpsStatus = GpsStatus.starting;
  SpeedLimit? limit;
  String? roadName;
  bool get overspeed => _overspeed.isOver;
  List<RoadObject> road = const [];
  LaneInfo lanes = LaneInfo.unknown;

  /// Roads around the car from OpenStreetMap, in the car's frame, and when
  /// they were computed (the view moves them along between GPS fixes).
  List<EgoRoad> roads = const [];
  DateTime roadsAt = DateTime.now();
  double? _heading;
  RoadObject? get lead => road.where((r) => r.isLead).firstOrNull;
  DateTime? departureAlertAt;
  int inferenceMs = 0;
  bool get demo => settings.demoMode;

  /// Display phone: vehicles and lanes come from the camera phone.
  bool get remoteCamera => settings.role == DeviceRole.display && !settings.demoMode;

  /// Camera state for the status icon, local or remote.
  CameraStatus get cameraStatus {
    if (!remoteCamera) return detector.status;
    if (receiver.error != null) return CameraStatus.error;
    return receiver.connected ? CameraStatus.running : CameraStatus.starting;
  }

  bool get showDepartureBanner =>
      departureAlertAt != null && DateTime.now().difference(departureAlertAt!) < const Duration(seconds: 4);

  StreamSubscription<GpsFix>? _gpsSub;
  StreamSubscription<FrameResult>? _camSub;
  StreamSubscription<LinkFrame>? _linkSub;
  Timer? _linkTimer;
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
    await _linkSub?.cancel();
    _linkTimer?.cancel();
    await receiver.stop();
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
    _lanes.reset();
    roads = const [];
    _heading = null;
    lanes = LaneInfo.unknown;
    _osmLanes = null;
    _demo = null;
  }

  Future<void> _startSensors() async {
    gpsStatus = await location.start();
    _gpsSub = location.fixes.listen(_onFix);
    if (remoteCamera) {
      await receiver.start();
      _linkSub = receiver.frames.listen(_onLinkFrame);
      // Camera phone gone (out of battery, hotspot off): clear old cars.
      _linkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!receiver.connected && road.isNotEmpty) {
          road = const [];
          lanes = _lanes.update(LaneObservation.empty, osmCount: _osmLanes);
          notifyListeners();
        }
      });
    } else if (settings.cameraEnabled) {
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
      d.tick(0.2);
      _applySpeed(d.speedKmh, d.limit, d.roadName);
      _applyFrame(d.detections, CameraModel.landscape);
      roads = d.roads;
      roadsAt = DateTime.now();
      lanes = d.lanes;
      brightness.addSample(d.luma);
      notifyListeners();
    });
  }

  void _onFix(GpsFix f) {
    hasGps = true;
    gpsStatus = GpsStatus.ok;
    final m = limits.update(LatLon(f.lat, f.lon), headingDeg: f.headingDeg);
    final newLimit = m == null ? null : limitFromTags(m.way.tags, forward: m.forward);
    _osmLanes = m == null ? null : lanesForDirection(m.way.tags, forward: m.forward, oneway: m.way.oneway);
    _applySpeed(f.speedKmh, newLimit, m?.way.name);
    _updateRoads(f, m);
    notifyListeners();
  }

  void _updateRoads(GpsFix f, WayMatch? m) {
    var h = f.headingDeg ?? _heading;
    // Use the road's own direction when we are on it: steadier than GPS.
    final seg = m?.segmentBearingDeg;
    if (seg != null && h != null) {
      final back = (seg + 180) % 360;
      double diff(double a, double b) {
        final x = ((a - b) % 360 + 360) % 360;
        return x > 180 ? 360 - x : x;
      }

      h = diff(seg, h) <= diff(back, h) ? seg : back;
    }
    if (h == null) return; // direction unknown until we drive a bit
    _heading = h;
    final pos = m?.closest ?? LatLon(f.lat, f.lon);
    roads = roadsAroundEgo(limits.ways, pos, h, currentWayId: m?.way.id);
    roadsAt = DateTime.now();
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
    _applyFrame(r.detections, r.camera);
    lanes = _lanes.update(r.lanes, osmCount: _osmLanes);
    notifyListeners();
  }

  void _onLinkFrame(LinkFrame f) => _onFrame(FrameResult(
        detections: f.detections,
        lanes: f.lanes,
        luma: f.luma,
        camera: CameraModel(f.aspect),
        inferenceMs: f.inferenceMs,
      ));

  void _applyFrame(List<Detection> dets, CameraModel camera) {
    road = placeOnRoad(dets, camera: camera);
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
