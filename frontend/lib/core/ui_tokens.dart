import 'package:flutter/material.dart';

class UiTokens {
  static const Color accent = Color(0xFFFF7A18);
  static const Color success = Color(0xFF2FA56A);
  static const Color warning = Color(0xFFFF7A18);
  static const Color info = Color(0xFF3BA0F3);

  static const Color backgroundLight = Color(0xFFF6F8FB);
  static const Color foregroundLight = Color(0xFF131825);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFEEF1F5);
  static const Color mutedLight = Color(0xFF7A8292);
  static const Color borderLight = Color(0xFFE3E7EE);

  static const Color backgroundDark = Color(0xFF0F1116);
  static const Color foregroundDark = Color(0xFFE6E9F0);
  static const Color cardDark = Color(0xFF191C24);
  static const Color surfaceDark = Color(0xFF212633);
  static const Color mutedDark = Color(0xFF8A90A0);
  static const Color borderDark = Color(0xFF262B36);

  static Color background(BuildContext context) =>
      _isDark(context) ? backgroundDark : backgroundLight;
  static Color foreground(BuildContext context) =>
      _isDark(context) ? foregroundDark : foregroundLight;
  static Color card(BuildContext context) =>
      _isDark(context) ? cardDark : cardLight;
  static Color surface(BuildContext context) =>
      _isDark(context) ? surfaceDark : surfaceLight;
  static Color muted(BuildContext context) =>
      _isDark(context) ? mutedDark : mutedLight;
  static Color border(BuildContext context) =>
      _isDark(context) ? borderDark : borderLight;

  static List<BoxShadow> cardShadow(BuildContext context) {
    final color =
        _isDark(context) ? Colors.black.withOpacity(0.25) : Colors.black12;
    return [
      BoxShadow(
        color: color,
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];
  }

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
