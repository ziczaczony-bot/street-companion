import 'package:flutter_test/flutter_test.dart';
import 'package:street_companion/core/lanes.dart';
import 'package:street_companion/core/link.dart';
import 'package:street_companion/core/vehicles.dart';
import 'package:street_companion/services/camera_link.dart';
import 'package:street_companion/services/vehicle_detector.dart';

void main() {
  test('camera phone sends, display phone receives and answers', () async {
    final rx = LinkReceiver();
    expect(await rx.start(), isTrue);
    final got = <LinkFrame>[];
    final sub = rx.frames.listen(got.add);

    final tx = LinkSender()..manualHost = '127.0.0.1';
    await tx.start();
    const r = FrameResult(
      detections: [Detection(kind: VehicleKind.car, score: 0.9, left: 0.4, top: 0.5, right: 0.6, bottom: 0.7)],
      luma: 80,
      camera: CameraModel(4 / 3),
      inferenceMs: 120,
      lanes: LaneObservation(left: LineType.solid),
    );
    for (var i = 0; i < 5 && got.isEmpty; i++) {
      tx.send(r);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(got, isNotEmpty);
    expect(got.first.detections.single.kind, VehicleKind.car);
    expect(got.first.lanes.left, LineType.solid);
    expect(rx.connected, isTrue);
    expect(tx.connected, isTrue); // the answer came back
    expect(tx.target, '127.0.0.1');

    await sub.cancel();
    await tx.stop();
    await rx.stop();
  });
}
