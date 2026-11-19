/// Pure-Dart display timezone configuration. Candle data is always stored and
/// aggregated on epoch-aligned UTC boundaries; this only controls how times
/// are *displayed* on axes, crosshairs, and trade logs.
enum DisplayTimezone {
  local,
  utc,
  utcPlus8,
  utcPlus9,
  utcMinus5,
  utcMinus4,
  utcPlus1,
}

extension DisplayTimezoneX on DisplayTimezone {
  String get label {
    switch (this) {
      case DisplayTimezone.local:
        return 'Local';
      case DisplayTimezone.utc:
        return 'UTC';
      case DisplayTimezone.utcPlus8:
        return 'UTC+8';
      case DisplayTimezone.utcPlus9:
        return 'UTC+9';
      case DisplayTimezone.utcMinus5:
        return 'UTC-5';
      case DisplayTimezone.utcMinus4:
        return 'UTC-4';
      case DisplayTimezone.utcPlus1:
        return 'UTC+1';
    }
  }

  String get subtitle {
    switch (this) {
      case DisplayTimezone.local:
        return 'This device';
      case DisplayTimezone.utc:
        return 'Coordinated Universal Time';
      case DisplayTimezone.utcPlus8:
        return 'Hong Kong / Beijing / Singapore';
      case DisplayTimezone.utcPlus9:
        return 'Tokyo / Seoul';
      case DisplayTimezone.utcMinus5:
        return 'New York (EST)';
      case DisplayTimezone.utcMinus4:
        return 'New York (EDT)';
      case DisplayTimezone.utcPlus1:
        return 'London / Frankfurt';
    }
  }

  Duration get fixedOffset {
    switch (this) {
      case DisplayTimezone.local:
        return Duration.zero;
      case DisplayTimezone.utc:
        return Duration.zero;
      case DisplayTimezone.utcPlus8:
        return const Duration(hours: 8);
      case DisplayTimezone.utcPlus9:
        return const Duration(hours: 9);
      case DisplayTimezone.utcMinus5:
        return const Duration(hours: -5);
      case DisplayTimezone.utcMinus4:
        return const Duration(hours: -4);
      case DisplayTimezone.utcPlus1:
        return const Duration(hours: 1);
    }
  }

  Duration get effectiveOffset => this == DisplayTimezone.local
      ? DateTime.now().timeZoneOffset
      : fixedOffset;

  /// Converts a stored UTC instant to a UTC-flagged wall-clock [DateTime] whose
  /// `.hour` / `.day` / etc. reflect the chosen display timezone without OS
  /// local-timezone interference.
  DateTime toDisplayTime(DateTime utcTime) =>
      utcTime.toUtc().add(effectiveOffset);

  String get shortLabel => this == DisplayTimezone.local
      ? 'Local (${_formatOffset(effectiveOffset)})'
      : label;
}

String _formatOffset(Duration offset) {
  final int minutes = offset.inMinutes;
  if (minutes == 0) return 'UTC';
  final String sign = minutes < 0 ? '-' : '+';
  final int abs = minutes.abs();
  final int h = abs ~/ 60;
  final int m = abs % 60;
  final String mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return 'UTC$sign$h$mm';
}
