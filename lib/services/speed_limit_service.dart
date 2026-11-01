import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/speed_limit.dart';

/// Loads roads around the car from OpenStreetMap (Overpass API) and keeps
/// them in memory, so only one request is needed every few hundred metres.
class SpeedLimitService {
  SpeedLimitService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];
  static const double radiusM = 700;
  static const double refetchAfterM = 450;

  List<Way> _ways = const [];
  LatLon? _center;
  DateTime? _fetchedAt;
  bool _loading = false;
  DateTime? _lastFailure;
  int _endpointIndex = 0;

  bool get hasData => _ways.isNotEmpty;
  List<Way> get ways => _ways;
  bool get loading => _loading;

  WayMatch? _lastMatch;
  DateTime? _lastMatchAt;

  /// Call on every GPS fix. Returns the current road match (may reuse the
  /// last one briefly when GPS jumps between roads).
  WayMatch? update(LatLon pos, {double? headingDeg}) {
    _maybeFetch(pos);
    final m = matchWay(_ways, pos, headingDeg: headingDeg);
    final now = DateTime.now();
    if (m != null) {
      _lastMatch = m;
      _lastMatchAt = now;
      return m;
    }
    if (_lastMatchAt != null && now.difference(_lastMatchAt!) < const Duration(seconds: 8)) return _lastMatch;
    return null;
  }

  void _maybeFetch(LatLon pos) {
    if (_loading) return;
    final now = DateTime.now();
    if (_lastFailure != null && now.difference(_lastFailure!) < const Duration(seconds: 20)) return;
    final stale = _fetchedAt == null || now.difference(_fetchedAt!) > const Duration(minutes: 15);
    final far = _center == null || distanceM(_center!, pos) > refetchAfterM;
    if (stale || far) _fetch(pos);
  }

  Future<void> _fetch(LatLon pos) async {
    _loading = true;
    final query = '[out:json][timeout:20];'
        'way(around:${radiusM.toInt()},${pos.lat},${pos.lon})'
        '[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|road|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)\$"];'
        'out tags geom;';
    try {
      final res = await _client
          .post(Uri.parse(_endpoints[_endpointIndex]),
              headers: {'User-Agent': 'StreetCompanion/0.1 (driving assistant app)'}, body: {'data': query})
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      _ways = parseOverpass(res.body);
      _center = pos;
      _fetchedAt = DateTime.now();
      _lastFailure = null;
    } catch (_) {
      _lastFailure = DateTime.now();
      _endpointIndex = (_endpointIndex + 1) % _endpoints.length;
    } finally {
      _loading = false;
    }
  }
}

List<Way> parseOverpass(String body) {
  final json = jsonDecode(body) as Map<String, dynamic>;
  final out = <Way>[];
  for (final e in (json['elements'] as List? ?? const [])) {
    if (e is! Map || e['type'] != 'way') continue;
    final geom = (e['geometry'] as List? ?? const [])
        .map((p) => LatLon((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))
        .toList();
    if (geom.length < 2) continue;
    final tags = <String, String>{};
    (e['tags'] as Map? ?? const {}).forEach((k, v) => tags['$k'] = '$v');
    out.add(Way(id: (e['id'] as num).toInt(), tags: tags, geometry: geom));
  }
  return out;
}
