import 'package:flutter/material.dart';

/// Palette matched to customer tactical references (muted olive-lime, dense dark UI).
abstract final class AppColors {
  static const Color background = Color(0xFF0A0B0D);
  static const Color surface = Color(0xFF121418);
  static const Color surfaceElevated = Color(0xFF181B20);
  static const Color card = Color(0xFF15181D);
  static const Color cardSoft = Color(0xFF1A1E24);
  static const Color border = Color(0xFF2C3138);
  static const Color borderSubtle = Color(0xFF23272E);

  /// Muted tactical lime (not neon).
  static const Color accent = Color(0xFFA4C639);
  static const Color accentDim = Color(0xFF7A9A2A);
  static const Color accentMuted = Color(0x2EA4C639);
  static const Color accentSoft = Color(0xFF2A3218);

  static const Color textPrimary = Color(0xFFECEDEF);
  static const Color textSecondary = Color(0xFF9A9FA6);
  static const Color textTertiary = Color(0xFF6E747C);

  static const Color danger = Color(0xFFE25B5B);
  static const Color dangerMuted = Color(0x28E25B5B);
  static const Color warning = Color(0xFFD4A017);
  static const Color roleAdmin = Color(0xFFE25B5B);
  static const Color roleModerator = Color(0xFFC9A227);
  static const Color roleOrganizer = Color(0xFFA4C639);
  static const Color roleSherpa = Color(0xFF6BB3B0);
  static const Color roleUser = Color(0xFF4B8BDB);
  static const Color gold = Color(0xFFC9A227);
  static const Color silver = Color(0xFFA8ADB4);
  static const Color bronze = Color(0xFFB07A3A);

  static const Color navInactive = Color(0xFF8A9098);
  static const Color scrim = Color(0xCC0A0B0D);
}

abstract final class AppRadii {
  static const double card = 14;
  static const double button = 12;
  static const double input = 12;
  static const double chip = 10;
  static const double badge = 8;
}

abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}
