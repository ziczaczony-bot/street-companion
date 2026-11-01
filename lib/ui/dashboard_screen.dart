import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/vehicles.dart';
import '../services/drive_controller.dart';
import '../services/location_service.dart';
import '../services/vehicle_detector.dart';
import 'settings_screen.dart';
import 'speed_sign.dart';
import 'theme.dart';
import 'traffic_view.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.drive});
  final DriveController drive;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  DriveController get d => widget.drive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    d.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release camera and GPS when the app is in the background.
    if (state == AppLifecycleState.paused) d.stop();
    if (state == AppLifecycleState.resumed) d.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    d.stop();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await d.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(settings: d.settings)));
    await d.restart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: d,
          builder: (context, _) {
            return LayoutBuilder(builder: (context, box) {
              final landscape = box.maxWidth > box.maxHeight;
              final traffic = _TrafficCard(d: d);
              final speed = _SpeedPanel(d: d, compact: !landscape);
              final content = landscape
                  ? Row(children: [
                      SizedBox(width: box.maxWidth * 0.36, child: speed),
                      const SizedBox(width: 10),
                      Expanded(child: traffic),
                    ])
                  : Column(children: [
                      Expanded(flex: 5, child: traffic),
                      const SizedBox(height: 10),
                      Expanded(flex: 4, child: speed),
                    ]);
              return Padding(
                padding: const EdgeInsets.all(10),
                child: Stack(children: [
                  Positioned.fill(child: content),
                  Positioned(top: 0, right: 0, child: _TopBar(d: d, onSettings: _openSettings)),
                ]),
              );
            });
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.d, required this.onSettings});
  final DriveController d;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final gpsColor = switch (d.gpsStatus) {
      GpsStatus.ok => C.ok,
      GpsStatus.searching || GpsStatus.starting => C.warn,
      _ => C.danger,
    };
    final camColor = switch (d.detector.status) {
      CameraStatus.running => C.ok,
      CameraStatus.starting => C.warn,
      CameraStatus.off => C.dim,
      _ => C.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: C.panel.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (d.demo)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('DEMO', style: TextStyle(color: C.warn, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
        Icon(Icons.gps_fixed, size: 18, color: gpsColor),
        const SizedBox(width: 8),
        Icon(Icons.videocam, size: 18, color: d.demo ? C.dim : camColor),
        IconButton(onPressed: onSettings, icon: const Icon(Icons.settings, color: C.dim), tooltip: 'Einstellungen'),
      ]),
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.d, required this.compact});
  final DriveController d;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final over = d.overspeed;
    final speedColor = over ? C.danger : C.text;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: over ? const Color(0xFF2A0D10) : C.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: over ? C.danger : C.line, width: over ? 3 : 1),
      ),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, box) {
        final unit = compact ? box.maxHeight : box.maxHeight * 0.55;
        final sign = SpeedSign(
          limit: d.limit,
          size: (compact ? box.maxHeight * 0.62 : box.maxWidth * 0.42).clamp(60.0, 200.0),
          loading: d.hasGps && d.limits.loading,
        );
        final speed = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                d.hasGps ? d.speedKmh.round().toString() : '--',
                style: TextStyle(
                  color: speedColor,
                  fontSize: unit * 0.5,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text('km/h', style: TextStyle(color: C.dim, fontSize: (unit * 0.08).clamp(12.0, 22.0))),
          ],
        );
        final status = Text(
          _statusText(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: over ? C.danger : C.dim, fontSize: 15, fontWeight: over ? FontWeight.w700 : FontWeight.w400),
        );
        if (compact) {
          return Row(children: [
            Expanded(child: Center(child: speed)),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [sign, const SizedBox(height: 8), SizedBox(width: box.maxWidth * 0.45, child: status)]),
          ]);
        }
        return Column(
          children: [
            const SizedBox(height: 24),
            Expanded(child: Center(child: speed)),
            sign,
            const SizedBox(height: 10),
            status,
          ],
        );
      }),
    );
  }

  String _statusText() {
    if (d.overspeed) return 'Zu schnell!';
    switch (d.gpsStatus) {
      case GpsStatus.denied:
        return 'Standort-Zugriff erlauben (Einstellungen)';
      case GpsStatus.disabled:
        return 'Standort (GPS) einschalten';
      case GpsStatus.starting:
      case GpsStatus.searching:
        return 'Suche GPS …';
      case GpsStatus.ok:
        break;
    }
    final lane = d.lanes.label;
    final road = d.limit?.unlimited == true
        ? '${d.roadName ?? 'Autobahn'} · Richtgeschw. 130'
        : (d.roadName ?? (d.limit == null ? 'Tempolimit unbekannt' : ''));
    return lane == null ? road : '$road\n$lane';
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({required this.d});
  final DriveController d;

  @override
  Widget build(BuildContext context) {
    final departure = d.showDepartureBanner;
    final cam = d.detector.controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: C.panel,
          border: Border.all(color: departure ? C.ok : C.line, width: departure ? 3 : 1),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(children: [
          Positioned.fill(child: TrafficView(
                objects: d.road,
                speedKmh: d.speedKmh,
                departure: departure,
                lanes: d.lanes,
                roads: d.roads,
                roadsAt: d.roadsAt,
              )),
          if (d.settings.showPreview && cam != null && cam.value.isInitialized)
            Positioned(
              left: 12,
              bottom: 12,
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(children: [
                  CameraPreview(cam),
                  Positioned.fill(child: CustomPaint(painter: _BoxPainter(d.road.map((r) => r.detection).toList()))),
                ]),
              ),
            ),
          if (_cameraHint() case final hint?)
            Positioned(
              left: 16,
              top: 16,
              right: 140,
              child: Text(hint, style: const TextStyle(color: C.dim, fontSize: 14)),
            ),
          if (departure)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(color: C.ok, borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.arrow_upward_rounded, color: Colors.black, size: 30),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text('Vorderfahrzeug fährt an',
                        style: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  String? _cameraHint() {
    if (d.demo || !d.settings.cameraEnabled) return null;
    return switch (d.detector.status) {
      CameraStatus.denied => 'Kamera-Zugriff erlauben, damit Fahrzeuge erkannt werden.',
      CameraStatus.error => 'Kamera-Fehler: ${d.detector.error ?? ''}',
      CameraStatus.starting => 'Kamera startet …',
      _ => null,
    };
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.dets);
  final List<Detection> dets;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = C.accent;
    for (final d in dets) {
      canvas.drawRect(Rect.fromLTRB(d.left * size.width, d.top * size.height, d.right * size.width, d.bottom * size.height), p);
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) => true;
}
