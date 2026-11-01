import 'package:flutter/material.dart';

import 'theme.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key, required this.onAccept});
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              const Text('Street Companion', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: C.text)),
              const SizedBox(height: 16),
              const _Point(Icons.visibility, 'Nur eine Hilfe. Sie fahren selbst und achten immer auf Verkehr und Schilder. Tempolimits aus OpenStreetMap können fehlen oder veraltet sein.'),
              const _Point(Icons.do_not_touch, 'Während der Fahrt das Handy nicht bedienen (§ 23 Abs. 1a StVO). Alles vor der Abfahrt einstellen.'),
              const _Point(Icons.phone_android, 'Handy fest in einer Halterung, Kamera nach vorne, ohne die Sicht zu verdecken.'),
              const _Point(Icons.lock, 'Die Kamera wird nur auf dem Handy ausgewertet. Es wird nichts aufgenommen, gespeichert oder hochgeladen.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Verstanden', style: TextStyle(fontSize: 18)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: C.accent),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4, color: C.text))),
        ]),
      );
}
