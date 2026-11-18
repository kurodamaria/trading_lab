import 'package:flutter/material.dart';

class ChartTheme {
  final Color background;
  final Color axisBackground;
  final Color axisActiveBackground;
  final Color gridLine;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color bullBody;
  final Color bullBorder;
  final Color bearBody;
  final Color bearBorder;
  final bool hollowBull;
  final Color crosshair;
  final Color badgeBackground;
  final Color badgeText;
  final Color pendingBuyBackground;
  final Color pendingBuyText;
  final Color pendingSellBackground;
  final Color pendingSellText;
  final Color activePillBackground;
  final Color activePillText;
  final Color pathColor;
  final String fontFamily;

  const ChartTheme({
    required this.background,
    required this.axisBackground,
    required this.axisActiveBackground,
    required this.gridLine,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.bullBody,
    required this.bullBorder,
    required this.bearBody,
    required this.bearBorder,
    required this.hollowBull,
    required this.crosshair,
    required this.badgeBackground,
    required this.badgeText,
    required this.pendingBuyBackground,
    required this.pendingBuyText,
    required this.pendingSellBackground,
    required this.pendingSellText,
    required this.activePillBackground,
    required this.activePillText,
    required this.pathColor,
    required this.fontFamily,
  });

  static const ChartTheme nytNewsprint = ChartTheme(
    background: Color(0xFFF7F5F0),
    axisBackground: Color(0xFFEDEAE2),
    axisActiveBackground: Color(0xFFE2DDD2),
    gridLine: Color(0xFFE5E0D5),
    border: Color(0xFF222222),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF555555),
    bullBody: Color(0xFFF7F5F0),
    bullBorder: Color(0xFF111111),
    bearBody: Color(0xFF111111),
    bearBorder: Color(0xFF111111),
    hollowBull: true,
    crosshair: Color(0xFF444444),
    badgeBackground: Color(0xFF111111),
    badgeText: Color(0xFFF7F5F0),
    pendingBuyBackground: Color(0xFF1B5E20),
    pendingBuyText: Color(0xFFFFFFFF),
    pendingSellBackground: Color(0xFFB71C1C),
    pendingSellText: Color(0xFFFFFFFF),
    activePillBackground: Color(0xFFC96442),
    activePillText: Color(0xFFFFFFFF),
    pathColor: Color(0xFF1B4F72),
    fontFamily: 'Georgia',
  );
}
