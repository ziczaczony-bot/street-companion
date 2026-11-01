import 'dart:math' as math;

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
    return const SpeedLimit(kmh: 100);
  }

  String get roadName {
    final t = _t;
    if (t < 18) return 'Hauptstraße';
    if (t < 50) return 'Schulweg';
    return 'L 1140';
  }

  /// Fake detections in upright image coordinates.
  List<Detection> get detections {
    final t = _t;
    final out = <Detection>[];
    Detection car(double cx, double w, {VehicleKind k = VehicleKind.car}) {
      final h = w * (k == VehicleKind.truck ? 1.0 : 0.75);
      final bottom = 0.5 + w * 0.9;
      return Detection(kind: k, score: 0.9, left: cx - w / 2, right: cx + w / 2, top: bottom - h, bottom: bottom);
    }

    // Lead car: approaches while we brake, waits, drives off at t = 44.
    double leadW;
    if (t < 30) {
      leadW = 0.05 + 0.01 * math.sin(t / 3);
    } else if (t < 36) {
      leadW = 0.05 + (t - 30) / 6 * 0.27;
    } else if (t < 44) {
      leadW = 0.32;
    } else if (t < 52) {
      leadW = math.max(0.06, 0.32 - (t - 44) * 0.05);
    } else {
      leadW = 0.09;
    }
    out.add(car(0.5, leadW));
    // Oncoming / neighbour traffic.
    final phase = (t * 0.35) % 1.0;
    out.add(car(0.18 - phase * 0.15, 0.05 + phase * 0.18));
    if (t > 50) {
      final p2 = ((t - 50) * 0.2) % 1.0;
      out.add(car(0.85, 0.04 + p2 * 0.06, k: VehicleKind.truck));
    }
    return out;
  }

  double get luma => 120;
}
