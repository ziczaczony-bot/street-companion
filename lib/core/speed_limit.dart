import 'dart:math' as math;

/// A speed limit as shown on the dashboard.
class SpeedLimit {
  const SpeedLimit({this.kmh, this.unlimited = false, this.label, this.advisoryKmh});

  /// Limit in km/h. Null when [unlimited] or unknown.
  final int? kmh;

  /// True on German motorways without a limit ("freie Fahrt").
  final bool unlimited;

  /// Optional short text, e.g. "Schritt" for living streets.
  final String? label;

  /// Recommended speed (Richtgeschwindigkeit), e.g. 130 on Autobahn.
  final int? advisoryKmh;

  @override
  bool operator ==(Object other) =>
      other is SpeedLimit &&
      other.kmh == kmh &&
      other.unlimited == unlimited &&
      other.label == label &&
      other.advisoryKmh == advisoryKmh;

  @override
  int get hashCode => Object.hash(kmh, unlimited, label, advisoryKmh);

  @override
  String toString() => unlimited ? 'SpeedLimit(none)' : 'SpeedLimit($kmh)';
}

const _walk = SpeedLimit(kmh: 7, label: 'Schritt');
const _none = SpeedLimit(unlimited: true, advisoryKmh: 130);

/// Implicit limits for Germany and its neighbours (OSM "XX:zone" values).
const Map<String, SpeedLimit> _implicit = {
  'DE:urban': SpeedLimit(kmh: 50),
  'DE:rural': SpeedLimit(kmh: 100),
  'DE:motorway': _none,
  'DE:living_street': _walk,
  'DE:bicycle_road': SpeedLimit(kmh: 30),
  'DE:zone:30': SpeedLimit(kmh: 30),
  'DE:zone30': SpeedLimit(kmh: 30),
  'DE:zone:20': SpeedLimit(kmh: 20),
  'DE:zone20': SpeedLimit(kmh: 20),
  'DE:zone:10': SpeedLimit(kmh: 10),
  'AT:urban': SpeedLimit(kmh: 50),
  'AT:rural': SpeedLimit(kmh: 100),
  'AT:motorway': SpeedLimit(kmh: 130),
  'CH:urban': SpeedLimit(kmh: 50),
  'CH:rural': SpeedLimit(kmh: 80),
  'CH:motorway': SpeedLimit(kmh: 120),
  'NL:urban': SpeedLimit(kmh: 50),
  'NL:rural': SpeedLimit(kmh: 80),
  'FR:urban': SpeedLimit(kmh: 50),
  'FR:rural': SpeedLimit(kmh: 80),
  'FR:motorway': SpeedLimit(kmh: 130),
};

/// Parses an OSM `maxspeed` value. Returns null when unknown
/// (e.g. "signals" for electronic signs, or garbage).
SpeedLimit? parseMaxspeed(String? raw) {
  if (raw == null) return null;
  var v = raw.trim();
  if (v.isEmpty) return null;
  // "50;30" happens on some ways; the first value is the main one.
  if (v.contains(';')) v = v.split(';').first.trim();
  if (v == 'none') return _none;
  if (v == 'walk') return _walk;
  if (v == 'signals' || v == 'variable') return null;
  final implicit = _implicit[v];
  if (implicit != null) return implicit;
  // Unknown zone value like "DE:zone:40" -> take the number.
  final zone = RegExp(r'^[A-Z]{2}:zone:?(\d+)$').firstMatch(v);
  if (zone != null) return SpeedLimit(kmh: int.parse(zone.group(1)!));
  final mph = RegExp(r'^(\d+)\s*mph$').firstMatch(v);
  if (mph != null) return SpeedLimit(kmh: (int.parse(mph.group(1)!) * 1.609344).round());
  final kmh = RegExp(r'^(\d+)(\s*km/h)?$').firstMatch(v);
  if (kmh != null) {
    final n = int.parse(kmh.group(1)!);
    if (n <= 0 || n > 200) return null;
    return SpeedLimit(kmh: n);
  }
  return null;
}

