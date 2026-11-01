import 'package:flutter_test/flutter_test.dart';
import 'package:street_companion/core/lanes.dart';
import 'package:street_companion/core/road_map.dart';
import 'package:street_companion/core/scene.dart';
import 'package:street_companion/core/speed_limit.dart';
import 'package:street_companion/core/vehicles.dart';

void main() {
  test('parked car stays in the parking strip and passes backwards', () {
    final tr = SceneTracker()..setLayout(LaneLayout.from(const LaneInfo(count: 1, index: 0)));
    var t = DateTime(2026);
    const ego = 36.0; // km/h = 10 m/s
    var worldD = 30.0;
    for (var i = 0; i < 25; i++) {
      t = t.add(const Duration(milliseconds: 200));
      worldD -= 2; // we drive 2 m per frame
      final det = projectToImage(VehicleKind.car, worldD, 3.0);
      final objs = det == null ? <RoadObject>[] : placeOnRoad([det]);
      tr.update(objs, t, ego);
    }
    // Camera lost it beside us; keep predicting.
    for (var i = 0; i < 10; i++) {
      t = t.add(const Duration(milliseconds: 200));
      tr.predict(t, ego);
    }
    final layout = tr.layout;
    for (final tk in tr.tracks) {
      expect(tk.slot, layout.rightParking, reason: 'never moves into a lane');
      expect(tk.parked, isTrue);
      expect(tk.relV, closeTo(-10, 0.01));
    }
    if (tr.tracks.isNotEmpty) expect(tr.tracks.first.d, lessThan(0)); // went behind us
  });

  test('car in the right lane keeps its lane despite noisy lateral measurements', () {
    final tr = SceneTracker()..setLayout(LaneLayout.from(const LaneInfo(count: 2, index: 0)));
    var t = DateTime(2026);
    for (var i = 0; i < 30; i++) {
      t = t.add(const Duration(milliseconds: 200));
      final noise = (i % 3 - 1) * 1.4; // +-1.4 m jitter
      tr.update([
        RoadObject(
          detection: const Detection(kind: VehicleKind.car, score: 0.9, left: 0.7, right: 0.8, top: 0.4, bottom: 0.5),
          distanceM: 20 - i * 0.2,
          lateralM: 3.6 + noise,
        )
      ], t, 80);
    }
    expect(tr.tracks.length, 1);
    expect(tr.tracks.single.slot, 3.6);
    expect(tr.tracks.single.relV, lessThan(0)); // we are slowly overtaking it
  });

  test('roads around the car in its own frame', () {
    const pos = LatLon(52.52, 13.40);
    // Road going north from the car, and a side street 50 m ahead going east.
    final ways = [
      Way(id: 1, tags: {'highway': 'primary'}, geometry: const [LatLon(52.5195, 13.40), LatLon(52.5215, 13.40)]),
      Way(id: 2, tags: {'highway': 'residential'}, geometry: const [LatLon(52.52045, 13.40), LatLon(52.52045, 13.401)]),
    ];
    final roads = roadsAroundEgo(ways, pos, 0, currentWayId: 1);
    final side = roads.firstWhere((r) => !r.current);
    expect(side.points.first.$2, closeTo(50, 1)); // 50 m ahead
    expect(side.points.last.$1, greaterThan(60)); // goes off to the right
    // Facing east, the same side street runs ahead and is 50 m to the left.
    final east = roadsAroundEgo(ways, pos, 90).firstWhere((r) => r.widthM == 6);
    expect(east.points.first.$1, closeTo(-50, 1));
  });
}
