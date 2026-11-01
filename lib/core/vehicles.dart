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

/// Simple pinhole model of the phone camera.
class CameraModel {
  const CameraModel(this.aspect);

  /// Upright image width / height.
  final double aspect;
  static const landscape = CameraModel(4 / 3);

  bool get portrait => aspect < 1;

  /// Focal length in units of image width: f = 0.5 / tan(hfov / 2)
  /// (~65° horizontal field of view in landscape, ~50° in portrait).
  double get fx => portrait ? 1.07 : 0.78;

  /// Focal length in units of image height.
  double get fy => fx * aspect;

  /// Height of the camera above the road (m).
  static const mountHeight = 1.25;
}

/// Real-world height used to estimate distance from box height. Height
/// stays right when a car is seen from the side, unlike width.
double typicalHeightM(VehicleKind k) => switch (k) {
      VehicleKind.car => 1.5,
      VehicleKind.truck => 3.4,
      VehicleKind.bus => 3.1,
      VehicleKind.motorcycle => 1.4,
      VehicleKind.bicycle => 1.7,
      VehicleKind.person => 1.7,
    };

/// Converts detections to positions on the road (metres from the camera).
List<RoadObject> placeOnRoad(List<Detection> dets, {CameraModel camera = CameraModel.landscape}) {
  final lead = selectLead(dets, camera: camera);
  final out = <RoadObject>[];
  final fx = camera.fx, fy = camera.fy;
  for (final d in dets) {
    if (d.width <= 0.01 || d.height <= 0.01) continue;
    final dW = typicalWidthM(d.kind) * fx / d.width;
    final dH = typicalHeightM(d.kind) * fy / d.height;
    final cutTop = d.top < 0.01;
    final cutSide = d.left < 0.01 || d.right > 0.99;
    final sideView = (d.centerX - 0.5).abs() > 0.18;
    double dist;
    if (cutTop && !cutSide) {
      dist = dW;
    } else if (cutSide || sideView) {
      dist = dH; // box also contains the car's flank: width would lie
    } else {
      dist = (dW + dH) / 2;
    }
    dist = dist.clamp(2.0, 120.0);
    // Lateral position from the box edge nearest to the image centre:
    // that edge is the car's near corner, the rest of the box is its flank.
    final halfW = typicalWidthM(d.kind) / 2;
    double lateral;
    if (identical(d, lead) || !sideView) {
      lateral = (d.centerX - 0.5) / fx * dist;
    } else if (d.centerX > 0.5) {
      lateral = (d.left - 0.5) / fx * dist + halfW;
    } else {
      lateral = (d.right - 0.5) / fx * dist - halfW;
    }
    out.add(RoadObject(detection: d, distanceM: dist, lateralM: lateral, isLead: identical(d, lead)));
  }
  return out;
}

/// Where a vehicle at [distanceM] ahead and [lateralM] to the right would
/// appear in the image (used by the demo and tests). Null when not visible.
Detection? projectToImage(VehicleKind kind, double distanceM, double lateralM,
    {CameraModel camera = CameraModel.landscape, double score = 0.9}) {
  if (distanceM < 2) return null;
  final fx = camera.fx, fy = camera.fy;
  final cx = 0.5 + lateralM * fx / distanceM;
  final w = typicalWidthM(kind) * fx / distanceM;
  final h = typicalHeightM(kind) * fy / distanceM;
  final bottom = 0.5 + CameraModel.mountHeight * fy / distanceM;
  final left = cx - w / 2, right = cx + w / 2, top = bottom - h;
  if (right < 0.02 || left > 0.98) return null;
  return Detection(
    kind: kind,
    score: score,
    left: left.clamp(0.0, 1.0),
    right: right.clamp(0.0, 1.0),
    top: top.clamp(0.0, 1.0),
    bottom: bottom.clamp(0.0, 1.0),
  );
}

/// The vehicle directly ahead: a vehicle whose estimated lateral position
/// is inside the own lane, the nearest one. Parked cars at the roadside
/// can look central in the image when far away, so the decision uses the
/// position on the road, not just the image position.
Detection? selectLead(List<Detection> dets, {CameraModel camera = CameraModel.landscape}) {
  Detection? best;
  double bestD = double.infinity;
  for (final d in dets) {
    if (!d.isVehicle || d.kind == VehicleKind.bicycle) continue;
    if (d.height <= 0.01 || d.left < 0.01 || d.right > 0.99) continue;
    final dist = typicalHeightM(d.kind) * camera.fy / d.height;
    final lateral = (d.centerX - 0.5) / camera.fx * dist;
    if (lateral.abs() > 1.3) continue;
    if (dist < bestD) {
      bestD = dist;
      best = d;
    }
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
