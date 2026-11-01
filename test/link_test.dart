import 'package:flutter_test/flutter_test.dart';
import 'package:street_companion/core/lanes.dart';
import 'package:street_companion/core/link.dart';
import 'package:street_companion/core/vehicles.dart';

void main() {
  test('frame survives the trip between the phones', () {
    const f = LinkFrame(
      seq: 42,
      detections: [
        Detection(kind: VehicleKind.truck, score: 0.87, left: 0.1, top: 0.2, right: 0.35, bottom: 0.6),
        Detection(kind: VehicleKind.person, score: 0.55, left: 0.7, top: 0.4, right: 0.75, bottom: 0.7),
      ],
      lanes: LaneObservation(left: LineType.solid, right: LineType.dashed, leftCoverage: 0.95, rightCoverage: 0.4, offset: -0.12),
      luma: 101.6,
      aspect: 4 / 3,
      inferenceMs: 230,
    );
    final text = f.encode();
    expect(text.length, lessThan(400)); // fits easily in one UDP packet
    final g = LinkFrame.decode(text)!;
    expect(g.seq, 42);
    expect(g.detections, hasLength(2));
    expect(g.detections[0].kind, VehicleKind.truck);
    expect(g.detections[0].left, closeTo(0.1, 0.001));
    expect(g.detections[0].bottom, closeTo(0.6, 0.001));
    expect(g.detections[1].score, closeTo(0.55, 0.01));
    expect(g.lanes.left, LineType.solid);
    expect(g.lanes.right, LineType.dashed);
    expect(g.lanes.offset, closeTo(-0.12, 0.001));
    expect(g.luma, 102);
    expect(g.aspect, closeTo(4 / 3, 0.001));
    expect(g.inferenceMs, 230);
  });

  test('lanes without offset and empty frames', () {
    const f = LinkFrame(seq: 0, detections: [], lanes: LaneObservation.empty, luma: 0, aspect: 0.75, inferenceMs: 0);
    final g = LinkFrame.decode(f.encode())!;
    expect(g.detections, isEmpty);
    expect(g.lanes.offset, isNull);
    expect(g.lanes.left, LineType.none);
  });

  test('ignores packets that are not ours', () {
    expect(LinkFrame.decode('hello'), isNull);
    expect(LinkFrame.decode('{"v":2}'), isNull);
    expect(LinkFrame.decode('{"v":1,"s":1}'), isNull);
    expect(LinkFrame.decode(linkAck), isNull);
  });

  test('finds the hotspot phone', () {
    expect(hotspotHostFor('172.20.10.3'), '172.20.10.1'); // iPhone hotspot
    expect(hotspotHostFor('192.168.43.120'), '192.168.43.1'); // Android hotspot
    expect(hotspotHostFor('10.12.5.77'), '10.12.5.1');
    expect(hotspotHostFor('192.168.43.1'), isNull); // that is us
    expect(hotspotHostFor('8.8.8.8'), isNull);
    expect(hotspotHostFor('nonsense'), isNull);
  });

  test('checks typed addresses', () {
    expect(isIpv4('172.20.10.1'), isTrue);
    expect(isIpv4(' 192.168.1.5 '), isTrue);
    expect(isIpv4('192.168.1'), isFalse);
    expect(isIpv4('300.1.1.1'), isFalse);
  });
}
