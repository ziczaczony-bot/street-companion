import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/speed_limit.dart';
import 'theme.dart';

/// German-style round speed limit sign (Zeichen 274) or
/// end-of-restrictions sign (Zeichen 282) for unlimited motorways.
class SpeedSign extends StatelessWidget {
  const SpeedSign({super.key, required this.limit, required this.size, this.loading = false});
  final SpeedLimit? limit;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SignPainter(l),
        child: Center(
          child: l == null
              ? Text(loading ? '…' : '--', style: TextStyle(color: C.dim, fontSize: size * 0.32, fontWeight: FontWeight.w700))
              : l.unlimited
                  ? const SizedBox.shrink()
                  : SizedBox(
                      width: size * 0.62,
                      height: size * 0.5,
                      child: FittedBox(
                        child: Text(
                          l.label ?? '${l.kmh}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

class _SignPainter extends CustomPainter {
  _SignPainter(this.limit);
  final SpeedLimit? limit;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final l = limit;
    if (l == null) {
      canvas.drawCircle(c, r - 2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = C.line);
      return;
    }
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    if (l.unlimited) {
      canvas.drawCircle(c, r - 1, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = Colors.black26);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.92)));
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-math.pi / 4);
      final p = Paint()..color = Colors.black;
      for (var i = -2; i <= 2; i++) {
        canvas.drawRect(Rect.fromCenter(center: Offset(0, i * r * 0.16), width: r * 2.2, height: r * 0.07), p);
      }
      canvas.restore();
      return;
    }
    canvas.drawCircle(c, r * 0.89, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.2
      ..color = C.signRed);
  }

  @override
  bool shouldRepaint(_SignPainter old) => old.limit != limit;
}
