import 'dart:math' as math;
import 'dart:typed_data';

/// Type of a lane marking next to the car.
enum LineType { none, dashed, solid }

/// Lanes in the driving direction, from OSM tags. Null when unknown.
int? lanesForDirection(Map<String, String> tags, {required bool forward, required bool oneway}) {
  int? n(String? v) {
    final x = int.tryParse((v ?? '').split(';').first.trim());
    return (x == null || x < 1 || x > 8) ? null : x;
  }

  final dir = n(forward ? tags['lanes:forward'] : tags['lanes:backward']);
  if (dir != null) return dir;
  final total = n(tags['lanes']);
  if (total != null) return oneway ? total : math.max(1, total ~/ 2);
  // Ordinary two-way streets without a lanes tag have one lane per direction.
  const single = {'residential', 'living_street', 'unclassified', 'service', 'tertiary', 'road'};
  if (!oneway && single.contains(tags['highway'])) return 1;
  return null;
}

/// What the camera sees of the lane markings in one frame.
class LaneObservation {
  const LaneObservation({
    this.left = LineType.none,
    this.right = LineType.none,
    this.leftCoverage = 0,
    this.rightCoverage = 0,
    this.offset,
  });

  final LineType left, right;

  /// Share of the visible road length that is painted (1 = solid line).
  final double leftCoverage, rightCoverage;

  /// Position inside the lane: 0 = centre, -0.5 = on the left line,
  /// +0.5 = on the right line. Null when not both lines are seen.
  final double? offset;

  static const empty = LaneObservation();
}

/// A straight line in the road area, given by its x at the bottom and
/// top of the region of interest (in pixels of the small gray image).
class _Line {
  _Line(this.xb, this.xt, this.votes);
  final double xb, xt;
  final int votes;
}

