import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF080B10);
  static const panel = Color(0xFF111720);
  static const line = Color(0xFF1E2733);
  static const text = Color(0xFFEAF0F6);
  static const dim = Color(0xFF7D8A99);
  static const accent = Color(0xFF3DD6F5);
  static const ok = Color(0xFF36D27A);
  static const warn = Color(0xFFFFB020);
  static const danger = Color(0xFFFF3B3B);
  static const signRed = Color(0xFFD7141A);
}

ThemeData buildTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: C.bg,
      colorScheme: const ColorScheme.dark(primary: C.accent, surface: C.panel),
      useMaterial3: true,
    );
