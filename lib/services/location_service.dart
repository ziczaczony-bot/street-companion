import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

class GpsFix {
  const GpsFix({required this.lat, required this.lon, required this.speedKmh, this.headingDeg, required this.accuracyM});
  final double lat, lon, speedKmh, accuracyM;
  final double? headingDeg;
}

enum GpsStatus { starting, denied, disabled, searching, ok }

/// GPS speed and position. Speed comes straight from the GPS chip
/// (Doppler), which is more exact than most car speedometers.
class LocationService {
  final _controller = StreamController<GpsFix>.broadcast();
  StreamSubscription<Position>? _sub;
  GpsStatus status = GpsStatus.starting;

  Stream<GpsFix> get fixes => _controller.stream;

  Future<GpsStatus> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) return status = GpsStatus.disabled;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return status = GpsStatus.denied;
    }
    status = GpsStatus.searching;
    final LocationSettings settings = Platform.isIOS
        ? AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.automotiveNavigation,
            distanceFilter: 0,
            pauseLocationUpdatesAutomatically: false,
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(milliseconds: 500),
          );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      status = GpsStatus.ok;
      final kmh = p.speed < 0 ? 0.0 : p.speed * 3.6;
      _controller.add(GpsFix(
        lat: p.latitude,
        lon: p.longitude,
        speedKmh: kmh,
        headingDeg: (kmh > 8 && p.heading >= 0) ? p.heading : null,
        accuracyM: p.accuracy,
      ));
    }, onError: (_) => status = GpsStatus.searching);
    return status;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
