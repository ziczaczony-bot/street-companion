import 'dart:math' as math;

import 'speed_limit.dart';

/// A road from OpenStreetMap in the car's own frame:
/// x = metres to the right, d = metres ahead.
class EgoRoad {
  const EgoRoad({required this.points, required this.widthM, this.current = false, this.name});
  final List<(double, double)> points;
  final double widthM;
  final bool current;
  final String? name;
}

double roadWidthM(String? highway) => switch (highway) {
      'motorway' || 'trunk' => 11,
      'primary' => 8,
      'secondary' => 7.5,
      'tertiary' => 7,
      'residential' || 'unclassified' || 'road' => 6,
      'living_street' => 5,
      'service' => 4,
      _ => highway != null && highway.endsWith('_link') ? 5 : 6,
    };

/// Converts roads around [pos] into the car's frame, facing [headingDeg].
List<EgoRoad> roadsAroundEgo(List<Way> ways, LatLon pos, double headingDeg,
    {int? currentWayId, double range = 160}) {
  final h = headingDeg * math.pi / 180;
  final sinH = math.sin(h), cosH = math.cos(h);
  final cosLat = math.cos(pos.lat * math.pi / 180);
  const r = 6371000.0;
  final out = <EgoRoad>[];
  for (final w in ways) {
    final pts = <(double, double)>[];
    void flush() {
      if (pts.length >= 2) {
        out.add(EgoRoad(points: List.of(pts), widthM: roadWidthM(w.tags['highway']), current: w.id == currentWayId, name: w.name));
      }
      pts.clear();
    }

    for (final p in w.geometry) {
      final east = (p.lon - pos.lon) * math.pi / 180 * r * cosLat;
      final north = (p.lat - pos.lat) * math.pi / 180 * r;
      final d = east * sinH + north * cosH;
      final x = east * cosH - north * sinH;
      if (x.abs() > range || d > range * 1.5 || d < -range * 0.5) {
        // Keep one point beyond the range so the road does not end early.
        if (pts.isNotEmpty) {
          pts.add((x, d));
          flush();
        }
        continue;
      }
      pts.add((x, d));
    }
    flush();
  }
  return out;
}
