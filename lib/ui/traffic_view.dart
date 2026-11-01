import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/lanes.dart';
import '../core/road_map.dart';
import '../core/scene.dart';
import '../core/vehicles.dart';
import 'theme.dart';

/// Animated bird's-eye-behind view of the road, like the display of a
/// modern car: own car at the bottom, detected vehicles placed ahead in
/// their lanes, real side roads from OpenStreetMap around.
class TrafficView extends StatefulWidget {
  const TrafficView({
    super.key,
    required this.objects,
    required this.speedKmh,
    required this.departure,
    this.lanes = LaneInfo.unknown,
    this.roads = const [],
    this.roadsAt,
  });
  final List<RoadObject> objects;
  final LaneInfo lanes;
  final double speedKmh;
  final bool departure;
  final List<EgoRoad> roads;
  final DateTime? roadsAt;

  @override
  State<TrafficView> createState() => _TrafficViewState();
}

/// Snapshot of a track for painting.
class _Tracked {
  _Tracked(this.kind, this.lateral, this.distance, this.isLead, this.opacity);
  final VehicleKind kind;
  final double lateral, distance;
  final bool isLead;
  final double opacity;
}

class _TrafficViewState extends State<TrafficView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _travelled = 0;
  final _scene = SceneTracker();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(TrafficView old) {
    super.didUpdateWidget(old);
    _scene.setLayout(LaneLayout.from(widget.lanes));
    if (!identical(old.objects, widget.objects)) {
      _scene.update(widget.objects, DateTime.now(), widget.speedKmh);
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _travelled += widget.speedKmh / 3.6 * dt;
    _scene.predict(DateTime.now(), widget.speedKmh);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.roadsAt;
    final shift = at == null ? 0.0 : (DateTime.now().difference(at).inMilliseconds / 1000.0).clamp(0.0, 2.0) * widget.speedKmh / 3.6;
    return CustomPaint(
      painter: _RoadPainter(
        tracked: [for (final t in _scene.tracks) _Tracked(t.kind, t.x, t.d, t.isLead, t.opacity)],
        travelled: _travelled,
        speedKmh: widget.speedKmh,
        departure: widget.departure,
        lanes: widget.lanes,
        roads: widget.roads,
        roadShift: shift,
      ),
      size: Size.infinite,
    );
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.tracked,
    required this.travelled,
    required this.speedKmh,
    required this.departure,
    required this.lanes,
    required this.roads,
    required this.roadShift,
  });
  final List<_Tracked> tracked;
  final LaneInfo lanes;
  final List<EgoRoad> roads;
  final double roadShift;
  final double travelled;
  final double speedKmh;
  final bool departure;

  static const _c = 12.0; // virtual camera distance behind own car (m)
  static const _maxD = 70.0;

  late double _w, _h, _horizon, _k, _kx;

  Offset _p(double lateral, double d) {
    final s = 1 / (d + _c);
    return Offset(_w / 2 + lateral * _kx * s, _horizon + _k * s);
  }

  double _scale(double d) => _kx / (d + _c);

  @override
  void paint(Canvas canvas, Size size) {
    _w = size.width;
    _h = size.height;
    _horizon = _h * 0.10;
    final ownY = _h * 0.80;
    _k = (ownY - _horizon) * _c;
    _kx = math.min(_w * 0.30, _h * 0.42) / 3.6 * _c;

    // Sky glow.
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0D1520), C.bg],
      ).createShader(Offset.zero & size));

    _drawMapRoads(canvas);

    // Lane lines: (lateral position in m, type). Own lane centre = 0.
    const lw = 3.6;
    final lines = <(double, LineType)>[];
    final count = lanes.count, index = lanes.index;
    if (count != null && count > 1 && index != null) {
      for (var i = 0; i <= count; i++) {
        final x = (i - index - 0.5) * lw;
        lines.add((x, (i == 0 || i == count) ? LineType.solid : LineType.dashed));
      }
    } else {
      // Unknown or one lane per direction: own lane plus oncoming lane on the left.
      lines.add((-1.5 * lw, LineType.solid));
      lines.add((-0.5 * lw, lanes.left == LineType.solid ? LineType.solid : LineType.dashed));
      lines.add((0.5 * lw, count == 1 || lanes.right == LineType.solid ? LineType.solid : LineType.dashed));
      if (count == null) lines.add((1.5 * lw, LineType.solid));
    }
    final leftX = lines.first.$1 - 1.0, rightX = lines.last.$1 + 1.0;

    // Road surface.
    final road = Path()
      ..moveTo(_p(leftX, _maxD).dx, _p(leftX, _maxD).dy)
      ..lineTo(_p(rightX, _maxD).dx, _p(rightX, _maxD).dy)
      ..lineTo(_p(rightX, -_c * 0.75).dx, _p(rightX, -_c * 0.75).dy)
      ..lineTo(_p(leftX, -_c * 0.75).dx, _p(leftX, -_c * 0.75).dy)
      ..close();
    canvas.drawPath(road, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF111821).withValues(alpha: 0.2), const Color(0xFF18212C)],
      ).createShader(Offset.zero & size));

    final solid = Paint()
      ..color = const Color(0xFF6A7B90)
      ..strokeWidth = 2.5;
    final dash = Paint()..color = const Color(0xFF8495AA);
    const period = 12.0, len = 4.0;
    final off = travelled % period;
    for (final (x, type) in lines) {
      if (type == LineType.solid) {
        canvas.drawLine(_p(x, _maxD), _p(x, -_c * 0.7), solid);
        continue;
      }
      // Moving dashes.
      for (var d = -off - period; d < _maxD; d += period) {
        final d0 = math.max(d, -_c * 0.7), d1 = math.min(d + len, _maxD);
        if (d1 <= d0) continue;
        dash.strokeWidth = (0.15 * _scale(d0)).clamp(1.0, 5.0);
        canvas.drawLine(_p(x, d0), _p(x, d1), dash..color = const Color(0xFF8495AA).withValues(alpha: _fade(d0)));
      }
    }

    // Own lane highlight.
    final lane = Path()
      ..moveTo(_p(-1.6, 0).dx, _p(-1.6, 0).dy)
      ..lineTo(_p(1.6, 0).dx, _p(1.6, 0).dy)
      ..lineTo(_p(1.6, 40).dx, _p(1.6, 40).dy)
      ..lineTo(_p(-1.6, 40).dx, _p(-1.6, 40).dy)
      ..close();
    canvas.drawPath(lane, Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [(departure ? C.ok : C.accent).withValues(alpha: 0.16), Colors.transparent],
      ).createShader(Rect.fromLTRB(0, _p(0, 40).dy, _w, _p(0, 0).dy)));

    // Vehicles, far to near.
    final sorted = [...tracked]..sort((a, b) => b.distance.compareTo(a.distance));
    for (final t in sorted) {
      if (t.distance > _maxD) continue;
      Color color;
      if (t.isLead) {
        final tooClose = speedKmh > 20 && t.distance < speedKmh / 2; // "halber Tacho"
        color = departure ? C.ok : (tooClose ? C.warn : C.accent);
      } else {
        color = const Color(0xFFB8C4D2);
      }
      _drawVehicle(canvas, t.kind, t.lateral, t.distance, color, t.opacity * _fade(t.distance), lead: t.isLead);
      if (t.isLead && t.opacity > 0.5) {
        final p = _p(t.lateral, t.distance);
        final tp = TextPainter(
          text: TextSpan(
            text: '${t.distance.round()} m',
            style: TextStyle(color: color, fontSize: math.max(13, _h * 0.04), fontWeight: FontWeight.w700, fontFamily: 'Roboto'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final top = p.dy - typicalWidthM(t.kind) * _scale(t.distance) * 1.1;
        tp.paint(canvas, Offset(p.dx - tp.width / 2, top - tp.height - 6));
      }
    }

    // Own car.
    _drawVehicle(canvas, VehicleKind.car, 0, 0, C.text, 1, own: true);
  }

  /// Real roads from OpenStreetMap as flat ribbons on the ground.
  void _drawMapRoads(Canvas canvas) {
    final near = -_c * 0.7;
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF2C3A4B);
    final labels = <(Offset, String)>[];
    for (final r in roads) {
      final pts = [for (final (x, d) in r.points) (x, d - roadShift)];
      for (var i = 0; i + 1 < pts.length; i++) {
        var (ax, ad) = pts[i];
        var (bx, bd) = pts[i + 1];
        if ((ad < near && bd < near) || (ad > _maxD && bd > _maxD)) continue;
        // Clip the segment to the visible depth range.
        (double, double) at(double d) {
          final t = (d - ad) / (bd - ad);
          return (ax + (bx - ax) * t, d);
        }

        if (ad < near) (ax, ad) = at(near);
        if (bd < near) (bx, bd) = at(near);
        if (ad > _maxD) (ax, ad) = at(_maxD);
        if (bd > _maxD) (bx, bd) = at(_maxD);
        final len = math.sqrt((bx - ax) * (bx - ax) + (bd - ad) * (bd - ad));
        if (len < 0.01) continue;
        final nx = -(bd - ad) / len * r.widthM / 2, nd = (bx - ax) / len * r.widthM / 2;
        final alpha = _fade(math.min(ad, bd));
        final quad = Path()
          ..moveTo(_p(ax + nx, ad + nd).dx, _p(ax + nx, ad + nd).dy)
          ..lineTo(_p(bx + nx, bd + nd).dx, _p(bx + nx, bd + nd).dy)
          ..lineTo(_p(bx - nx, bd - nd).dx, _p(bx - nx, bd - nd).dy)
          ..lineTo(_p(ax - nx, ad - nd).dx, _p(ax - nx, ad - nd).dy)
          ..close();
        canvas.drawPath(quad, fill..color = const Color(0xFF1B2430).withValues(alpha: alpha));
        canvas.drawPath(quad, edge..color = const Color(0xFF3A4A5E).withValues(alpha: alpha));
        if (!r.current && r.name != null && i == 0 && ad > 8 && ad < 50 && ax.abs() < 30) {
          labels.add((_p(ax + (bx - ax) * 0.3, ad + (bd - ad) * 0.3), r.name!));
        }
      }
    }
    for (final (pos, text) in labels) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: C.dim, fontSize: math.max(11, _h * 0.03), fontFamily: 'Roboto')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height - 2));
    }
  }

  double _fade(double d) => (1 - (d - 45) / 25).clamp(0.0, 1.0);

  void _drawVehicle(Canvas canvas, VehicleKind kind, double lateral, double d, Color color, double alpha,
      {bool lead = false, bool own = false}) {
    if (alpha <= 0.01) return;
    final s = _scale(d);
    final base = _p(lateral, d);
    final wM = typicalWidthM(kind);
    final hM = switch (kind) {
      VehicleKind.truck => 2.6,
      VehicleKind.bus => 2.6,
      VehicleKind.motorcycle || VehicleKind.bicycle => 1.3,
      VehicleKind.person => 1.7,
      VehicleKind.car => 1.35,
    };
    final w = wM * s, h = hM * s * 0.85;
    final depth = (kind == VehicleKind.truck || kind == VehicleKind.bus ? 7.0 : 4.2);
    final backTop = _p(lateral, d + depth);
    final topH = (base.dy - backTop.dy);
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(base.dx - w / 2, base.dy - h, w, h),
      Radius.circular(w * 0.16),
    );
    // Roof/top surface going away from the viewer.
    final roofW = w * 0.82;
    final roof = Path()
      ..moveTo(base.dx - w / 2, base.dy - h)
      ..lineTo(base.dx + w / 2, base.dy - h)
      ..lineTo(base.dx + roofW / 2, base.dy - h - math.min(topH * 0.2, h * 0.45))
      ..lineTo(base.dx - roofW / 2, base.dy - h - math.min(topH * 0.2, h * 0.45))
      ..close();
    // Shadow.
    canvas.drawOval(Rect.fromCenter(center: base.translate(0, h * 0.04), width: w * 1.15, height: h * 0.22),
        Paint()..color = Colors.black.withValues(alpha: 0.45 * alpha));
    canvas.drawPath(roof, Paint()..color = Color.lerp(color, Colors.black, 0.45)!.withValues(alpha: alpha));
    canvas.drawRRect(body, Paint()..color = Color.lerp(color, Colors.black, own ? 0.1 : 0.2)!.withValues(alpha: alpha));
    // Rear window.
    if (kind == VehicleKind.car) {
      final win = RRect.fromRectAndRadius(
        Rect.fromLTWH(base.dx - w * 0.36, base.dy - h * 0.92, w * 0.72, h * 0.34),
        Radius.circular(w * 0.06),
      );
      canvas.drawRRect(win, Paint()..color = const Color(0xFF0A0F16).withValues(alpha: 0.85 * alpha));
    }
    // Tail lights.
    final tl = Paint()..color = const Color(0xFFFF3040).withValues(alpha: alpha);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(base.dx - w * 0.47, base.dy - h * 0.45, w * 0.16, h * 0.1), Radius.circular(h * 0.05)), tl);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(base.dx + w * 0.31, base.dy - h * 0.45, w * 0.16, h * 0.1), Radius.circular(h * 0.05)), tl);
    if (lead) {
      canvas.drawRRect(body.inflate(3), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => true;
}
