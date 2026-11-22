import 'package:flutter/material.dart';

const Object _unsetFontFamily = Object();

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

  /// Effective font family. `null` means the platform/theme default.
  final String? fontFamily;

  /// Typography scale applied to chart text and the app-level text theme.
  final double fontScale;

  static const double minFontScale = 0.85;
  static const double maxFontScale = 1.30;

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
    this.fontFamily,
    this.fontScale = 1.0,
  });

  /// Clamped effective scale used for every rendered text size.
  double get effectiveFontScale =>
      fontScale.clamp(minFontScale, maxFontScale).toDouble();

  /// Scales a base font size by the (clamped) typography scale.
  double scaledFontSize(double baseSize) => baseSize * effectiveFontScale;

  ChartTheme copyWith({
    Color? background,
    Color? axisBackground,
    Color? axisActiveBackground,
    Color? gridLine,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? bullBody,
    Color? bullBorder,
    Color? bearBody,
    Color? bearBorder,
    bool? hollowBull,
    Color? crosshair,
    Color? badgeBackground,
    Color? badgeText,
    Color? pendingBuyBackground,
    Color? pendingBuyText,
    Color? pendingSellBackground,
    Color? pendingSellText,
    Color? activePillBackground,
    Color? activePillText,
    Color? pathColor,
    Object? fontFamily = _unsetFontFamily,
    double? fontScale,
  }) {
    return ChartTheme(
      background: background ?? this.background,
      axisBackground: axisBackground ?? this.axisBackground,
      axisActiveBackground: axisActiveBackground ?? this.axisActiveBackground,
      gridLine: gridLine ?? this.gridLine,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      bullBody: bullBody ?? this.bullBody,
      bullBorder: bullBorder ?? this.bullBorder,
      bearBody: bearBody ?? this.bearBody,
      bearBorder: bearBorder ?? this.bearBorder,
      hollowBull: hollowBull ?? this.hollowBull,
      crosshair: crosshair ?? this.crosshair,
      badgeBackground: badgeBackground ?? this.badgeBackground,
      badgeText: badgeText ?? this.badgeText,
      pendingBuyBackground:
          pendingBuyBackground ?? this.pendingBuyBackground,
      pendingBuyText: pendingBuyText ?? this.pendingBuyText,
      pendingSellBackground:
          pendingSellBackground ?? this.pendingSellBackground,
      pendingSellText: pendingSellText ?? this.pendingSellText,
      activePillBackground:
          activePillBackground ?? this.activePillBackground,
      activePillText: activePillText ?? this.activePillText,
      pathColor: pathColor ?? this.pathColor,
      fontFamily: identical(fontFamily, _unsetFontFamily)
          ? this.fontFamily
          : fontFamily as String?,
      fontScale: (fontScale ?? this.fontScale)
          .clamp(minFontScale, maxFontScale)
          .toDouble(),
    );
  }

  /// Builds the app-level [ThemeData] for this chart theme. Font families are
  /// applied here, but font sizes are intentionally left untouched — global
  /// scaling is handled once by `MediaQuery.textScaler` at the app root, which
  /// prevents double-scaling of widget text.
  ThemeData buildThemeData() {
    final ThemeData base = ThemeData.light(useMaterial3: false);
    final TextTheme tt = base.textTheme;
    TextStyle? withFamily(TextStyle? style) =>
        style?.copyWith(fontFamily: fontFamily);
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: false,
      scaffoldBackgroundColor: background,
      fontFamily: fontFamily,
      textTheme: tt.copyWith(
        displayLarge: withFamily(tt.displayLarge),
        displayMedium: withFamily(tt.displayMedium),
        displaySmall: withFamily(tt.displaySmall),
        headlineLarge: withFamily(tt.headlineLarge),
        headlineMedium: withFamily(tt.headlineMedium),
        headlineSmall: withFamily(tt.headlineSmall),
        titleLarge: withFamily(tt.titleLarge),
        titleMedium: withFamily(tt.titleMedium),
        titleSmall: withFamily(tt.titleSmall),
        bodyLarge: withFamily(tt.bodyLarge),
        bodyMedium: withFamily(tt.bodyMedium),
        bodySmall: withFamily(tt.bodySmall),
        labelLarge: withFamily(tt.labelLarge),
        labelMedium: withFamily(tt.labelMedium),
        labelSmall: withFamily(tt.labelSmall),
      ),
    );
  }

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
