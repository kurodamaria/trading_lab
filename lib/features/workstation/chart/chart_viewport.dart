import 'dart:math' as math;

import '../../../domain/models/candle.dart';

class ChartViewport {
  double startIndex;
  double endIndex;
  double minPrice;
  double maxPrice;
  bool autoScaleY;

  ChartViewport({
    required this.startIndex,
    required this.endIndex,
    required this.minPrice,
    required this.maxPrice,
    this.autoScaleY = true,
  });

  double get visibleBarCount => endIndex - startIndex;
  double get priceRange => maxPrice - minPrice;

  // World -> Screen (uses main chart area width/height, excluding axes)
  double indexToX(double index, double chartWidth) {
    if (visibleBarCount <= 0) return 0;
    return ((index - startIndex + 0.5) / visibleBarCount) * chartWidth;
  }

  double priceToY(double price, double chartHeight) {
    if (priceRange <= 0) return chartHeight / 2;
    final ratio = (price - minPrice) / priceRange;
    return chartHeight * (1.0 - ratio);
  }

  // Screen -> World
  double xToIndex(double x, double chartWidth) {
    return startIndex + (x / chartWidth) * visibleBarCount - 0.5;
  }

  double yToPrice(double y, double chartHeight) {
    final ratio = 1.0 - (y / chartHeight);
    return minPrice + ratio * priceRange;
  }

  void fitPriceToVisible(List<Candle> candles) {
    if (!autoScaleY || candles.isEmpty) return;

    final int first = math.max(0, startIndex.floor());
    final int last = math.min(candles.length - 1, endIndex.ceil());
    if (first > last) return;

    double low = candles[first].low;
    double high = candles[first].high;

    for (int i = first; i <= last; i++) {
      if (candles[i].low < low) low = candles[i].low;
      if (candles[i].high > high) high = candles[i].high;
    }

    final span = math.max(high - low, 0.0001);
    minPrice = low - span * 0.08;
    maxPrice = high + span * 0.08;
  }
}
