// Renders dashboard screenshots in demo mode (not part of the normal tests).
// Run: flutter test tool/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:street_companion/services/demo.dart';
import 'package:street_companion/services/drive_controller.dart';
import 'package:street_companion/services/settings.dart';
import 'package:street_companion/ui/dashboard_screen.dart';
import 'package:street_companion/ui/theme.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  testWidgets('screenshots', (tester) async {
    const inter = '/usr/share/fonts/opentype/inter';
    await tester.runAsync(() async {
      await _font('Roboto', [for (final w in ['Light', 'Regular', 'SemiBold', 'Bold', 'ExtraBold']) '$inter/Inter-$w.otf']);
      await _font('MaterialIcons', ['${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/provider-6.1.5+1/extension/devtools/build/assets/fonts/MaterialIcons-Regular.otf']);
    });
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'demo': true, 'disclaimer': true});
    final settings = await Settings.load();
    final drive = DriveController(settings);
    final key = GlobalKey();

    Future<void> shot(String name, Size size, Duration at, {int waitMs = 2500}) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: DashboardScreen(drive: drive)),
      ));
      // Advance the scripted demo drive.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      DemoDrive.debugEpoch = DateTime.now().subtract(at);
      // Let real time pass (the demo follows the wall clock) while frames run.
      for (var i = 0; i < waitMs ~/ 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('docs').createSync();
        File('docs/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('dashboard_portrait', const Size(400, 860), const Duration(seconds: 10));
    await shot('dashboard_landscape', const Size(860, 400), const Duration(seconds: 52));
    await shot('overspeed', const Size(860, 400), const Duration(seconds: 19));
    await shot('departure', const Size(860, 400), const Duration(seconds: 41), waitMs: 5500);
    await tester.pumpWidget(const SizedBox());
    await drive.stop();
  });
}
