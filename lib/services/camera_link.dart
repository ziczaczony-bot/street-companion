import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/link.dart';
import 'vehicle_detector.dart';

/// IPv4 addresses of this phone on local networks (WiFi or hotspot).
Future<List<String>> localAddresses() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>[];
    for (final i in ifs) {
      for (final a in i.addresses) {
        final ip = a.address;
        final o = ip.split('.').map(int.tryParse).toList();
        if (o.length != 4 || o.contains(null)) continue;
        final private = o[0] == 10 || (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31) || (o[0] == 192 && o[1] == 168);
        if (private) out.add(ip);
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// Camera phone side: sends each detection result to the display phone.
class LinkSender {
  RawDatagramSocket? _sock;
  Timer? _resolveTimer;
  int _seq = 0;
  final _guesses = <InternetAddress>[];

  /// Address typed in the settings; empty = find the hotspot automatically.
  String manualHost = '';

  /// Display phone that answered last, and when.
  InternetAddress? peer;
  DateTime? _lastAck;
  int sent = 0;

  bool get connected => _lastAck != null && DateTime.now().difference(_lastAck!) < const Duration(seconds: 3);

  /// Where frames currently go (for the status screen).
  String get target {
    if (connected) return peer!.address;
    if (_guesses.isEmpty) return '–';
    return _guesses.map((a) => a.address).join(', ');
  }

  Future<void> start() async {
    if (_sock != null) return;
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    // iPhones may only broadcast with a special Apple permission, so they
    // rely on the hotspot address instead.
    s.broadcastEnabled = !Platform.isIOS;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      if (utf8.decode(d.data, allowMalformed: true) == linkAck) {
        peer = d.address;
        _lastAck = DateTime.now();
      }
    });
    _sock = s;
    await _resolve();
    _resolveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _resolve());
  }

  Future<void> _resolve() async {
    final list = <InternetAddress>[];
    final manual = manualHost.trim();
    if (isIpv4(manual)) {
      list.add(InternetAddress(manual));
    } else {
      for (final ip in await localAddresses()) {
        final host = hotspotHostFor(ip);
        if (host != null) list.add(InternetAddress(host));
      }
      if (!Platform.isIOS) list.add(InternetAddress('255.255.255.255'));
    }
    _guesses
      ..clear()
      ..addAll(list);
  }

  void send(FrameResult r) {
    final s = _sock;
    if (s == null) return;
    final bytes = utf8.encode(LinkFrame(
      seq: _seq++,
      detections: r.detections,
      lanes: r.lanes,
      luma: r.luma,
      aspect: r.camera.aspect,
      inferenceMs: r.inferenceMs,
    ).encode());
    // Once the display phone has answered, talk only to it.
    final targets = connected ? [peer!] : _guesses;
    for (final t in targets) {
      try {
        s.send(bytes, t, linkPort);
      } catch (_) {
        // Network not ready yet (hotspot just switching): try next frame.
      }
    }
    sent++;
  }

  Future<void> stop() async {
    _resolveTimer?.cancel();
    _resolveTimer = null;
    _sock?.close();
    _sock = null;
    _lastAck = null;
  }
}

/// Display phone side: receives results from the camera phone.
class LinkReceiver {
  RawDatagramSocket? _sock;
  final _frames = StreamController<LinkFrame>.broadcast();
  DateTime? lastAt;
  String? cameraAddress;
  int _lastSeq = -1;
  String? error;

  Stream<LinkFrame> get frames => _frames.stream;

  bool get connected => lastAt != null && DateTime.now().difference(lastAt!) < const Duration(seconds: 2);

  Future<bool> start() async {
    if (_sock != null) return true;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, linkPort, reuseAddress: true);
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        final f = LinkFrame.decode(utf8.decode(d.data, allowMalformed: true));
        if (f == null) return;
        try {
          s.send(utf8.encode(linkAck), d.address, d.port);
        } catch (_) {}
        // Same frame can arrive twice (hotspot address + broadcast).
        // A much smaller number means the camera app was restarted.
        if (f.seq <= _lastSeq && _lastSeq - f.seq < 50) return;
        _lastSeq = f.seq;
        lastAt = DateTime.now();
        cameraAddress = d.address.address;
        _frames.add(f);
      });
      _sock = s;
      error = null;
      return true;
    } catch (e) {
      error = '$e';
      debugPrint('LinkReceiver: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _sock?.close();
    _sock = null;
    lastAt = null;
    _lastSeq = -1;
  }
}
