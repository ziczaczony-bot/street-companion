import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:street_companion/core/lanes.dart';

/// Draws a synthetic road (160 x 120) with lane lines in perspective.
/// [dashOffset] moves the dashes as if driving.
Uint8List road({required bool leftSolid, required bool rightSolid, double shift = 0, double dashOffset = 0}) {
  const w = 160, h = 120;
  final img = Uint8List(w * h);
  const horizon = 48.0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      img[y * w + x] = y < horizon ? 150 : 70; // sky / asphalt
    }
  }
  // Lines at lateral -1.75 m and +1.75 m, vanishing point at (80+shift, horizon).
  for (var y = horizon.toInt() + 1; y < h; y++) {
    final depth = (y - horizon) / (h - horizon); // 0 at horizon .. 1 at bottom
    final dist = 6 / depth; // pseudo distance in metres
    final halfLane = 75 * depth; // pixels for 1.75 m
    final lineW = (1 + 3 * depth).round();
    for (final side in [-1, 1]) {
      final solid = side < 0 ? leftSolid : rightSolid;
      if (!solid && ((dist + dashOffset) % 9) > 3) continue; // 3 m dash, 6 m gap
      final xc = (80 + shift * depth + side * halfLane).round();
      for (var dx = 0; dx < lineW; dx++) {
        final x = xc + dx - lineW ~/ 2;
        if (x >= 0 && x < w) img[y * w + x] = 220;
      }
    }
  }
  return img;
}

void main() {
  test('solid left, dashed right', () {
    final o = detectLanes(road(leftSolid: true, rightSolid: false), 160, 120);
    expect(o.left, LineType.solid);
    expect(o.right, LineType.dashed);
    expect(o.offset, isNotNull);
    expect(o.offset!.abs(), lessThan(0.1));
  });

  test('dashed left, solid right', () {
    final o = detectLanes(road(leftSolid: false, rightSolid: true, dashOffset: 1.5), 160, 120);
    expect(o.left, LineType.dashed);
    expect(o.right, LineType.solid);
  });

  test('offset when driving off-centre', () {
    final o = detectLanes(road(leftSolid: true, rightSolid: true, shift: -40), 160, 120);
    expect(o.offset, isNotNull);
    expect(o.offset!, greaterThan(0.15)); // car is right of the lane centre
  });

  test('empty road', () {
    final img = Uint8List(160 * 120)..fillRange(0, 160 * 120, 80);
    final o = detectLanes(img, 160, 120);
    expect(o.left, LineType.none);
    expect(o.right, LineType.none);
  });

  test('lane index from lines and OSM count', () {
    expect(laneIndexFromLines(3, LineType.solid, LineType.dashed), 0);
    expect(laneIndexFromLines(3, LineType.dashed, LineType.dashed), 1);
    expect(laneIndexFromLines(3, LineType.dashed, LineType.solid), 2);
    expect(laneIndexFromLines(2, LineType.dashed, LineType.solid), 1);
    expect(laneIndexFromLines(2, LineType.dashed, LineType.dashed), isNull);
    expect(laneIndexFromLines(null, LineType.solid, LineType.dashed), 0);
    expect(laneIndexFromLines(1, LineType.dashed, LineType.solid), 0);
  });

  test('labels', () {
    expect(const LaneInfo(count: 3, index: 1).label, 'Mittlere Spur · 3 Spuren');
    expect(const LaneInfo(count: 2, index: 1).label, 'Rechte Spur · 2 Spuren');
    expect(const LaneInfo(count: 3, index: 0).label, 'Linke Spur · 3 Spuren');
    expect(const LaneInfo(count: 1, index: 0).label, 'Einspurig');
    expect(const LaneInfo(count: 4, index: 1).label, '2. Spur von links · 4 Spuren');
    expect(const LaneInfo().label, isNull);
  });

  test('OSM lanes per direction', () {
    expect(lanesForDirection({'highway': 'motorway', 'lanes': '3'}, forward: true, oneway: true), 3);
    expect(lanesForDirection({'highway': 'primary', 'lanes': '4'}, forward: true, oneway: false), 2);
    expect(lanesForDirection({'highway': 'primary', 'lanes': '3', 'lanes:forward': '2', 'lanes:backward': '1'}, forward: false, oneway: false), 1);
    expect(lanesForDirection({'highway': 'residential'}, forward: true, oneway: false), 1);
    expect(lanesForDirection({'highway': 'motorway'}, forward: true, oneway: true), isNull);
  });

  test('tracker follows a lane change to the right on a 3-lane road', () {
    final tr = LaneTracker();
    var t = DateTime(2026);
    LaneInfo step(LaneObservation o) {
      t = t.add(const Duration(milliseconds: 200));
      return tr.update(o, osmCount: 3, now: t);
    }

    // Left lane: solid on the left.
    for (var i = 0; i < 30; i++) {
      step(const LaneObservation(left: LineType.solid, right: LineType.dashed, leftCoverage: 0.95, rightCoverage: 0.35, offset: 0));
    }
    expect(tr.info.index, 0);
    // Drift right and cross the dashed line.
    step(const LaneObservation(leftCoverage: 0.95, rightCoverage: 0.35, offset: 0.4));
    for (var i = 0; i < 30; i++) {
      step(const LaneObservation(leftCoverage: 0.35, rightCoverage: 0.35, offset: -0.4));
    }
    expect(tr.info.index, 1);
    expect(tr.info.label, 'Mittlere Spur · 3 Spuren');
  });
}
