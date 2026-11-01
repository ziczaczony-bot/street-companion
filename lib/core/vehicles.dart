import 'dart:math' as math;

enum VehicleKind { car, truck, bus, motorcycle, bicycle, person }

/// Real-world width used to estimate distance from box width.
double typicalWidthM(VehicleKind k) => switch (k) {
      VehicleKind.car => 1.8,
      VehicleKind.truck => 2.5,
      VehicleKind.bus => 2.55,
      VehicleKind.motorcycle => 0.8,
      VehicleKind.bicycle => 0.6,
      VehicleKind.person => 0.5,
    };

/// COCO label index (as in labelmap.txt, "???" = 0) -> kind.
VehicleKind? kindForCocoIndex(int i) => switch (i) {
      1 => VehicleKind.person,
      2 => VehicleKind.bicycle,
      3 => VehicleKind.car,
      4 => VehicleKind.motorcycle,
      6 => VehicleKind.bus,
      8 => VehicleKind.truck,
      _ => null,
    };

/// One detection, in upright image coordinates normalised to 0..1.
class Detection {
  const Detection({
    required this.kind,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final VehicleKind kind;
  final double score;
  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  bool get isVehicle => kind != VehicleKind.person;
}

/// A detection placed on the road in metres (for the traffic view).
class RoadObject {
  const RoadObject({required this.detection, required this.distanceM, required this.lateralM, this.isLead = false});
  final Detection detection;
  final double distanceM; // ahead of the camera
  final double lateralM; // + = right
  final bool isLead;
  VehicleKind get kind => detection.kind;
}

/// Converts detections to positions on the road.
/// [portrait] tells whether the upright camera image is taller than wide,
/// which changes the horizontal field of view.
List<RoadObject> placeOnRoad(List<Detection> dets, {required bool portrait}) {
  // focal length in units of image width: f = 0.5 / tan(hfov / 2)
  final f = portrait ? 1.07 : 0.78; // ~50° vs ~65° horizontal FOV
  final lead = selectLead(dets);
  final out = <RoadObject>[];
  for (final d in dets) {
    if (d.width <= 0.01) continue;
    final dist = (typicalWidthM(d.kind) * f / d.width).clamp(2.0, 120.0);
    final lateral = (d.centerX - 0.5) / f * dist;
    out.add(RoadObject(detection: d, distanceM: dist, lateralM: lateral, isLead: identical(d, lead)));
  }
  return out;
}

/// The vehicle directly ahead: a vehicle in the central corridor,
/// the one closest to the camera (lowest bottom edge).
Detection? selectLead(List<Detection> dets) {
  Detection? best;
  for (final d in dets) {
    if (!d.isVehicle || d.kind == VehicleKind.bicycle) continue;
    // Corridor: box must overlap the middle 30% and its centre must be central.
    if (d.right < 0.35 || d.left > 0.65) continue;
    if ((d.centerX - 0.5).abs() > 0.22) continue;
    if (best == null || d.bottom > best.bottom) best = d;
  }
  return best;
}

/// Detects "the car in front has driven off while I am still standing".
///
/// Feed it every camera frame. It arms after the own car stood still for
/// [armAfter] with a close lead vehicle, then fires once when that vehicle
/// clearly shrinks (moves away) or disappears.
class DepartureMonitor {
  DepartureMonitor({
    this.stoppedBelowKmh = 3,
    this.armAfter = const Duration(seconds: 2),
    this.minLeadWidth = 0.12,
    this.shrinkRatio = 0.80,
    this.confirmFor = const Duration(milliseconds: 600),
    this.lostFor = const Duration(milliseconds: 1200),
  });

  final double stoppedBelowKmh;
  final Duration armAfter;
  final double minLeadWidth; // box width fraction: ~ closer than 12 m
  final double shrinkRatio;
  final Duration confirmFor;
  final Duration lostFor;

  DateTime? _stoppedSince;
  double? _baseline;
  double? _smoothed;
  DateTime? _shrinkSince;
  DateTime? _lastSeen;
  bool _fired = false;

  bool get armed => _baseline != null && !_fired;

  void reset() {
    _stoppedSince = null;
    _baseline = null;
    _smoothed = null;
    _shrinkSince = null;
    _lastSeen = null;
    _fired = false;
  }

  /// Returns true when the alert should be raised now.
  bool update(DateTime now, double speedKmh, Detection? lead) {
    if (speedKmh >= stoppedBelowKmh) {
      reset();
      return false;
    }
    _stoppedSince ??= now;
    if (_fired) return false;

    if (lead != null) {
      _lastSeen = now;
      final w = lead.width;
      _smoothed = _smoothed == null ? w : _smoothed! * 0.6 + w * 0.4;
    }

    // Arm: stood still long enough with a close vehicle ahead.
    if (_baseline == null) {
      if (lead != null && now.difference(_stoppedSince!) >= armAfter && _smoothed! >= minLeadWidth) {
        _baseline = _smoothed;
      }
      return false;
    }

    // Lead vanished (drove off or turned away).
    if (lead == null) {
      if (_lastSeen != null && now.difference(_lastSeen!) >= lostFor) return _fire();
      return false;
    }

    final s = _smoothed!;
    // Creeping closer (e.g. it was still rolling when we armed): follow it.
    if (s > _baseline!) _baseline = s;

    if (s < _baseline! * shrinkRatio) {
      _shrinkSince ??= now;
      if (now.difference(_shrinkSince!) >= confirmFor) return _fire();
    } else {
      _shrinkSince = null;
    }
    return false;
  }

  bool _fire() {
    _fired = true;
    return true;
  }
}

/// Exponential smoothing for noisy positions in the animation.
double lerpDouble(double a, double b, double t) => a + (b - a) * math.min(1.0, math.max(0.0, t));
