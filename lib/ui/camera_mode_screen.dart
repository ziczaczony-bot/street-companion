import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/link.dart';
import '../core/vehicles.dart';
import '../services/camera_link.dart';
import '../services/settings.dart';
import '../services/vehicle_detector.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// Camera phone in two-phone mode: runs the camera and detection and
/// sends the results to the display phone. The screen goes dark after a
/// few seconds to keep the phone cool; tap to wake it.
class CameraModeScreen extends StatefulWidget {
  const CameraModeScreen({super.key, required this.settings});
  final Settings settings;

  @override
  State<CameraModeScreen> createState() => _CameraModeScreenState();
}

class _CameraModeScreenState extends State<CameraModeScreen> with WidgetsBindingObserver {
  static const _awakeFor = Duration(seconds: 20);

  final _detector = VehicleDetector();
  final _sender = LinkSender();
  StreamSubscription<FrameResult>? _sub;
  Timer? _tick;
  bool _running = false;
  DateTime _wokeAt = DateTime.now();
  bool _dim = false;
  List<Detection> _last = const [];
  int _framesThisSecond = 0;
  int _fps = 0;
  int _inferenceMs = 0;
  List<String> _ownIps = const [];

  bool get _awake => DateTime.now().difference(_wokeAt) < _awakeFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    _sender.manualHost = widget.settings.linkHost;
    await _sender.start();
    _detector.rotationOverride = widget.settings.cameraRotation;
    await _detector.start();
    _sub = _detector.results.listen((r) {
      _sender.send(r);
      _last = r.detections;
      _inferenceMs = r.inferenceMs;
      _framesThisSecond++;
    });
    _wake();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      _fps = _framesThisSecond;
      _framesThisSecond = 0;
      _ownIps = await localAddresses();
      if (!_awake && !_dim) {
        _dim = true;
        try {
          await ScreenBrightness.instance.setApplicationScreenBrightness(0.02);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    if (!_running) return;
    _running = false;
    _tick?.cancel();
    await _sub?.cancel();
    await _detector.stop();
    await _sender.stop();
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
      await WakelockPlus.disable();
    } catch (_) {}
  }

  void _wake() {
    _wokeAt = DateTime.now();
    if (_dim) {
      _dim = false;
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _stop();
    if (state == AppLifecycleState.resumed) _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop().then((_) => _detector.dispose());
    super.dispose();
  }

  Future<void> _openSettings() async {
    await _stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(settings: widget.settings)));
    if (!mounted || widget.settings.role != DeviceRole.camera) return;
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    final awake = _awake;
    final cam = _detector.controller;
    final connected = _sender.connected;
    final camOk = _detector.status == CameraStatus.running;
    final String headline;
    final String detail;
    if (!camOk) {
      headline = switch (_detector.status) {
        CameraStatus.denied => 'Kamera-Zugriff erlauben',
        CameraStatus.error => 'Kamera-Fehler',
        _ => 'Kamera startet …',
      };
      detail = _detector.error ?? '';
    } else if (connected) {
      headline = 'Verbunden';
      detail = 'Sendet an ${_sender.target} · $_fps Bilder/s · $_inferenceMs ms';
    } else {
      headline = 'Suche Anzeige-Handy …';
      detail = 'Am Anzeige-Handy den Hotspot einschalten und dieses Handy damit verbinden. '
          'Am Anzeige-Handy in den Einstellungen „Anzeige-Handy“ wählen.\n'
          'Dieses Handy: ${_ownIps.isEmpty ? 'kein WLAN' : _ownIps.join(', ')} · versucht ${_sender.target}';
    }
    final color = !camOk ? C.danger : (connected ? C.ok : C.warn);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _wake,
        child: SafeArea(
          child: !awake
              // Dark screen: only a small dot so you can see it is working.
              ? Center(child: Icon(Icons.circle, size: 14, color: color.withValues(alpha: 0.6)))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Icon(Icons.videocam, color: C.accent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Kamera-Handy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings, color: C.dim),
                        tooltip: 'Einstellungen',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.circle, size: 14, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(headline, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(detail, style: const TextStyle(color: C.dim, fontSize: 14)),
                    const SizedBox(height: 16),
                    if (cam != null && cam.value.isInitialized)
                      Expanded(
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(children: [
                              CameraPreview(cam),
                              Positioned.fill(child: CustomPaint(painter: _Boxes(_last))),
                            ]),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(height: 8),
                    const Text(
                      'Kamera so ausrichten, dass die Straße gut zu sehen ist. '
                      'Der Bildschirm wird nach 20 Sekunden dunkel – antippen zum Aufwecken.',
                      style: TextStyle(color: C.dim, fontSize: 12),
                    ),
                  ]),
                ),
        ),
      ),
    );
  }
}

class _Boxes extends CustomPainter {
  _Boxes(this.dets);
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
  bool shouldRepaint(_Boxes old) => true;
}
