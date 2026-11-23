import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/models/indicator.dart';

/// Curated high-contrast ink swatches for the nytNewsprint theme.
const List<int> _inkSwatches = <int>[
  0xFF1B4F72, // Navy
  0xFFB75500, // Burnt Sienna
  0xFF1B5E20, // Forest
  0xFF8E24AA, // Plum
  0xFFB71C1C, // Crimson
  0xFF222222, // Charcoal
  0xFF00695C, // Teal
  0xFF8D6E63, // Ochre
];

const List<double> _strokeWidths = <double>[1.0, 1.3, 1.8, 2.2];

Future<IndicatorConfig?> showIndicatorConfigDialog({
  required BuildContext context,
  required ChartTheme theme,
  IndicatorConfig? initial,
}) {
  return showDialog<IndicatorConfig>(
    context: context,
    builder: (_) => _IndicatorConfigDialog(theme: theme, initial: initial),
  );
}

class _IndicatorConfigDialog extends StatefulWidget {
  final ChartTheme theme;
  final IndicatorConfig? initial;

  const _IndicatorConfigDialog({required this.theme, this.initial});

  @override
  State<_IndicatorConfigDialog> createState() => _IndicatorConfigDialogState();
}

class _IndicatorConfigDialogState extends State<_IndicatorConfigDialog> {
  late IndicatorType _type;
  late final TextEditingController _period;
  late final TextEditingController _label;
  late final TextEditingController _overbought;
  late final TextEditingController _oversold;
  late int _colorValue;
  late double _strokeWidth;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final IndicatorConfig? initial = widget.initial;
    _type = initial?.type ?? IndicatorType.ema;
    _colorValue = initial?.colorValue ?? _inkSwatches.first;
    _strokeWidth = initial?.strokeWidth ?? 1.3;
    _period = TextEditingController(
      text: '${initial?.period ?? (_type == IndicatorType.rsi ? 14 : 20)}',
    );
    _label = TextEditingController(text: initial?.customLabel ?? '');
    _overbought =
        TextEditingController(text: '${initial?.overbought ?? 70.0}');
    _oversold = TextEditingController(text: '${initial?.oversold ?? 30.0}');
  }

  @override
  void dispose() {
    _period.dispose();
    _label.dispose();
    _overbought.dispose();
    _oversold.dispose();
    super.dispose();
  }

  int get _parsedPeriod =>
      (int.tryParse(_period.text.trim()) ?? 20).clamp(1, 500).toInt();

  void _submit() {
    final String label = _label.text.trim();
    final double overbought =
        (double.tryParse(_overbought.text.trim()) ?? 70.0).clamp(0.0, 100.0);
    final double oversold =
        (double.tryParse(_oversold.text.trim()) ?? 30.0).clamp(0.0, 100.0);
    Navigator.of(context).pop(
      IndicatorConfig(
        id: widget.initial?.id ??
            'ind-${DateTime.now().microsecondsSinceEpoch}',
        type: _type,
        period: _parsedPeriod,
        colorValue: _colorValue,
        strokeWidth: _strokeWidth,
        visible: widget.initial?.visible ?? true,
        customLabel: label.isEmpty ? null : label,
        overbought: overbought,
        oversold: oversold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return Dialog(
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: 440,
        decoration: BoxDecoration(
          color: t.background,
          border: Border.all(color: t.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.axisBackground,
                border: Border(bottom: BorderSide(color: t.border, width: 1)),
              ),
              child: Text(
                _isEditing ? 'EDIT INDICATOR' : 'ADD INDICATOR',
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel(t, 'TYPE'),
                  Row(
                    children: [
                      _typeChip(t, 'EMA', IndicatorType.ema),
                      const SizedBox(width: 6),
                      _typeChip(t, 'RSI', IndicatorType.rsi),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _fieldLabel(t, 'PERIOD (1–500)'),
                            _field(t, _period, TextInputType.number),
                          ],
                        ),
                      ),
                      if (_type == IndicatorType.rsi) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _fieldLabel(t, 'OVERBOUGHT'),
                              _field(t, _overbought, TextInputType.number),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _fieldLabel(t, 'OVERSOLD'),
                              _field(t, _oversold, TextInputType.number),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel(t, 'CUSTOM LABEL (OPTIONAL)'),
                  _field(t, _label, TextInputType.text,
                      hint: 'Auto (e.g. EMA 20)'),
                  const SizedBox(height: 12),
                  _fieldLabel(t, 'COLOR'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final int swatch in _inkSwatches)
                        _swatch(t, swatch),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel(t, 'STROKE WIDTH'),
                  Row(
                    children: [
                      for (final double width in _strokeWidths) ...[
                        _widthChip(t, width),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _button(t, 'Cancel',
                      onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  _button(t, _isEditing ? 'Save' : 'Add',
                      primary: true, onTap: _submit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(ChartTheme t, String label, IndicatorType type) {
    final bool active = _type == type;
    return GestureDetector(
      onTap: _isEditing
          ? null
          : () => setState(() {
                _type = type;
                if (_period.text.trim().isEmpty) {
                  _period.text = type == IndicatorType.rsi ? '14' : '20';
                }
              }),
      child: Opacity(
        opacity: _isEditing && !active ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? t.activePillBackground.withValues(alpha: 0.14)
                : t.background,
            border: Border.all(
              color: active ? t.activePillBackground : t.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _swatch(ChartTheme t, int value) {
    final bool active = _colorValue == value;
    return GestureDetector(
      onTap: () => setState(() => _colorValue = value),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Color(value),
          border: Border.all(
            color: active ? t.activePillBackground : t.border,
            width: active ? 2 : 1,
          ),
        ),
      ),
    );
  }

  Widget _widthChip(ChartTheme t, double width) {
    final bool active = (_strokeWidth - width).abs() < 0.001;
    return GestureDetector(
      onTap: () => setState(() => _strokeWidth = width),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? t.activePillBackground.withValues(alpha: 0.14)
              : t.background,
          border: Border.all(
            color: active ? t.activePillBackground : t.border,
            width: 1,
          ),
        ),
        child: Text(
          width.toStringAsFixed(1),
          style: TextStyle(
            color: t.textPrimary,
            fontFamily: t.fontFamily,
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(ChartTheme t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            color: t.textSecondary,
            fontFamily: t.fontFamily,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _field(
    ChartTheme t,
    TextEditingController controller,
    TextInputType keyboardType, {
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: t.textPrimary,
        fontFamily: t.fontFamily,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: t.textSecondary,
          fontFamily: t.fontFamily,
          fontSize: 12,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: t.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: t.activePillBackground, width: 1.5),
        ),
      ),
    );
  }

  Widget _button(
    ChartTheme t,
    String label, {
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? t.activePillText : t.textPrimary,
        backgroundColor: primary ? t.activePillBackground : t.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: primary ? BorderSide.none : BorderSide(color: t.border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: t.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
