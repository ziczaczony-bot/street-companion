import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/drive_controller.dart';
import 'services/settings.dart';
import 'ui/dashboard_screen.dart';
import 'ui/disclaimer_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final settings = await Settings.load();
  runApp(StreetCompanionApp(settings: settings));
}

class StreetCompanionApp extends StatefulWidget {
  const StreetCompanionApp({super.key, required this.settings});
  final Settings settings;

  @override
  State<StreetCompanionApp> createState() => _StreetCompanionAppState();
}

class _StreetCompanionAppState extends State<StreetCompanionApp> {
  late final DriveController _drive = DriveController(widget.settings);

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Street Companion',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: widget.settings.acceptedDisclaimer
          ? DashboardScreen(drive: _drive)
          : DisclaimerScreen(onAccept: () => setState(() => widget.settings.acceptedDisclaimer = true)),
    );
  }
}
