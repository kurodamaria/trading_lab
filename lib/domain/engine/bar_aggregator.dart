import '../models/candle.dart';
import '../models/timeframe.dart';

/// Pure-Dart aggregation engine: builds higher-timeframe candles from a
/// base 1-minute series. No Flutter imports allowed.
class BarAggregator {
  static List<Candle> aggregate(List<Candle> base1mCandles, Timeframe tf) {
    if (base1mCandles.isEmpty) return [];
    if (tf == Timeframe.m1) return base1mCandles;

    final int bucketMs = tf.duration.inMilliseconds;

    final List<Candle> out = <Candle>[];
    int currentKey = -9223372036854775807;
    double open = 0, high = 0, low = 0, close = 0, volSum = 0.0;
    bool bucketOpen = false;

    void flush() {
      if (!bucketOpen) return;
      out.add(
        Candle(
          index: out.length,
          time: DateTime.fromMillisecondsSinceEpoch(
            currentKey * bucketMs,
            isUtc: true,
          ),
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volSum,
        ),
      );
      bucketOpen = false;
    }

    for (final c in base1mCandles) {
      final int key = c.time.toUtc().millisecondsSinceEpoch ~/ bucketMs;
      if (key != currentKey) {
        flush();
        currentKey = key;
        open = c.open;
        high = c.high;
        low = c.low;
        close = c.close;
        volSum = c.volume;
        bucketOpen = true;
      } else {
        if (c.high > high) high = c.high;
        if (c.low < low) low = c.low;
        close = c.close;
        volSum += c.volume;
      }
    }
    flush();
    return out;
  }

  /// EMA series with `k = 2.0 / (period + 1)`. Indices `< period - 1` are
  /// `null`; the first valid value is the SMA of the first `period` closes.
  static List<double?> computeEma(List<Candle> candles, int period) {
    final int n = candles.length;
    final List<double?> ema = List<double?>.filled(n, null);
    if (period <= 0 || n < period) return ema;

    final double k = 2.0 / (period + 1);

    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += candles[i].close;
    }
    double prev = sum / period;
    ema[period - 1] = prev;

    for (int i = period; i < n; i++) {
      prev = candles[i].close * k + prev * (1.0 - k);
      ema[i] = prev;
    }
    return ema;
  }

  /// Wilder-smoothed RSI. Values before index [period] are `null`; `avgLoss`
  /// of zero yields `100.0` and the result is clamped to `0..100`.
  static List<double?> computeRsi(List<Candle> candles, int period) {
    final int n = candles.length;
    final List<double?> rsi = List<double?>.filled(n, null);
    if (period < 1 || n <= period) return rsi;

    double gainSum = 0.0;
    double lossSum = 0.0;
    for (int i = 1; i <= period; i++) {
      final double delta = candles[i].close - candles[i - 1].close;
      if (delta >= 0) {
        gainSum += delta;
      } else {
        lossSum -= delta;
      }
    }
    double avgGain = gainSum / period;
    double avgLoss = lossSum / period;
    rsi[period] = _rsiValue(avgGain, avgLoss);

    for (int i = period + 1; i < n; i++) {
      final double delta = candles[i].close - candles[i - 1].close;
      final double gain = delta > 0 ? delta : 0.0;
      final double loss = delta < 0 ? -delta : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
      rsi[i] = _rsiValue(avgGain, avgLoss);
    }
    return rsi;
  }

  static double _rsiValue(double avgGain, double avgLoss) {
    if (avgLoss == 0.0) return 100.0;
    final double rs = avgGain / avgLoss;
    final double value = 100.0 - 100.0 / (1.0 + rs);
    return value.clamp(0.0, 100.0).toDouble();
  }
}
