import 'dart:convert';

import 'lanes.dart';
import 'vehicles.dart';

/// Two-phone mode: a "camera phone" at the windshield runs the detection
/// and sends only the results (a few hundred bytes, ~5 times a second) to
/// a "display phone" over the display phone's hotspot. No pictures are
/// sent.

/// UDP port the display phone listens on.
const linkPort = 47123;

/// Reply the display phone sends back so the camera phone knows it is heard.
const linkAck = 'SC-ACK';

/// What this phone does.
enum DeviceRole {
  /// One phone does everything (default).
  single,

  /// Sits at the windshield, runs the camera and sends results.
  camera,

  /// Shows the dashboard and gets vehicles and lanes from the camera phone.
  display,
}

/// One camera result as it travels between the phones.
class LinkFrame {
  const LinkFrame({
    required this.seq,
    required this.detections,
    required this.lanes,
    required this.luma,
    required this.aspect,
    required this.inferenceMs,
  });

  final int seq;
  final List<Detection> detections;
  final LaneObservation lanes;
  final double luma;

  /// Upright image width / height of the camera phone.
  final double aspect;
  final int inferenceMs;

  static int _q(double v, int scale) => (v * scale).round();

  String encode() => jsonEncode({
        'v': 1,
        's': seq,
        'd': [
          for (final d in detections)
            [d.kind.index, _q(d.score, 100), _q(d.left, 1000), _q(d.top, 1000), _q(d.right, 1000), _q(d.bottom, 1000)],
        ],
        'l': [
          lanes.left.index,
          lanes.right.index,
          _q(lanes.leftCoverage, 100),
          _q(lanes.rightCoverage, 100),
          lanes.offset == null ? null : _q(lanes.offset!, 1000),
        ],
        'y': luma.round(),
        'a': _q(aspect, 1000),
        'i': inferenceMs,
      });

  /// Null for anything that is not a valid frame (other apps, garbage).
  static LinkFrame? decode(String text) {
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['v'] != 1) return null;
      final dets = <Detection>[];
      for (final e in m['d'] as List) {
        final a = (e as List).cast<num>();
        if (a.length < 6 || a[0] < 0 || a[0] >= VehicleKind.values.length) continue;
        double c(num v) => (v / 1000).clamp(0.0, 1.0).toDouble();
        dets.add(Detection(
          kind: VehicleKind.values[a[0].toInt()],
          score: a[1] / 100,
          left: c(a[2]),
          top: c(a[3]),
          right: c(a[4]),
          bottom: c(a[5]),
        ));
      }
      final l = m['l'] as List;
      LineType line(Object? v) {
        final i = (v as num?)?.toInt() ?? 0;
        return i >= 0 && i < LineType.values.length ? LineType.values[i] : LineType.none;
      }

      final off = l[4] as num?;
      return LinkFrame(
        seq: (m['s'] as num).toInt(),
        detections: dets,
        lanes: LaneObservation(
          left: line(l[0]),
          right: line(l[1]),
          leftCoverage: (l[2] as num) / 100,
          rightCoverage: (l[3] as num) / 100,
          offset: off == null ? null : off / 1000,
        ),
        luma: (m['y'] as num).toDouble(),
        aspect: (m['a'] as num) / 1000,
        inferenceMs: (m['i'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The phone that shares its hotspot is the network's gateway, which is
/// the ".1" address on almost every phone (iPhone: 172.20.10.1, Android:
/// 192.168.x.1). Null for addresses that are not on a private network.
String? hotspotHostFor(String ownIp) {
  final p = ownIp.split('.');
  if (p.length != 4) return null;
  final o = p.map(int.tryParse).toList();
  if (o.any((x) => x == null || x < 0 || x > 255)) return null;
  final a = o[0]!, b = o[1]!;
  final private = a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  if (!private || o[3] == 1) return null; // we are the gateway ourselves
  return '${p[0]}.${p[1]}.${p[2]}.1';
}

/// Simple check for an IPv4 address typed by the user.
bool isIpv4(String s) {
  final p = s.trim().split('.');
  return p.length == 4 && p.every((x) => int.tryParse(x) != null && int.parse(x) >= 0 && int.parse(x) <= 255);
}
