import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/models/display_timezone.dart';

/// Settings panel: compact desktop/tablet display-timezone selector with an
/// inline live clock. Candle aggregation always stays anchored to `00:00 UTC`;
/// only display formatting changes.
class SettingsPage extends StatefulWidget {
  final ChartTheme theme;
  final DisplayTimezone selected;
  final ValueChanged<DisplayTimezone> onChanged;
  final String? customFontFamily;
  final double fontScale;
  final ValueChanged<String?>? onFontFamilyChanged;
  final ValueChanged<double>? onFontScaleChanged;

  const SettingsPage({
    super.key,
    required this.theme,
    required this.selected,
    required this.onChanged,
    this.customFontFamily,
    this.fontScale = 1.0,
    this.onFontFamilyChanged,
    this.onFontScaleChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<String> _fontPresets = <String>[
    'Default',
    'Times New Roman',
    'Georgia',
    'Segoe UI',
    'JetBrains Mono',
    'Consolas',
  ];
  static const List<double> _scaleSteps = <double>[
    0.85,
    0.95,
    1.00,
    1.10,
    1.20,
    1.30,
  ];

  Timer? _clock;
  DateTime _now = DateTime.now();
  late final TextEditingController _fontController;

  @override
  void initState() {
    super.initState();
    _fontController =
        TextEditingController(text: widget.customFontFamily ?? '');
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String next = widget.customFontFamily ?? '';
    if (_fontController.text != next &&
        !_fontController.selection.isValid) {
      _fontController.text = next;
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _fontController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return Container(
      color: t.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeader(t),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeader(t),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool twoCols = constraints.maxWidth >= 460;
                          return _grid(t, twoCols);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Candle aggregation remains anchored to 00:00 UTC '
                        '(Binance / exchange standard).',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontFamily: t.fontFamily,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _typographySection(t),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageHeader(ChartTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SETTINGS',
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Time & Session Display',
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ChartTheme t) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Row(
        children: [
          Text(
            'DISPLAY TIMEZONE',
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          Text(
            '${_clockText(widget.selected.toDisplayTime(_now.toUtc()))}'
            ' · ${widget.selected.label}',
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(ChartTheme t, bool twoCols) {
    final List<DisplayTimezone> tzs = DisplayTimezone.values;
    final int columns = twoCols ? 2 : 1;
    final int rows = (tzs.length / columns).ceil();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: t.border, width: 1),
          top: BorderSide(color: t.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          for (int r = 0; r < rows; r++)
            Row(
              children: [
                for (int c = 0; c < columns; c++)
                  Expanded(
                    child: _cell(
                      t,
                      (r * columns + c) < tzs.length
                          ? tzs[r * columns + c]
                          : null,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(ChartTheme t, DisplayTimezone? tz) {
    if (tz == null) {
      return Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: t.border, width: 1),
            bottom: BorderSide(color: t.border, width: 1),
          ),
        ),
      );
    }
    final bool active = tz == widget.selected;
    return _TimezoneCell(
      theme: t,
      timezone: tz,
      active: active,
      onTap: () => widget.onChanged(tz),
    );
  }

  Widget _typographySection(ChartTheme t) {
    final String? custom = widget.customFontFamily;
    final String normalized = (custom ?? '').trim();
    final bool isDefault = normalized.isEmpty;
    final String previewFamily = isDefault ? (t.fontFamily ?? '') : normalized;
    final double scale = widget.fontScale.clamp(
      ChartTheme.minFontScale,
      ChartTheme.maxFontScale,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.axisBackground,
            border: Border.all(color: t.border, width: 1),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            'TYPOGRAPHY',
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.border, width: 1),
              right: BorderSide(color: t.border, width: 1),
              bottom: BorderSide(color: t.border, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(t, 'FONT FAMILY'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final String preset in _fontPresets)
                    _fontChip(t, preset, isDefault, normalized),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fontController,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontFamily: t.fontFamily,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Type any installed font name',
                        hintStyle: TextStyle(
                          color: t.textSecondary,
                          fontFamily: t.fontFamily,
                          fontSize: 12,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(color: t.border, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: t.activePillBackground,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (value) =>
                          widget.onFontFamilyChanged?.call(value),
                      onSubmitted: (value) =>
                          widget.onFontFamilyChanged?.call(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _smallButton(
                    t,
                    'Reset',
                    onTap: () {
                      _fontController.clear();
                      widget.onFontFamilyChanged?.call(null);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label(t, 'FONT SIZE / SCALE'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final double step in _scaleSteps)
                    _scaleChip(t, step, scale),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: t.background,
                  border: Border.all(color: t.border, width: 1),
                ),
                child: Text(
                  'AaBbCc 012345.67 · +1.50R',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontFamily:
                        previewFamily.isEmpty ? t.fontFamily : previewFamily,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(ChartTheme t, String text) => Text(
        text,
        style: TextStyle(
          color: t.textSecondary,
          fontFamily: t.fontFamily,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      );

  Widget _fontChip(
    ChartTheme t,
    String preset,
    bool isDefault,
    String current,
  ) {
    final bool active = preset == 'Default'
        ? isDefault
        : current.toLowerCase() == preset.toLowerCase();
    return _chip(t, preset, active, () {
      if (preset == 'Default') {
        _fontController.clear();
        widget.onFontFamilyChanged?.call(null);
      } else {
        _fontController.text = preset;
        widget.onFontFamilyChanged?.call(preset);
      }
    });
  }

  Widget _scaleChip(ChartTheme t, double step, double activeScale) {
    final bool active = (step - activeScale).abs() < 0.001;
    return _chip(
      t,
      '${(step * 100).round()}%',
      active,
      () => widget.onFontScaleChanged?.call(step),
    );
  }

  Widget _chip(
    ChartTheme t,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
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
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
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

  Widget _smallButton(
    ChartTheme t,
    String label, {
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: t.textPrimary,
        backgroundColor: t.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: BorderSide(color: t.border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: t.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static String _clockText(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }
}

class _TimezoneCell extends StatefulWidget {
  final ChartTheme theme;
  final DisplayTimezone timezone;
  final bool active;
  final VoidCallback onTap;

  const _TimezoneCell({
    required this.theme,
    required this.timezone,
    required this.active,
    required this.onTap,
  });

  @override
  State<_TimezoneCell> createState() => _TimezoneCellState();
}

class _TimezoneCellState extends State<_TimezoneCell> {
  bool _isHovered = false;

  static String _subtitleOf(DisplayTimezone tz) {
    switch (tz) {
      case DisplayTimezone.local:
        return 'Device';
      case DisplayTimezone.utc:
        return 'Exchange';
      case DisplayTimezone.utcPlus8:
        return 'HK / BJ / SG';
      case DisplayTimezone.utcPlus9:
        return 'Tokyo';
      case DisplayTimezone.utcMinus5:
        return 'NY EST';
      case DisplayTimezone.utcMinus4:
        return 'NY EDT';
      case DisplayTimezone.utcPlus1:
        return 'London';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final bool active = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? t.activePillBackground.withValues(alpha: 0.14)
                : (_isHovered
                    ? t.activePillBackground.withValues(alpha: 0.06)
                    : Colors.transparent),
            border: Border(
              right: BorderSide(color: t.border, width: 1),
              bottom: BorderSide(color: t.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                widget.timezone.label,
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '· ${_subtitleOf(widget.timezone)}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontFamily: t.fontFamily,
                    fontSize: 11,
                  ),
                ),
              ),
              if (active)
                Icon(Icons.check, size: 16, color: t.activePillBackground),
            ],
          ),
        ),
      ),
    );
  }
}