/// Finds the lane markings left and right of the car in a small upright
/// grayscale frame (e.g. 160 x 120) and tells solid from dashed.
///
/// Classic computer vision, no model: bright thin stripes on the road
/// (top-hat filter), then a Hough vote for straight lines converging
/// towards the horizon.
LaneObservation detectLanes(Uint8List gray, int w, int h) {
  final y0 = (h * 0.60).round();
  final y1 = (h * 0.94).round();
  final rows = y1 - y0;
  if (rows < 8) return LaneObservation.empty;

  // 1. Marking pixels per row: brighter than the road on both sides.
  final mark = List.generate(rows, (_) => Uint8List(w));
  final pts = <int>[]; // packed (row << 16) | x
  for (var r = 0; r < rows; r++) {
    final y = y0 + r;
    final k = (2 + 4 * r / rows).round(); // stripes look wider near the car
    final base = y * w;
    var sum = 0;
    for (var x = 0; x < w; x++) {
      sum += gray[base + x];
    }
    final mean = sum / w;
    for (var x = k; x < w - k; x++) {
      final v = gray[base + x];
      final side = math.max(gray[base + x - k], gray[base + x + k]);
      if (v - side > 22 && v > mean + 15) {
        mark[r][x] = 1;
        pts.add((r << 16) | x);
      }
    }
  }
  if (pts.length < 10) return LaneObservation.empty;

  // 2. Hough vote over (x at bottom, x at top).
  const step = 2;
  final xbMin = -w ~/ 2, xbMax = w + w ~/ 2;
  final xtMin = -w ~/ 4, xtMax = w + w ~/ 4;
  final nb = (xbMax - xbMin) ~/ step + 1, nt = (xtMax - xtMin) ~/ step + 1;
  final acc = Int32List(nb * nt);
  for (final p in pts) {
    final r = p >> 16, x = p & 0xffff;
    final t = (rows - 1 - r) / (rows - 1); // 0 at bottom row, 1 at top row
    if (t < 0.05) continue;
    for (var bi = 0; bi < nb; bi++) {
      final xb = xbMin + bi * step;
      final xt = xb + (x - xb) / t;
      final ti = ((xt - xtMin) / step).round();
      if (ti < 0 || ti >= nt) continue;
      acc[bi * nt + ti]++;
    }
  }

  // 3. Peaks (local maxima) that look like lane lines.
  final minVotes = math.max(8, rows ~/ 3);
  final cands = <_Line>[];
  for (var bi = 1; bi < nb - 1; bi++) {
    for (var ti = 1; ti < nt - 1; ti++) {
      final v = acc[bi * nt + ti];
      if (v < minVotes) continue;
      var isMax = true;
      for (var db = -2; db <= 2 && isMax; db++) {
        for (var dt = -2; dt <= 2; dt++) {
          final b2 = bi + db, t2 = ti + dt;
          if ((db == 0 && dt == 0) || b2 < 0 || b2 >= nb || t2 < 0 || t2 >= nt) continue;
          final o = acc[b2 * nt + t2];
          if (o > v || (o == v && (db < 0 || (db == 0 && dt < 0)))) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) cands.add(_Line((xbMin + bi * step).toDouble(), (xtMin + ti * step).toDouble(), v));
    }
  }
  final cx = w / 2;
  // Left boundary leans right towards the top, right boundary leans left.
  final lefts = cands.where((l) => l.xb < cx && l.xt > l.xb + w * 0.05 && l.xt < cx + w * 0.15).toList();
  final rights = cands.where((l) => l.xb > cx && l.xt < l.xb - w * 0.05 && l.xt > cx - w * 0.15).toList();

  _Line? pick(List<_Line> ls, bool left) {
    if (ls.isEmpty) return null;
    final maxV = ls.map((l) => l.votes).reduce(math.max);
    final strong = ls.where((l) => l.votes >= maxV * 0.35).toList()
      ..sort((a, b) => left ? b.xb.compareTo(a.xb) : a.xb.compareTo(b.xb));
    return strong.first; // the one closest to the car
  }

  final l = pick(lefts, true), r = pick(rights, false);

  double coverage(_Line line) {
    var hit = 0;
    for (var rr = 0; rr < rows; rr++) {
      final t = (rows - 1 - rr) / (rows - 1);
      final x = (line.xb + (line.xt - line.xb) * t).round();
      final tol = (1 + 2 * (1 - t)).round();
      var found = false;
      for (var dx = -tol; dx <= tol && !found; dx++) {
        final xx = x + dx;
        if (xx >= 0 && xx < w && mark[rr][xx] == 1) found = true;
      }
      if (found) hit++;
    }
    return hit / rows;
  }

  LineType type(double c) => c >= 0.72 ? LineType.solid : (c >= 0.15 ? LineType.dashed : LineType.none);

  final lc = l == null ? 0.0 : coverage(l);
  final rc = r == null ? 0.0 : coverage(r);
  double? offset;
  if (l != null && r != null && r.xb - l.xb > w * 0.3) {
    final center = (l.xb + r.xb) / 2;
    offset = ((cx - center) / (r.xb - l.xb)).clamp(-0.6, 0.6);
  }
  return LaneObservation(left: type(lc), right: type(rc), leftCoverage: lc, rightCoverage: rc, offset: offset);
}

/// The lane the car is in, for display.
class LaneInfo {
  const LaneInfo({this.count, this.index, this.left = LineType.none, this.right = LineType.none});

  /// Lanes in the driving direction (null = unknown).
  final int? count;

  /// 0 = leftmost lane (null = unknown).
  final int? index;
  final LineType left, right;

  static const unknown = LaneInfo();

  String? get label {
    final c = count, i = index;
    if (c == 1) return 'Einspurig';
    if (i == null) return c == null ? null : '$c Spuren';
    String name;
    if (i == 0) {
      name = 'Linke Spur';
    } else if (c != null && i == c - 1) {
      name = 'Rechte Spur';
    } else if (c == 3 || c == null) {
      name = 'Mittlere Spur';
    } else {
      name = '${i + 1}. Spur von links';
    }
    return c == null ? name : '$name · $c Spuren';
  }
}

/// Smooths the camera's lane observations over time and combines them
/// with the lane count from OpenStreetMap.
class LaneTracker {
  double _lc = 0, _rc = 0;
  LineType _left = LineType.none, _right = LineType.none;
  double? _lastOffset;
  int? _index;
  int? _count;
  DateTime? _lastSeen;

  LaneInfo get info => LaneInfo(count: _count, index: _index, left: _left, right: _right);

  void reset() {
    _lc = _rc = 0;
    _left = _right = LineType.none;
    _lastOffset = null;
    _index = null;
    _count = null;
    _lastSeen = null;
  }

  static LineType _classify(double c, LineType prev) {
    // Hysteresis so the type does not flicker as dashes pass by.
    switch (prev) {
      case LineType.solid:
        return c < 0.6 ? (c >= 0.12 ? LineType.dashed : LineType.none) : LineType.solid;
      case LineType.dashed:
        return c >= 0.78 ? LineType.solid : (c < 0.08 ? LineType.none : LineType.dashed);
      case LineType.none:
        return c >= 0.78 ? LineType.solid : (c >= 0.2 ? LineType.dashed : LineType.none);
    }
  }

  LaneInfo update(LaneObservation obs, {int? osmCount, DateTime? now}) {
    final t = now ?? DateTime.now();
    _count = osmCount;
    const a = 0.15;
    _lc = _lc * (1 - a) + obs.leftCoverage * a;
    _rc = _rc * (1 - a) + obs.rightCoverage * a;
    _left = _classify(_lc, _left);
    _right = _classify(_rc, _right);

    // Lane change: the offset jumps from one side of the lane to the other.
    final o = obs.offset;
    if (o != null) {
      final last = _lastOffset;
      if (last != null && _index != null) {
        if (last > 0.25 && o < -0.25) _index = _index! + 1; // crossed the right line
        if (last < -0.25 && o > 0.25) _index = _index! - 1; // crossed the left line
      }
      _lastOffset = o;
      _lastSeen = t;
    } else if (_lastSeen != null && t.difference(_lastSeen!) > const Duration(seconds: 2)) {
      _lastOffset = null;
    }

    final fromLines = laneIndexFromLines(_count, _left, _right);
    if (fromLines != null) _index = fromLines;
    if (_index != null && _count != null) _index = _index!.clamp(0, _count! - 1);
    if (_count == 1) _index = 0;
    return info;
  }
}

/// Which lane (0 = leftmost) follows from the markings on both sides.
/// A solid line on the left means the leftmost lane (next to the median or
/// the road edge), a solid line or no line on the right means the rightmost.
int? laneIndexFromLines(int? count, LineType left, LineType right) {
  if (count == 1) return 0;
  final leftEdge = left == LineType.solid;
  final rightEdge = right == LineType.solid || (right == LineType.none && left == LineType.dashed);
  if (leftEdge && rightEdge) return null; // contradictory (or a single lane)
  if (leftEdge) return 0;
  if (rightEdge) return count == null ? null : count - 1;
  if (left == LineType.dashed && right == LineType.dashed && count == 3) return 1;
  return null;
}
