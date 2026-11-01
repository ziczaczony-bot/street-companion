import 'dart:math' as math;

import '../core/lanes.dart';
import '../core/road_map.dart';
import '../core/speed_limit.dart';
import '../core/vehicles.dart';

/// A 70-second scripted drive so the app can be tried at home:
/// town at 50, a 30 zone where you are a bit too fast, a red light where
/// the car ahead drives off, then a country road.
class DemoDrive {
  DemoDrive() : _start = DateTime.now();
  final DateTime _start;
  static const loop = 70.0;

  /// For screenshots: pretend the drive started at this moment.
  static DateTime? debugEpoch;

  double get _t => (DateTime.now().difference(debugEpoch ?? _start).inMilliseconds / 1000.0) % loop;

  double get speedKmh {
    final t = _t;
    if (t < 8) return t / 8 * 48; // pull away
    if (t < 18) return 48 + math.sin(t) * 2; // town
    if (t < 30) return 48 - (t - 18) / 12 * 10 + (t > 22 ? 0 : 0); // into 30 zone, still ~40 = too fast
    if (t < 36) return math.max(0, 38 - (t - 30) / 6 * 38); // brake for red light
    if (t < 47) return 0; // wait at the light
    if (t < 55) return (t - 47) / 8 * 75; // go
    return 75 + math.sin(t / 2) * 4; // country road
  }

  SpeedLimit get limit {
    final t = _t;
    if (t < 18) return const SpeedLimit(kmh: 50);
    if (t < 40) return const SpeedLimit(kmh: 30);
    if (t < 50) return const SpeedLimit(kmh: 50);
    return const SpeedLimit(kmh: 120);
  }

  String get roadName {
    final t = _t;
    if (t < 18) return 'Hauptstraße';
    if (t < 50) return 'Schulweg';
    return 'A 8';
  }

  /// Metres driven; advanced by [tick].
  double travelled = 0;
  void tick(double dtSeconds) => travelled += speedKmh / 3.6 * dtSeconds;

  /// Fake camera detections, made by projecting a small simulated world
  /// (lead car, parked cars, oncoming and overtaken traffic) into the image.
  List<Detection> get detections {
    final t = _t;
    final out = <Detection>[];
    void add(VehicleKind k, double d, double x) {
      final det = projectToImage(k, d, x);
      if (det != null) out.add(det);
    }

    // Lead car in our lane: approaches while we brake, waits, drives off at 44 s.
    double leadD;
    if (t < 30) {
      leadD = 28 + 3 * math.sin(t / 3);
    } else if (t < 36) {
      leadD = 28 - (t - 30) / 6 * 22;
    } else if (t < 44) {
      leadD = 6;
    } else if (t < 52) {
      leadD = 6 + (t - 44) * (t - 44) * 0.6;
    } else {
      leadD = 40 + 4 * math.sin(t / 4);
    }
    add(VehicleKind.car, leadD, 0);

    if (t < 50) {
      // Town: cars parked on the right every 7 m (with gaps), fixed in the world.
      final s0 = travelled;
      for (var i = (s0 / 7).floor(); i < (s0 + 45) / 7; i++) {
        if (i % 5 == 3 || i % 7 == 1) continue; // gaps / driveways
        add(i % 6 == 0 ? VehicleKind.truck : VehicleKind.car, i * 7.0 - s0 + 4, 3.4);
      }
      // Oncoming traffic on the left lane at 40 km/h.
      final phase = (t * 0.25) % 1.0;
      add(VehicleKind.car, 50 - phase * 60, -3.6);
    } else {
      // Motorway: a truck in the right lane that we overtake, a fast car on the left.
      final idx = lanes.index ?? 2;
      final rightLaneX = (2 - idx) * 3.6;
      add(VehicleKind.truck, 45 - (t - 50) * 4.5, rightLaneX == 0 ? 3.6 : rightLaneX);
      final leftLaneX = (0 - idx) * 3.6;
      add(VehicleKind.car, 8 + ((t - 50) * 6) % 60, leftLaneX == 0 ? -3.6 : leftLaneX);
    }
    return out;
  }

  /// Side streets every 80 m in town, an exit ramp on the motorway.
  List<EgoRoad> get roads {
    final t = _t;
    final out = <EgoRoad>[
      const EgoRoad(points: [(0.0, -60.0), (0.0, 200.0)], widthM: 9, current: true),
    ];
    if (t < 50) {
      for (var k = (travelled / 80).floor(); k < (travelled + 160) / 80; k++) {
        final d = k * 80.0 - travelled + 30;
        out.add(EgoRoad(points: [(-90.0, d), (90.0, d)], widthM: 6, name: 'Gartenstraße'));
      }
    } else {
      final d = 160 - (t - 50) * 20;
      out.add(EgoRoad(points: [(8.0, d), (14.0, d + 40), (30.0, d + 90)], widthM: 5, name: 'Ausfahrt'));
    }
    return out;
  }

  /// Town: one lane each way. Motorway (from 50 s): three lanes, joining
  /// on the right and changing to the middle lane at 60 s.
  LaneInfo get lanes {
    final t = _t;
    if (t < 50) return const LaneInfo(count: 1, index: 0, left: LineType.dashed, right: LineType.solid);
    if (t < 60) return const LaneInfo(count: 3, index: 2, left: LineType.dashed, right: LineType.solid);
    return const LaneInfo(count: 3, index: 1, left: LineType.dashed, right: LineType.dashed);
  }

  double get luma => 120;
}
