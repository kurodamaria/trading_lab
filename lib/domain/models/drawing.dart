import 'candle.dart';

class ChartAnchor {
  final DateTime time;
  final double price;

  const ChartAnchor({required this.time, required this.price});
}

class CrossTimeframePath {
  final String id;
  final List<ChartAnchor> points;

  CrossTimeframePath({required this.id, required this.points});
}

/// Finds the exact fractional (or integer) bar index for [targetTime] using
/// binary search on [candles]. If [targetTime] lies in the future empty space
/// past the last candle, the index is extrapolated linearly using
/// [barDuration] (falling back to the neighbor-candle step, then 5 minutes).
double resolveBarIndex(
  DateTime targetTime,
  List<Candle> candles, {
  Duration? barDuration,
}) {
  if (candles.isEmpty) return 0;
  if (candles.length == 1) {
    return (targetTime.millisecondsSinceEpoch -
            candles.first.time.millisecondsSinceEpoch) /
        const Duration(minutes: 5).inMilliseconds;
  }

  int lo = 0;
  int hi = candles.length - 1;

  // Past the last candle: extrapolate using the bar duration.
  if (!targetTime.isBefore(candles.last.time)) {
    final int barMs = barDuration?.inMilliseconds ??
        (candles.last.time.millisecondsSinceEpoch -
            candles[candles.length - 2].time.millisecondsSinceEpoch);
    if (barMs <= 0) return candles.length - 1.0;
    return (candles.length - 1) +
        (targetTime.millisecondsSinceEpoch -
                candles.last.time.millisecondsSinceEpoch) /
            barMs;
  }

  // Before the first candle.
  if (targetTime.isBefore(candles.first.time)) {
    final stepMs =
        candles[1].time.millisecondsSinceEpoch -
        candles.first.time.millisecondsSinceEpoch;
    if (stepMs <= 0) return 0;
    return (targetTime.millisecondsSinceEpoch -
            candles.first.time.millisecondsSinceEpoch) /
        stepMs;
  }

  while (hi - lo > 1) {
    final int mid = (lo + hi) >> 1;
    if (candles[mid].time.isBefore(targetTime)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }

  final stepMs =
      candles[hi].time.millisecondsSinceEpoch -
      candles[lo].time.millisecondsSinceEpoch;
  if (stepMs <= 0) return lo.toDouble();
  return lo +
      (targetTime.millisecondsSinceEpoch -
          candles[lo].time.millisecondsSinceEpoch) /
          stepMs;
}
