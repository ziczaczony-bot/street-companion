import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/lanes.dart';
import '../core/vehicles.dart';

class FrameResult {
  const FrameResult({
    required this.detections,
    required this.luma,
    required this.camera,
    required this.inferenceMs,
    this.lanes = LaneObservation.empty,
  });
  final List<Detection> detections;
  final LaneObservation lanes;
  final double luma; // mean brightness 0..255
  final CameraModel camera;
  final int inferenceMs;
}

enum CameraStatus { off, starting, running, denied, error }

/// Runs the rear camera and an on-device object detector (COCO SSD
/// MobileNet, ~4 MB). Nothing leaves the phone and no video is stored.
class VehicleDetector {
  static const _input = 300;
  static const _minScore = 0.5;
  static const _minInterval = Duration(milliseconds: 180); // ~5 fps keeps the phone cool

  CameraController? controller;
  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  final _results = StreamController<FrameResult>.broadcast();
  CameraStatus status = CameraStatus.off;
  String? error;

  /// -1 = automatic, else forced rotation in degrees.
  int rotationOverride = -1;

  Stream<FrameResult> get results => _results.stream;

  Future<CameraStatus> start() async {
    status = CameraStatus.starting;
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      controller = c;
      _interpreter ??= await Interpreter.fromAsset('assets/models/detect.tflite', options: InterpreterOptions()..threads = 2);
      _isolate ??= await IsolateInterpreter.create(address: _interpreter!.address);
      await c.startImageStream(_onFrame);
      return status = CameraStatus.running;
    } on CameraException catch (e) {
      error = e.description ?? e.code;
      final denied = e.code.contains('ccess') || e.code.contains('ermission');
      return status = denied ? CameraStatus.denied : CameraStatus.error;
    } catch (e) {
      error = '$e';
      return status = CameraStatus.error;
    }
  }

  int _rotationFor(CameraController c) {
    if (rotationOverride >= 0) return rotationOverride;
    final sensor = c.description.sensorOrientation;
    final device = switch (c.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    // Frames arrive in the sensor's orientation (landscape on almost every
    // phone); turn them by the difference to how the phone is held.
    return (sensor - device + 360) % 360;
  }

  Future<void> _onFrame(CameraImage img) async {
    final now = DateTime.now();
    if (_busy || now.difference(_lastRun) < _minInterval) return;
    final c = controller;
    final isolate = _isolate;
    if (c == null || isolate == null) return;
    _busy = true;
    _lastRun = now;
    try {
      final rot = _rotationFor(c);
      final prep = prepareInput(img, rot, _input);
      final lanes = detectLanes(prep.gray, PreparedInput.grayW, PreparedInput.grayH);
      final boxes = [List.generate(10, (_) => List.filled(4, 0.0))];
      final classes = [List.filled(10, 0.0)];
      final scores = [List.filled(10, 0.0)];
      final count = [0.0];
      final sw = Stopwatch()..start();
      await isolate.runForMultipleInputs([prep.rgb], {0: boxes, 1: classes, 2: scores, 3: count});
      sw.stop();
      final dets = <Detection>[];
      final n = count[0].toInt().clamp(0, 10);
      for (var i = 0; i < n; i++) {
        if (scores[0][i] < _minScore) continue;
        // Model classes are 0-based without the "???" background entry.
        final kind = kindForCocoIndex(classes[0][i].toInt() + 1);
        if (kind == null) continue;
        final b = boxes[0][i];
        dets.add(Detection(
          kind: kind,
          score: scores[0][i],
          top: b[0].clamp(0.0, 1.0),
          left: b[1].clamp(0.0, 1.0),
          bottom: b[2].clamp(0.0, 1.0),
          right: b[3].clamp(0.0, 1.0),
        ));
      }
      final upright = (rot == 90 || rot == 270) ? img.height / img.width : img.width / img.height;
      _results.add(FrameResult(
          detections: dets, luma: prep.luma, camera: CameraModel(upright), inferenceMs: sw.elapsedMilliseconds, lanes: lanes));
    } catch (e) {
      error = '$e';
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    final c = controller;
    controller = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c?.dispose();
    status = CameraStatus.off;
  }

  Future<void> dispose() async {
    await stop();
    _isolate?.close();
    _interpreter?.close();
    _isolate = null;
    _interpreter = null;
  }
}

class PreparedInput {
  PreparedInput(this.rgb, this.luma, this.gray);
  final Uint8List rgb;
  final double luma;

  /// Small upright grayscale copy for lane detection.
  final Uint8List gray;
  static const grayW = 160, grayH = 120;
}

/// Scales a camera frame to size x size RGB, rotated upright by [rot]
/// degrees (clockwise), and measures the average brightness.
PreparedInput prepareInput(CameraImage img, int rot, int size) {
  final w = img.width, h = img.height;
  final out = Uint8List(size * size * 3);
  final yuv = img.planes.length >= 3;
  final p0 = img.planes[0];
  final y = p0.bytes;
  final yRow = p0.bytesPerRow;
  Uint8List? u, v;
  var uvRow = 0, uvPix = 1;
  if (yuv) {
    u = img.planes[1].bytes;
    v = img.planes[2].bytes;
    uvRow = img.planes[1].bytesPerRow;
    uvPix = img.planes[1].bytesPerPixel ?? 1;
  }
  var lumaSum = 0, lumaN = 0;
  var o = 0;
  for (var oy = 0; oy < size; oy++) {
    final vN = (oy + 0.5) / size;
    for (var ox = 0; ox < size; ox++) {
      final uN = (ox + 0.5) / size;
      final (sxN, syN) = _rotate(uN, vN, rot);
      final sx = (sxN * w).toInt().clamp(0, w - 1);
      final sy = (syN * h).toInt().clamp(0, h - 1);
      int r, g, b;
      if (yuv) {
        final yy = y[sy * yRow + sx];
        final uvi = (sy >> 1) * uvRow + (sx >> 1) * uvPix;
        final uu = (uvi < u!.length ? u[uvi] : 128) - 128;
        final vv = (uvi < v!.length ? v[uvi] : 128) - 128;
        r = (yy + 1.402 * vv).round().clamp(0, 255);
        g = (yy - 0.344 * uu - 0.714 * vv).round().clamp(0, 255);
        b = (yy + 1.772 * uu).round().clamp(0, 255);
        if ((ox & 7) == 0 && (oy & 7) == 0) {
          lumaSum += yy;
          lumaN++;
        }
      } else {
        // BGRA (iOS)
        final i = sy * yRow + sx * 4;
        b = y[i];
        g = y[i + 1];
        r = y[i + 2];
        if ((ox & 7) == 0 && (oy & 7) == 0) {
          lumaSum += (r * 299 + g * 587 + b * 114) ~/ 1000;
          lumaN++;
        }
      }
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
    }
  }
  // Grayscale copy for lane-marking detection.
  const gw = PreparedInput.grayW, gh = PreparedInput.grayH;
  final gray = Uint8List(gw * gh);
  var gi = 0;
  for (var oy = 0; oy < gh; oy++) {
    final vN = (oy + 0.5) / gh;
    for (var ox = 0; ox < gw; ox++) {
      final uN = (ox + 0.5) / gw;
      final (sxN, syN) = _rotate(uN, vN, rot);
      final sx = (sxN * w).toInt().clamp(0, w - 1);
      final sy = (syN * h).toInt().clamp(0, h - 1);
      if (yuv) {
        gray[gi++] = y[sy * yRow + sx];
      } else {
        final i = sy * yRow + sx * 4;
        gray[gi++] = (y[i + 2] * 299 + y[i + 1] * 587 + y[i] * 114) ~/ 1000;
      }
    }
  }
  return PreparedInput(out, lumaN == 0 ? 128 : lumaSum / lumaN, gray);
}

/// Maps upright normalised coordinates to sensor coordinates.
(double, double) _rotate(double uN, double vN, int rot) => switch (rot) {
      90 => (vN, 1 - uN),
      180 => (1 - uN, 1 - vN),
      270 => (1 - vN, uN),
      _ => (uN, vN),
    };
