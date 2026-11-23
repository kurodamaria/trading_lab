/// Pure-Dart indicator configuration model. No Flutter / dart:ui imports.
enum IndicatorType { ema, rsi }

const Object _unsetLabel = Object();

class IndicatorConfig {
  final String id;
  final IndicatorType type;

  /// Lookback period, clamped to `1..500`.
  final int period;

  /// ARGB colour value used for the overlay stroke.
  final int colorValue;
  final double strokeWidth;
  final bool visible;
  final String? customLabel;
  final double overbought;
  final double oversold;

  const IndicatorConfig({
    required this.id,
    required this.type,
    required this.period,
    required this.colorValue,
    this.strokeWidth = 1.3,
    this.visible = true,
    this.customLabel,
    this.overbought = 70.0,
    this.oversold = 30.0,
  });

  static const List<IndicatorConfig> defaults = <IndicatorConfig>[
    IndicatorConfig(
      id: 'ema-20',
      type: IndicatorType.ema,
      period: 20,
      colorValue: 0xFF1B4F72,
    ),
    IndicatorConfig(
      id: 'ema-50',
      type: IndicatorType.ema,
      period: 50,
      colorValue: 0xFFB75500,
    ),
  ];

  static List<IndicatorConfig> defaultIndicators() =>
      <IndicatorConfig>[...defaults];

  String get displayLabel {
    final String? custom = customLabel;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return type == IndicatorType.ema ? 'EMA $period' : 'RSI $period';
  }

  IndicatorConfig copyWith({
    String? id,
    IndicatorType? type,
    int? period,
    int? colorValue,
    double? strokeWidth,
    bool? visible,
    Object? customLabel = _unsetLabel,
    double? overbought,
    double? oversold,
  }) {
    return IndicatorConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      period: (period ?? this.period).clamp(1, 500).toInt(),
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      visible: visible ?? this.visible,
      customLabel: identical(customLabel, _unsetLabel)
          ? this.customLabel
          : customLabel as String?,
      overbought: overbought ?? this.overbought,
      oversold: oversold ?? this.oversold,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'period': period,
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'visible': visible,
        'customLabel': customLabel,
        'overbought': overbought,
        'oversold': oversold,
      };

  factory IndicatorConfig.fromJson(Map<String, dynamic> json) {
    final String typeName = (json['type'] as String?) ?? IndicatorType.ema.name;
    final IndicatorType type = IndicatorType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => IndicatorType.ema,
    );
    return IndicatorConfig(
      id: (json['id'] as String?) ?? 'indicator-${json['period'] ?? 20}',
      type: type,
      period: ((json['period'] as num?)?.toInt() ?? 20).clamp(1, 500).toInt(),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF1B4F72,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.3,
      visible: (json['visible'] as bool?) ?? true,
      customLabel: json['customLabel'] as String?,
      overbought: (json['overbought'] as num?)?.toDouble() ?? 70.0,
      oversold: (json['oversold'] as num?)?.toDouble() ?? 30.0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IndicatorConfig &&
        other.id == id &&
        other.type == type &&
        other.period == period &&
        other.colorValue == colorValue &&
        other.strokeWidth == strokeWidth &&
        other.visible == visible &&
        other.customLabel == customLabel &&
        other.overbought == overbought &&
        other.oversold == oversold;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        period,
        colorValue,
        strokeWidth,
        visible,
        customLabel,
        overbought,
        oversold,
      );
}
