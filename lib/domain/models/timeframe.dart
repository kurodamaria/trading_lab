/// Pure-Dart timeframe definitions. No Flutter imports allowed.
enum Timeframe {
  m1,
  m3,
  m5,
  m15,
  m30,
  h1,
  h4,
  d1,
}

extension TimeframeX on Timeframe {
  String get label {
    switch (this) {
      case Timeframe.m1:
        return '1m';
      case Timeframe.m3:
        return '3m';
      case Timeframe.m5:
        return '5m';
      case Timeframe.m15:
        return '15m';
      case Timeframe.m30:
        return '30m';
      case Timeframe.h1:
        return '1h';
      case Timeframe.h4:
        return '4h';
      case Timeframe.d1:
        return '1d';
    }
  }

  Duration get duration {
    switch (this) {
      case Timeframe.m1:
        return const Duration(minutes: 1);
      case Timeframe.m3:
        return const Duration(minutes: 3);
      case Timeframe.m5:
        return const Duration(minutes: 5);
      case Timeframe.m15:
        return const Duration(minutes: 15);
      case Timeframe.m30:
        return const Duration(minutes: 30);
      case Timeframe.h1:
        return const Duration(hours: 1);
      case Timeframe.h4:
        return const Duration(hours: 4);
      case Timeframe.d1:
        return const Duration(hours: 24);
    }
  }

  int get minutes {
    switch (this) {
      case Timeframe.m1:
        return 1;
      case Timeframe.m3:
        return 3;
      case Timeframe.m5:
        return 5;
      case Timeframe.m15:
        return 15;
      case Timeframe.m30:
        return 30;
      case Timeframe.h1:
        return 60;
      case Timeframe.h4:
        return 240;
      case Timeframe.d1:
        return 1440;
    }
  }
}