/// Limit for a way's tags, travelling forward (along the way's node order)
/// or backward.
SpeedLimit? limitFromTags(Map<String, String> tags, {bool forward = true}) {
  final dir = forward ? tags['maxspeed:forward'] : tags['maxspeed:backward'];
  return parseMaxspeed(dir) ??
      parseMaxspeed(tags['maxspeed']) ??
      parseMaxspeed(tags['maxspeed:type']) ??
      parseMaxspeed(tags['source:maxspeed']) ??
      _fallbackForHighway(tags['highway']);
}

SpeedLimit? _fallbackForHighway(String? highway) {
  switch (highway) {
    case 'motorway':
      return _none;
    case 'living_street':
      return _walk;
    default:
      return null;
  }
}

class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;
}

class Way {
  const Way({required this.id, required this.tags, required this.geometry});
  final int id;
  final Map<String, String> tags;
  final List<LatLon> geometry;

  String? get name => tags['name'] ?? tags['ref'];
  bool get oneway => tags['oneway'] == 'yes' || tags['highway'] == 'motorway' || tags['junction'] == 'roundabout';
}

class WayMatch {
  const WayMatch(this.way, this.distanceM, this.forward, {this.closest, this.segmentBearingDeg});
  final Way way;
  final double distanceM;
  final bool forward;

  /// Nearest point on the road (the car snapped onto it).
  final LatLon? closest;

  /// Bearing of the road segment in the way's node order (0 = north).
  final double? segmentBearingDeg;
}

const double _earthR = 6371000.0;

/// Finds the road the car is most likely on.
/// [headingDeg] is the GPS course (0 = north), or null when unknown/slow.
WayMatch? matchWay(List<Way> ways, LatLon pos, {double? headingDeg, double maxDistanceM = 35}) {
  WayMatch? best;
  double bestScore = double.infinity;
  final cosLat = math.cos(pos.lat * math.pi / 180);
  // Local flat projection around the car, metres.
  double px(LatLon p) => (p.lon - pos.lon) * math.pi / 180 * _earthR * cosLat;
  double py(LatLon p) => (p.lat - pos.lat) * math.pi / 180 * _earthR;

  for (final way in ways) {
    final g = way.geometry;
    for (var i = 0; i + 1 < g.length; i++) {
      final ax = px(g[i]), ay = py(g[i]), bx = px(g[i + 1]), by = py(g[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      if (len2 == 0) continue;
      final t = (((-ax) * dx + (-ay) * dy) / len2).clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final dist = math.sqrt(cx * cx + cy * cy);
      if (dist > maxDistanceM) continue;
      final segBearing = (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
      var forward = true;
      var penalty = 0.0;
      if (headingDeg != null) {
        final diff = _angleDiff(headingDeg, segBearing); // 0..180
        forward = diff <= 90;
        final axisDiff = forward ? diff : 180 - diff; // 0..90
        penalty = axisDiff * 0.4;
        if (!forward && way.oneway) penalty += 40; // driving against a one-way is unlikely
      }
      final score = dist + penalty;
      if (score < bestScore) {
        bestScore = score;
        best = WayMatch(
          way,
          dist,
          forward,
          closest: LatLon(pos.lat + cy / _earthR * 180 / math.pi, pos.lon + cx / (_earthR * cosLat) * 180 / math.pi),
          segmentBearingDeg: segBearing,
        );
      }
    }
  }
  return best;
}

double _angleDiff(double a, double b) {
  final d = ((a - b) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}

/// Distance in metres between two points (haversine).
double distanceM(LatLon a, LatLon b) {
  final dLat = (b.lat - a.lat) * math.pi / 180;
  final dLon = (b.lon - a.lon) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthR * math.asin(math.sqrt(h.toDouble()));
}

/// Overspeed detection with hysteresis so the warning does not flicker.
class OverspeedTracker {
  bool _over = false;
  bool get isOver => _over;

  /// Returns true exactly when the driver *becomes* too fast.
  bool update(double speedKmh, SpeedLimit? limit, int toleranceKmh) {
    final kmh = limit?.kmh;
    if (kmh == null || limit!.unlimited) {
      _over = false;
      return false;
    }
    final threshold = kmh + toleranceKmh;
    if (!_over && speedKmh > threshold) {
      _over = true;
      return true;
    }
    if (_over && speedKmh <= threshold - 2) _over = false;
    return false;
  }
}
