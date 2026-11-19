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

  const SettingsPage({
    super.key,
    required this.theme,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
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
