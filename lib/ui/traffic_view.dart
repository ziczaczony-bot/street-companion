import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/vehicles.dart';
import 'theme.dart';

/// Animated bird's-eye-behind view of the road, like the display of a
/// modern car: own car at the bottom, detected vehicles placed ahead.
class TrafficView extends StatefulWidget {
  const TrafficView({super.key, required this.objects, required this.speedKmh, required this.departure});
  final List<RoadObject> objects;
  final double speedKmh;
  final bool departure;

  @override
  State<TrafficView> createState() => _TrafficViewState();
}

class _Tracked {
  _Tracked(this.kind, this.lateral, this.distance);
  VehicleKind kind;
  double lateral, distance;
  double targetLateral = 0, targetDistance = 0;
  double opacity = 0;
  bool alive = true;
  bool isLead = false;
}

class _TrafficViewState extends State<TrafficView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _travelled = 0;
  final List<_Tracked> _tracked = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(TrafficView old) {
    super.didUpdateWidget(old);
    if (!identical(old.objects, widget.objects)) _match(widget.objects);
  }

  void _match(List<RoadObject> objs) {
    for (final t in _tracked) {
      t.alive = false;
    }
    for (final o in objs) {
      _Tracked? best;
      var bestD = 6.0;
      for (final t in _tracked) {
        if (t.alive) continue;
        final d = (t.targetLateral - o.lateralM).abs() + (t.targetDistance - o.distanceM).abs() * 0.25;
        if (d < bestD) {
          bestD = d;
          best = t;
        }
      }
      best ??= (_Tracked(o.kind, o.lateralM, o.distanceM)..opacity = 0).also(_tracked.add);
      best
        ..alive = true
        ..kind = o.kind
        ..isLead = o.isLead
        ..targetLateral = o.lateralM
        ..targetDistance = o.distanceM;
    }
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.016 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _travelled += widget.speedKmh / 3.6 * dt;
    final k = 1 - math.exp(-dt * 6);
    for (final t in _tracked) {
      t.lateral += (t.targetLateral - t.lateral) * k;
      t.distance += (t.targetDistance - t.distance) * k;
      t.opacity = (t.opacity + (t.alive ? dt * 4 : -dt * 3)).clamp(0.0, 1.0);
    }
    _tracked.removeWhere((t) => !t.alive && t.opacity <= 0);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoadPainter(
        tracked: List.of(_tracked),
        travelled: _travelled,
        speedKmh: widget.speedKmh,
        departure: widget.departure,
      ),
      size: Size.infinite,
    );
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({required this.tracked, required this.travelled, required this.speedKmh, required this.departure});
  final List<_Tracked> tracked;
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

    // Road surface.
    const half = 7.0;
    final road = Path()
      ..moveTo(_p(-half, _maxD).dx, _p(-half, _maxD).dy)
      ..lineTo(_p(half, _maxD).dx, _p(half, _maxD).dy)
      ..lineTo(_p(half, -_c * 0.75).dx, _p(half, -_c * 0.75).dy)
      ..lineTo(_p(-half, -_c * 0.75).dx, _p(-half, -_c * 0.75).dy)
      ..close();
    canvas.drawPath(road, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF111821).withValues(alpha: 0.2), const Color(0xFF18212C)],
      ).createShader(Offset.zero & size));

    // Edge lines.
    final edge = Paint()
      ..color = const Color(0xFF55657A)
      ..strokeWidth = 2;
    for (final x in [-5.4, 5.4]) {
      canvas.drawLine(_p(x, _maxD), _p(x, -_c * 0.7), edge);
    }
    // Moving lane dashes.
    final dash = Paint()..color = const Color(0xFF8495AA);
    const period = 12.0, len = 4.0;
    final off = travelled % period;
    for (final x in [-1.8, 1.8]) {
      for (var d = -off - period; d < _maxD; d += period) {
        final d0 = math.max(d, -_c * 0.7), d1 = math.min(d + len, _maxD);
        if (d1 <= d0) continue;
        final a = _p(x, d0), b = _p(x, d1);
        dash.strokeWidth = (0.15 * _scale(d0)).clamp(1.0, 5.0);
        canvas.drawLine(a, b, dash..color = const Color(0xFF8495AA).withValues(alpha: _fade(d0)));
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
