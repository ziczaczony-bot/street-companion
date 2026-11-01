import 'package:flutter/material.dart';

import '../core/link.dart';
import '../services/camera_link.dart';
import '../services/settings.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen'), backgroundColor: C.bg),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(children: [
          const _Header('Zwei Handys'),
          ListTile(
            title: const Text('Dieses Handy ist'),
            subtitle: Text(switch (s.role) {
              DeviceRole.single => 'Kamera und Anzeige auf einem Handy',
              DeviceRole.camera => 'An der Scheibe: erkennt Autos und sendet sie',
              DeviceRole.display => 'Zeigt alles an, Autos kommen vom Kamera-Handy',
            }),
            trailing: DropdownButton<DeviceRole>(
              value: s.role,
              items: const [
                DropdownMenuItem(value: DeviceRole.single, child: Text('Ein Handy')),
                DropdownMenuItem(value: DeviceRole.camera, child: Text('Kamera-Handy')),
                DropdownMenuItem(value: DeviceRole.display, child: Text('Anzeige-Handy')),
              ],
              onChanged: (v) => s.role = v ?? DeviceRole.single,
            ),
          ),
          if (s.role == DeviceRole.display)
            FutureBuilder<List<String>>(
              future: localAddresses(),
              builder: (context, snap) {
                final ips = snap.data ?? const [];
                return ListTile(
                  title: const Text('So verbinden'),
                  subtitle: Text('Hotspot an diesem Handy einschalten und das Kamera-Handy damit verbinden. '
                      'Das Kamera-Handy findet dieses Handy dann von selbst.\n'
                      'Adresse dieses Handys: ${ips.isEmpty ? '– (Hotspot oder WLAN einschalten)' : ips.join(', ')}'),
                );
              },
            ),
          if (s.role == DeviceRole.camera)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextFormField(
                initialValue: s.linkHost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Adresse des Anzeige-Handys (optional)',
                  helperText: 'Leer lassen = automatisch über den Hotspot. Nur ausfüllen, wenn es nicht klappt.',
                  helperMaxLines: 2,
                ),
                onChanged: (v) {
                  if (v.trim().isEmpty || isIpv4(v)) s.linkHost = v;
                },
              ),
            ),
          const _Header('Tempo'),
          ListTile(
            title: const Text('Warnen ab'),
            subtitle: Text('${s.toleranceKmh} km/h über dem Limit'),
            trailing: SizedBox(
              width: 180,
              child: Slider(
                value: s.toleranceKmh.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '+${s.toleranceKmh}',
                onChanged: (v) => s.toleranceKmh = v.round(),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Neues Tempolimit ansagen'),
            value: s.announceLimit,
            onChanged: (v) => s.announceLimit = v,
          ),
          const _Header('Hinweise'),
          SwitchListTile(
            title: const Text('Sprachansagen'),
            subtitle: const Text('Sonst nur Ton und Vibration'),
            value: s.voice,
            onChanged: (v) => s.voice = v,
          ),
          SwitchListTile(
            title: const Text('„Vorderfahrzeug fährt an“'),
            subtitle: const Text('Hinweis, wenn das Auto vor Ihnen losfährt und Sie noch stehen'),
            value: s.departureAlert,
            onChanged: (v) => s.departureAlert = v,
          ),
          const _Header('Kamera'),
          SwitchListTile(
            title: const Text('Fahrzeugerkennung mit Kamera'),
            subtitle: const Text('Läuft nur auf dem Handy, nichts wird gespeichert oder gesendet'),
            value: s.cameraEnabled,
            onChanged: (v) => s.cameraEnabled = v,
          ),
          SwitchListTile(
            title: const Text('Kamerabild klein anzeigen'),
            subtitle: const Text('Zum Ausrichten der Halterung'),
            value: s.showPreview,
            onChanged: (v) => s.showPreview = v,
          ),
          ListTile(
            title: const Text('Bilddrehung'),
            subtitle: const Text('Nur ändern, wenn Autos falsch erkannt werden'),
            trailing: DropdownButton<int>(
              value: s.cameraRotation,
              items: const [
                DropdownMenuItem(value: -1, child: Text('Automatisch')),
                DropdownMenuItem(value: 0, child: Text('0°')),
                DropdownMenuItem(value: 90, child: Text('90°')),
                DropdownMenuItem(value: 180, child: Text('180°')),
                DropdownMenuItem(value: 270, child: Text('270°')),
              ],
              onChanged: (v) => s.cameraRotation = v ?? -1,
            ),
          ),
          const _Header('Bildschirm'),
          SwitchListTile(
            title: const Text('Automatische Helligkeit'),
            subtitle: const Text('Nachts und im Tunnel dunkler, tagsüber hell'),
            value: s.autoBrightness,
            onChanged: (v) => s.autoBrightness = v,
          ),
          const _Header('Ausprobieren'),
          SwitchListTile(
            title: const Text('Demo-Modus'),
            subtitle: const Text('Simulierte Fahrt zum Testen zu Hause'),
            value: s.demoMode,
            onChanged: (v) => s.demoMode = v,
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Tempolimits: © OpenStreetMap-Mitwirkende (ODbL). Angaben ohne Gewähr – '
              'Verkehrszeichen vor Ort haben immer Vorrang.',
              style: TextStyle(color: C.dim, fontSize: 12),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text.toUpperCase(), style: const TextStyle(color: C.accent, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
      );
}
