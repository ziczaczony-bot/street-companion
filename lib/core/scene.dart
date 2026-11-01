import 'dart:math' as math;

import 'lanes.dart';
import 'vehicles.dart';

const double laneWidthM = 3.6;

/// Where lanes and parking strips are, relative to the centre of the own
/// lane (metres, + = right).
class LaneLayout {
  const LaneLayout({required this.centers, required this.leftEdge, required this.rightEdge});

  final List<double> centers;
  final double leftEdge, rightEdge;

  double get rightParking => rightEdge + 1.4;
  double get leftParking => leftEdge - 1.4;

  factory LaneLayout.from(LaneInfo info) {
    const lw = laneWidthM;
    final c = info.count, i = info.index;
    if (c != null && c > 1 && i != null) {
      return LaneLayout(
        centers: [for (var k = 0; k < c; k++) (k - i) * lw],
        leftEdge: -(i + 0.5) * lw,
        rightEdge: (c - 1 - i + 0.5) * lw,
      );
    }
    // One lane per direction (or unknown): oncoming lane on the left.
    return LaneLayout(
      centers: [-lw, 0, if (c == null) lw],
      leftEdge: -1.5 * lw,
      rightEdge: c == null ? 1.5 * lw : 0.5 * lw,
    );
  }

  /// Lateral position a detected object belongs to: a lane centre, or a
  /// parking strip beyond the road edge.
  double slotFor(double lateral) {
    if (lateral > rightEdge - 0.3) return rightParking;
    if (lateral < leftEdge + 0.3) return leftParking;
    var best = centers.first;
    for (final c in centers) {
      if ((c - lateral).abs() < (best - lateral).abs()) best = c;
    }
    return best;
  }

  bool isParking(double slot) => slot == rightParking || slot == leftParking;
}

/// One vehicle as drawn in the traffic view.
class Track {
  Track(this.id, this.kind, this.d, this.slot) : x = slot;
  final int id;
  VehicleKind kind;

  /// Distance ahead (m), relative speed (m/s, negative = coming closer).
  double d, relV = 0;

  /// Lateral slot it belongs to and the animated lateral position.
  double slot, x;
  bool parked = false;
  bool isLead = false;
  double opacity = 0;
  DateTime? lastSeen;
  double? _lastMeasD;
  DateTime? _lastMeasT;
  double? _pendingSlot;
  int _pendingCount = 0;
}

/// Keeps vehicles calm on screen: each one stays in its lane or parking
/// strip, moves with a smoothed speed, and parked cars slide backwards at
/// exactly the own speed as you drive past.
class SceneTracker {
  final List<Track> tracks = [];
  int _nextId = 0;
  DateTime? _lastPredict;
  LaneLayout layout = LaneLayout.from(LaneInfo.unknown);

  void setLayout(LaneLayout l) {
    if (l.centers.length == layout.centers.length && l.leftEdge == layout.leftEdge) return;
    // Lanes changed (e.g. lane change): shift slots to the new layout.
    final old = layout;
    layout = l;
    for (final t in tracks) {
      t.slot = old.isParking(t.slot) ? (t.slot > 0 ? l.rightParking : l.leftParking) : l.slotFor(t.slot);
    }
  }

  /// Advances all tracks to [now] while no new camera frame arrives.
  void predict(DateTime now, double egoKmh) {
    final last = _lastPredict;
    _lastPredict = now;
    if (last == null) return;
    final dt = (now.difference(last).inMicroseconds / 1e6).clamp(0.0, 0.5);
    final ego = egoKmh / 3.6;
    final k = 1 - math.exp(-dt * 4);
    for (final t in tracks) {
      if (t.parked) t.relV = -ego; // parked cars do not move: they pass at our speed
      t.d += t.relV * dt;
      t.x += (t.slot - t.x) * k;
      final seen = t.lastSeen != null && now.difference(t.lastSeen!) < const Duration(milliseconds: 500);
      t.opacity = (t.opacity + (seen ? dt * 3 : -dt * 1.2)).clamp(0.0, 1.0);
      if (!seen && t.d < 15 && !t.parked && t.slot != 0) {
        // Out of the camera's view beside us: let it drift behind instead of freezing.
        t.relV = math.min(t.relV, -ego * 0.3);
      }
    }
    tracks.removeWhere((t) => (t.opacity <= 0 && t.lastSeen != null) || t.d < -12 || t.d > 95);
  }

  /// Feeds one camera frame of placed detections.
  void update(List<RoadObject> objs, DateTime now, double egoKmh) {
    predict(now, egoKmh);
    final ego = egoKmh / 3.6;
    final free = List<Track>.of(tracks);
    for (final t in tracks) {
      t.isLead = false;
    }
    // Lead first, then nearest objects first.
    final sorted = [...objs]..sort((a, b) => a.isLead ? -1 : (b.isLead ? 1 : a.distanceM.compareTo(b.distanceM)));
    for (final o in sorted) {
      final slot = o.isLead ? 0.0 : layout.slotFor(o.lateralM);
      Track? best;
      var bestCost = 1.6;
      for (final t in free) {
        if ((t.kind == VehicleKind.person) != (o.kind == VehicleKind.person)) continue;
        final cost = (t.d - o.distanceM).abs() / math.max(3.0, 0.3 * o.distanceM) + (t.slot - slot).abs() / laneWidthM;
        if (cost < bestCost) {
          bestCost = cost;
          best = t;
        }
      }
      if (best == null) {
        final t = Track(_nextId++, o.kind, o.distanceM, slot)
          ..parked = layout.isParking(slot)
          ..relV = layout.isParking(slot) ? -ego : 0;
        _measure(t, o, now, slot);
        tracks.add(t);
      } else {
        free.remove(best);
        best.kind = o.kind;
        best.d += 0.4 * (o.distanceM - best.d);
        _measure(best, o, now, slot);
      }
    }
  }

  void _measure(Track t, RoadObject o, DateTime now, double slot) {
    if (t._lastMeasD != null) {
      final dt = now.difference(t._lastMeasT!).inMicroseconds / 1e6;
      if (dt > 0.05) {
        final v = ((o.distanceM - t._lastMeasD!) / dt).clamp(-60.0, 40.0);
        t.relV = t.relV * 0.75 + v * 0.25;
      }
    }
    t._lastMeasD = o.distanceM;
    t._lastMeasT = now;
    t.lastSeen = now;
    t.isLead = o.isLead;
    // Change lane only when seen there several times in a row.
    if (o.isLead) {
      t.slot = 0;
      t._pendingSlot = null;
    } else if (slot != t.slot) {
      if (t._pendingSlot == slot) {
        t._pendingCount++;
      } else {
        t._pendingSlot = slot;
        t._pendingCount = 1;
      }
      if (t._pendingCount >= 4) {
        t.slot = slot;
        t._pendingSlot = null;
      }
    } else {
      t._pendingSlot = null;
    }
    t.parked = layout.isParking(t.slot);
  }
}
