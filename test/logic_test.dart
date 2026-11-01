import 'package:flutter_test/flutter_test.dart';
import 'package:street_companion/core/speed_limit.dart';
import 'package:street_companion/core/vehicles.dart';

void main() {
  group('parseMaxspeed', () {
    test('numbers and units', () {
      expect(parseMaxspeed('50')!.kmh, 50);
      expect(parseMaxspeed('30 mph')!.kmh, 48);
      expect(parseMaxspeed('70 km/h')!.kmh, 70);
      expect(parseMaxspeed('80;60')!.kmh, 80);
    });
    test('German implicit values', () {
      expect(parseMaxspeed('DE:urban')!.kmh, 50);
      expect(parseMaxspeed('DE:rural')!.kmh, 100);
      expect(parseMaxspeed('DE:zone:30')!.kmh, 30);
      expect(parseMaxspeed('DE:zone30')!.kmh, 30);
      expect(parseMaxspeed('DE:motorway')!.unlimited, isTrue);
      expect(parseMaxspeed('none')!.unlimited, isTrue);
      expect(parseMaxspeed('walk')!.label, 'Schritt');
    });
    test('unknown', () {
      expect(parseMaxspeed('signals'), isNull);
      expect(parseMaxspeed('fast'), isNull);
      expect(parseMaxspeed(null), isNull);
    });
    test('directional and fallback tags', () {
      final tags = {'highway': 'primary', 'maxspeed:forward': '70', 'maxspeed:backward': '50'};
      expect(limitFromTags(tags, forward: true)!.kmh, 70);
      expect(limitFromTags(tags, forward: false)!.kmh, 50);
      expect(limitFromTags({'highway': 'motorway'})!.unlimited, isTrue);
      expect(limitFromTags({'highway': 'residential', 'maxspeed:type': 'DE:urban'})!.kmh, 50);
      expect(limitFromTags({'highway': 'residential'}), isNull);
    });
  });

  group('matchWay', () {
    // Two parallel streets running east-west, ~30 m apart in Berlin.
    final a = Way(id: 1, tags: {'highway': 'primary', 'maxspeed': '50'}, geometry: const [
      LatLon(52.5200, 13.4000),
      LatLon(52.5200, 13.4100),
    ]);
    final b = Way(id: 2, tags: {'highway': 'residential', 'maxspeed': '30'}, geometry: const [
      LatLon(52.52027, 13.4000),
      LatLon(52.52027, 13.4100),
    ]);
    // A north-south street crossing near the car.
    final c = Way(id: 3, tags: {'highway': 'secondary', 'maxspeed': '60'}, geometry: const [
      LatLon(52.5150, 13.40505),
      LatLon(52.5250, 13.40505),
    ]);

    test('picks nearest street', () {
      final m = matchWay([a, b], const LatLon(52.52003, 13.405));
      expect(m!.way.id, 1);
    });
    test('heading disambiguates at a crossing', () {
      final m = matchWay([a, c], const LatLon(52.52002, 13.40503), headingDeg: 0);
      expect(m!.way.id, 3);
      final m2 = matchWay([a, c], const LatLon(52.52002, 13.40503), headingDeg: 90);
      expect(m2!.way.id, 1);
    });
    test('direction along the way', () {
      expect(matchWay([a], const LatLon(52.52, 13.405), headingDeg: 90)!.forward, isTrue);
      expect(matchWay([a], const LatLon(52.52, 13.405), headingDeg: 270)!.forward, isFalse);
    });
    test('nothing in range', () {
      expect(matchWay([a], const LatLon(52.53, 13.405)), isNull);
    });
  });

  test('overspeed hysteresis', () {
    final t = OverspeedTracker();
    const limit = SpeedLimit(kmh: 50);
    expect(t.update(52, limit, 3), isFalse);
    expect(t.update(54, limit, 3), isTrue);
    expect(t.update(55, limit, 3), isFalse); // already warned
    expect(t.isOver, isTrue);
    expect(t.update(52, limit, 3), isFalse);
    expect(t.isOver, isTrue); // hysteresis
    expect(t.update(50, limit, 3), isFalse);
    expect(t.isOver, isFalse);
    expect(t.update(200, const SpeedLimit(unlimited: true), 3), isFalse);
  });

  group('DepartureMonitor', () {
    Detection car(double w) =>
        Detection(kind: VehicleKind.car, score: 0.9, left: 0.5 - w / 2, right: 0.5 + w / 2, top: 0.4, bottom: 0.4 + w * 0.7);

    test('fires once when the car ahead drives off', () {
      final m = DepartureMonitor();
      var t = DateTime(2026);
      bool step(double speed, Detection? d, {int ms = 100}) {
        t = t.add(Duration(milliseconds: ms));
        return m.update(t, speed, d);
      }

      for (var i = 0; i < 30; i++) {
        expect(step(0, car(0.3)), isFalse);
      }
      expect(m.armed, isTrue);
      var fired = false;
      var w = 0.3;
      for (var i = 0; i < 30; i++) {
        w *= 0.97;
        fired |= step(0, car(w));
      }
      expect(fired, isTrue);
      // No second alert while still standing.
      for (var i = 0; i < 20; i++) {
        expect(step(0, car(0.1)), isFalse);
      }
    });

    test('does not fire while both cars stand', () {
      final m = DepartureMonitor();
      var t = DateTime(2026);
      for (var i = 0; i < 100; i++) {
        t = t.add(const Duration(milliseconds: 100));
        final jitter = (i % 3 - 1) * 0.01;
        expect(m.update(t, 0, car(0.3 + jitter)), isFalse);
      }
    });

    test('does not fire when we drive too', () {
      final m = DepartureMonitor();
      var t = DateTime(2026);
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 100));
        m.update(t, 0, car(0.3));
      }
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 100));
        expect(m.update(t, 10, car(0.2)), isFalse);
      }
    });

    test('fires when lead disappears', () {
      final m = DepartureMonitor();
      var t = DateTime(2026);
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 100));
        m.update(t, 0, car(0.3));
      }
      var fired = false;
      for (var i = 0; i < 20; i++) {
        t = t.add(const Duration(milliseconds: 100));
        fired |= m.update(t, 0, null);
      }
      expect(fired, isTrue);
    });
  });

  test('lead selection ignores cars in other lanes', () {
    const left = Detection(kind: VehicleKind.car, score: 0.9, left: 0.0, right: 0.2, top: 0.5, bottom: 0.9);
    const ahead = Detection(kind: VehicleKind.car, score: 0.9, left: 0.4, right: 0.6, top: 0.4, bottom: 0.6);
    expect(selectLead([left, ahead]), same(ahead));
    expect(selectLead([left]), isNull);
    final road = placeOnRoad([ahead], portrait: false);
    expect(road.single.isLead, isTrue);
    expect(road.single.distanceM, closeTo(7.0, 0.1));
  });
}
