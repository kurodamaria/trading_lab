import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/models/candle.dart';
import '../../../domain/models/display_timezone.dart';
import '../../../domain/models/drawing.dart';
import '../../../domain/models/indicator.dart';
import '../../../domain/models/order.dart';
import 'chart_viewport.dart';

// Helper: keeps time grid density readable regardless of zoom level
int computeTimeStep(double visibleBars) {
  if (visibleBars <= 25) return 5;
  if (visibleBars <= 60) return 10;
  if (visibleBars <= 140) return 20;
  if (visibleBars <= 300) return 50;
  return 100;
}

const double _minTickSpacingPx = 88.0;
const List<String> _monthAbbr = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

class _TimeTick {
  final double x;
  final String label;
  final bool major;

  const _TimeTick({required this.x, required this.label, required this.major});
}

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _dayLabel(DateTime t) => '${_monthAbbr[t.month - 1]} ${t.day}';

/// Effective bar spacing, falling back to the neighbour delta and finally to
/// one minute so extrapolation never divides by zero.
Duration _effectiveBarDuration(List<Candle> candles, Duration? barDuration) {
  Duration d = barDuration ??
      (candles.length > 1
          ? candles[1].time.difference(candles[0].time)
          : const Duration(minutes: 1));
  if (d <= Duration.zero) d = const Duration(minutes: 1);
  return d;
}

/// The timestamp for a (possibly out-of-range) bar slot, extrapolating cleanly
/// into the empty left (`index < 0`) and right (`index >= length`) margins.
DateTime _timeAtBar(List<Candle> candles, int index, Duration barDuration) {
  if (candles.isEmpty) return DateTime.now();
  if (index >= 0 && index < candles.length) return candles[index].time;
  if (index < 0) {
    return candles.first.time.subtract(barDuration * -index);
  }
  return candles.last.time.add(barDuration * (index - (candles.length - 1)));
}

/// Snaps tick candidates to natural calendar boundaries and enforces a strict
/// minimum pixel separation so time labels never collide at any zoom level.
/// Ticks are extrapolated across empty left/right margins so gridlines and
/// crosshair timestamps remain continuous when the view pans past the data.
List<_TimeTick> _computeTimeTicks(
  List<Candle> candles,
  ChartViewport viewport,
  double width, [
  DisplayTimezone tz = DisplayTimezone.utc,
  Duration? barDuration,
]) {
  if (candles.isEmpty || width <= 0 || viewport.visibleBarCount <= 0) {
    return const <_TimeTick>[];
  }
  final Duration barDur = _effectiveBarDuration(candles, barDuration);

  final int first = viewport.startIndex.floor();
  final int last = viewport.endIndex.ceil();
  if (first > last) return const <_TimeTick>[];

  final Duration visibleSpan = _timeAtBar(candles, last, barDur)
      .difference(_timeAtBar(candles, first, barDur));
  final double barSpacing = width / viewport.visibleBarCount;

  int intradayStepMinutes = 0;
  if (visibleSpan.inDays <= 4) {
    const List<int> steps = <int>[15, 30, 60, 120, 240, 360, 720];
    final int barMinutes = math.max(1, barDur.inMinutes);
    for (final int s in steps) {
      if ((s / barMinutes) * barSpacing >= _minTickSpacingPx) {
        intradayStepMinutes = s;
        break;
      }
    }
    if (intradayStepMinutes == 0) intradayStepMinutes = 720;
  }

  bool isBoundary(DateTime prev, DateTime t) {
    if (visibleSpan.inDays > 730) return t.year != prev.year;
    if (visibleSpan.inDays > 60) {
      return t.year != prev.year || t.month != prev.month;
    }
    if (visibleSpan.inDays > 4) {
      return t.year != prev.year || t.month != prev.month || t.day != prev.day;
    }
    final int minutesOfDay = t.hour * 60 + t.minute;
    return minutesOfDay % intradayStepMinutes == 0;
  }

  final List<_TimeTick> out = <_TimeTick>[];
  DateTime? prev;
  DateTime? prevPainted;
  double lastX = -double.infinity;

  for (int i = first; i <= last; i++) {
    final DateTime t = tz.toDisplayTime(_timeAtBar(candles, i, barDur));
    if (prev != null && isBoundary(prev, t)) {
      final double x = viewport.indexToX(i.toDouble(), width);
      final bool inRange = x >= 0 && x <= width;
      if (inRange && (x - lastX).abs() >= _minTickSpacingPx) {
        String label;
        bool major = true;
        if (visibleSpan.inDays > 730) {
          label = t.year.toString();
        } else if (prevPainted == null) {
          label = visibleSpan.inDays > 4 ? _dayLabel(t) : _hm(t);
          major = visibleSpan.inDays > 4;
        } else if (t.year != prevPainted.year) {
          label = t.year.toString();
        } else if (t.month != prevPainted.month) {
          label = _monthAbbr[t.month - 1];
        } else if (t.day != prevPainted.day) {
          label = _dayLabel(t);
        } else {
          label = _hm(t);
          major = false;
        }
        out.add(_TimeTick(x: x, label: label, major: major));
        lastX = x;
        prevPainted = t;
      }
    }
    prev = t;
  }
  return out;
}

// ============================================================================
// PAINTER A: MAIN CHART CANVAS (Background + Gridlines + Candles + Paths + Crosshair)
// ============================================================================
class MainChartPainter extends CustomPainter {
  final List<Candle> candles;
  final ChartViewport viewport;
  final Offset? cursorPos;
  final ChartTheme theme;
  final List<CrossTimeframePath> paths;
  final CrossTimeframePath? activePath;
  final List<({IndicatorConfig config, List<double?> series})> emaOverlays;
  final DateTimeRange? syncedCursorRange;
  final Duration? barDuration;
  final bool showVolume;
  final OpenPosition? openPosition;
  final List<PendingOrder> pendingOrders;
  final List<CompletedTrade> closedTrades;
  final String? selectedPathId;
  final int? selectedPointIndex;
  final DateTimeRange? highlightedRange;
  final DisplayTimezone displayTimezone;

  MainChartPainter({
    required this.candles,
    required this.viewport,
    required this.cursorPos,
    required this.theme,
    this.paths = const [],
    this.activePath,
    this.emaOverlays = const [],
    this.syncedCursorRange,
    this.barDuration,
    this.showVolume = false,
    this.openPosition,
    this.pendingOrders = const [],
    this.closedTrades = const [],
    this.selectedPathId,
    this.selectedPointIndex,
    this.highlightedRange,
    this.displayTimezone = DisplayTimezone.utc,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);

    final gridPaint = Paint()
      ..color = theme.gridLine
      ..strokeWidth = 1.0;

    // Horizontal grid lines (matches PriceAxisPainter divisions)
    const int priceRows = 6;
    for (int r = 1; r < priceRows; r++) {
      final y = size.height * (r / priceRows);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid lines (hierarchical, collision-free)
    final List<_TimeTick> ticks =
        _computeTimeTicks(candles, viewport, size.width, displayTimezone, barDuration);
    final int first = math.max(0, viewport.startIndex.floor());
    final int last = math.min(candles.length - 1, viewport.endIndex.ceil());
    for (final _TimeTick tick in ticks) {
      canvas.drawLine(
        Offset(tick.x, 0),
        Offset(tick.x, size.height),
        gridPaint,
      );
    }

    // Volume histogram (drawn before candlesticks so candles sit on top)
    if (showVolume && candles.isNotEmpty && viewport.visibleBarCount > 0) {
      double maxVol = 0;
      for (int i = first; i <= last; i++) {
        if (candles[i].volume > maxVol) maxVol = candles[i].volume;
      }
      if (maxVol > 0) {
        final double slotWidth = size.width / viewport.visibleBarCount;
        final double barWidth = math.max(slotWidth * 0.72, 1.0);
        for (int i = first; i <= last; i++) {
          final c = candles[i];
          final double h =
              (c.volume / maxVol) * size.height * 0.18;
          final double x = viewport.indexToX(i.toDouble(), size.width);
          canvas.drawRect(
            Rect.fromLTWH(
              x - barWidth / 2,
              size.height - h,
              barWidth,
              h,
            ),
            Paint()
              ..color = (c.close >= c.open
                      ? theme.bullBorder
                      : theme.bearBody)
                  .withValues(alpha: 0.22),
          );
        }
      }
    }

    // Candles
    if (candles.isNotEmpty && viewport.visibleBarCount > 0) {
      final double slotWidth = size.width / viewport.visibleBarCount;
      final double bodyWidth = math.max(slotWidth * 0.72, 1.0);
      final double wickWidth = clampDouble(slotWidth * 0.12, 1.0, 2.2);

      final Duration candleDuration =
          barDuration ?? const Duration(minutes: 1);

      for (int i = first; i <= last; i++) {
        final c = candles[i];
        final bool isBull = c.close >= c.open;
        final bool matched = highlightedRange != null &&
            c.time.isBefore(highlightedRange!.end) &&
            c.time.add(candleDuration).isAfter(highlightedRange!.start);

        final Color wickColor = matched
            ? theme.activePillBackground
            : (isBull ? theme.bullBorder : theme.bearBorder);
        final wickPaint = Paint()
          ..color = wickColor
          ..strokeWidth = wickWidth;

        final double centerX = viewport.indexToX(i.toDouble(), size.width);
        final double yHigh = viewport.priceToY(c.high, size.height);
        final double yLow = viewport.priceToY(c.low, size.height);
        final double yOpen = viewport.priceToY(c.open, size.height);
        final double yClose = viewport.priceToY(c.close, size.height);

        canvas.drawLine(Offset(centerX, yHigh), Offset(centerX, yLow), wickPaint);

        final double top = math.min(yOpen, yClose);
        final double bottom = math.max(yOpen, yClose);
        final double bodyHeight = math.max(bottom - top, 1.5);
        final Rect bodyRect = Rect.fromLTWH(
          centerX - bodyWidth / 2,
          top,
          bodyWidth,
          bodyHeight,
        );

        if (matched) {
          canvas.drawRect(
            bodyRect,
            Paint()..color = theme.activePillBackground,
          );
          canvas.drawRect(
            bodyRect,
            Paint()
              ..color = theme.activePillBackground
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        } else if (isBull && theme.hollowBull) {
          // Hollow bullish candle: filled body + stroked border
          canvas.drawRect(
            bodyRect,
            Paint()..color = theme.bullBody,
          );
          canvas.drawRect(
            bodyRect,
            Paint()
              ..color = theme.bullBorder
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        } else {
          canvas.drawRect(
            bodyRect,
            Paint()..color = isBull ? theme.bullBody : theme.bearBody,
          );
        }
      }
    }

    // EMA overlays
    for (final ({IndicatorConfig config, List<double?> series}) overlay
        in emaOverlays) {
      if (!overlay.config.visible) continue;
      _drawEma(
        canvas,
        size,
        overlay.series,
        Color(overlay.config.colorValue),
        overlay.config.strokeWidth,
      );
    }

    // Order / position / SL lines and trade markers
    _drawOrdersAndTrades(canvas, size);

    // Cross-timeframe paths
    for (final path in paths) {
      _drawPath(
        canvas,
        size,
        path,
        selected: path.id == selectedPathId,
        selectedIndex: path.id == selectedPathId ? selectedPointIndex : null,
      );
    }
    if (activePath != null) {
      _drawPath(canvas, size, activePath!);

      // Dashed preview line from last point to cursor
      if (cursorPos != null && activePath!.points.isNotEmpty) {
        final last = activePath!.points.last;
        final lastX = viewport.indexToX(
          resolveBarIndex(last.time, candles, barDuration: barDuration),
          size.width,
        );
        final lastY = viewport.priceToY(last.price, size.height);
        _drawDashedLine(
          canvas,
          Offset(lastX, lastY),
          cursorPos!,
          Paint()
            ..color = theme.pathColor.withValues(alpha: 0.7)
            ..strokeWidth = 2.0,
        );
      }
    }

    // Synced crosshair from other panes (subtle time guide)
    if (cursorPos == null && syncedCursorRange != null) {
      final double idx = resolveBarIndex(
        syncedCursorRange!.start,
        candles,
        barDuration: barDuration,
      );
      final double x = viewport.indexToX(idx, size.width);
      if (x >= 0 && x <= size.width) {
        _drawDashedLine(
          canvas,
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = theme.crosshair.withValues(alpha: 0.35)
            ..strokeWidth = 1.0,
        );
      }
    }

    // Crosshair lines only (badges live inside the dedicated axes!)
    if (cursorPos != null) {
      final double rawIndex = viewport.xToIndex(cursorPos!.dx, size.width);
      final double snappedX = viewport.indexToX(
        rawIndex.round().toDouble(),
        size.width,
      );
      final double cursorY = cursorPos!.dy;

      final linePaint = Paint()
        ..color = theme.crosshair.withValues(alpha: 0.7)
        ..strokeWidth = 1.0;

      _drawDashedLine(
        canvas,
        Offset(snappedX, 0),
        Offset(snappedX, size.height),
        linePaint,
      );
      _drawDashedLine(
        canvas,
        Offset(0, cursorY),
        Offset(size.width, cursorY),
        linePaint,
      );
    }
  }

  void _drawOrdersAndTrades(Canvas canvas, Size size) {
    final OpenPosition? pos = openPosition;
    if (pos != null) {
      final Color posBg = pos.side == OrderSide.buy
          ? theme.pendingBuyBackground
          : theme.pendingSellBackground;
      final Color posText = pos.side == OrderSide.buy
          ? theme.pendingBuyText
          : theme.pendingSellText;
      final double y = viewport.priceToY(pos.entryPrice, size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = posBg
          ..strokeWidth = 1.5,
      );
      _drawRightBadge(
        canvas,
        size,
        y,
        '${pos.side == OrderSide.buy ? "LONG" : "SHORT"} ${pos.entryPrice.toStringAsFixed(2)} │ ✕',
        posBg,
        fill: posBg,
        textColor: posText,
      );
    }

    final double? sl = pos?.currentSl;
    if (pos != null && sl != null) {
      final bool slIsProfit =
          pos.side == OrderSide.buy ? sl >= pos.entryPrice : sl <= pos.entryPrice;
      final Color slBg = slIsProfit
          ? theme.pendingBuyBackground
          : theme.pendingSellBackground;
      final Color slText = slIsProfit
          ? theme.pendingBuyText
          : theme.pendingSellText;
      final double y = viewport.priceToY(sl, size.height);
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = slBg
          ..strokeWidth = 1.5,
      );
      _drawRightBadge(
        canvas,
        size,
        y,
        'SL ${sl.toStringAsFixed(2)} │ ✕',
        slBg,
        fill: slBg,
        textColor: slText,
      );
    }

    // Paired risk bracket from the live entry to its stop-loss.
    if (pos != null && pos.currentSl != null) {
      final double yEntry = viewport.priceToY(pos.entryPrice, size.height);
      final double ySl = viewport.priceToY(pos.currentSl!, size.height);
      _drawVerticalBracket(
        canvas,
        16.0,
        yEntry,
        ySl,
        theme.bearBorder.withValues(alpha: 0.75),
      );
    }

    for (int orderIndex = 0; orderIndex < pendingOrders.length; orderIndex++) {
      final PendingOrder order = pendingOrders[orderIndex];
      final Color lineAndBg = order.side == OrderSide.buy
          ? theme.pendingBuyBackground
          : theme.pendingSellBackground;
      final Color orderTextColor = order.side == OrderSide.buy
          ? theme.pendingBuyText
          : theme.pendingSellText;
      final double y = viewport.priceToY(order.entryPrice, size.height);
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = lineAndBg
          ..strokeWidth = 1.2,
      );
      _drawRightBadge(
        canvas,
        size,
        y,
        '${order.side.name.toUpperCase()} ${order.type.name.toUpperCase()} ${order.entryPrice.toStringAsFixed(2)} │ ✕',
        lineAndBg,
        fill: lineAndBg,
        textColor: orderTextColor,
      );

      final double? pendingSl = order.stopLoss;
      if (pendingSl != null) {
        final double ySl = viewport.priceToY(pendingSl, size.height);
        final Color slColor = theme.bearBorder.withValues(alpha: 0.7);
        _drawDashedLine(
          canvas,
          Offset(0, ySl),
          Offset(size.width, ySl),
          Paint()
            ..color = slColor
            ..strokeWidth = 1.2,
        );
        _drawTag(
          canvas,
          Offset(22, ySl),
          'Pending SL (${(order.entryPrice - pendingSl).abs().toStringAsFixed(1)})',
          theme.bearBorder,
          theme.pendingSellText,
        );
        _drawVerticalBracket(
          canvas,
          16.0 + orderIndex * 10.0,
          y,
          ySl,
          slColor,
        );
      }
    }

    // Entry marker for the live position.
    if (pos != null) {
      _drawEntryMarker(canvas, size, pos.side, pos.entryTime, pos.entryPrice);
    }

    // Entry + exit markers for closed trades, connected by a dotted line.
    for (final trade in closedTrades) {
      _drawEntryMarker(
        canvas,
        size,
        trade.side,
        trade.entryTime,
        trade.entryPrice,
      );
      final double entryX = viewport.indexToX(
        resolveBarIndex(trade.entryTime, candles, barDuration: barDuration),
        size.width,
      );
      final double entryY = viewport.priceToY(trade.entryPrice, size.height);
      final double exitX = viewport.indexToX(
        resolveBarIndex(trade.exitTime, candles, barDuration: barDuration),
        size.width,
      );
      final double exitY = viewport.priceToY(trade.exitPrice, size.height);

      _drawDottedLine(
        canvas,
        Offset(entryX, entryY),
        Offset(exitX, exitY),
        Paint()
          ..color = theme.textSecondary.withValues(alpha: 0.5)
          ..strokeWidth = 1.0,
      );

      final Color exitColor =
          trade.pnlPoints >= 0 ? theme.bullBorder : theme.bearBody;
      final Paint exitPaint = Paint()..color = exitColor;
      const double r = 3.5;
      canvas.drawLine(
        Offset(exitX - r, exitY - r),
        Offset(exitX + r, exitY + r),
        exitPaint
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.drawLine(
        Offset(exitX - r, exitY + r),
        Offset(exitX + r, exitY - r),
        exitPaint,
      );
    }
  }

  void _drawEntryMarker(
    Canvas canvas,
    Size size,
    OrderSide side,
    DateTime time,
    double price,
  ) {
    final double x = viewport.indexToX(
      resolveBarIndex(time, candles, barDuration: barDuration),
      size.width,
    );
    final double y = viewport.priceToY(price, size.height);
    const double h = 6.0;
    const double w = 4.0;
    final bool buy = side == OrderSide.buy;
    final double tipY = buy ? y + 12.0 : y - 12.0;
    final double baseY = buy ? tipY - h : tipY + h;
    final Path path = Path()
      ..moveTo(x, tipY)
      ..lineTo(x - w, baseY)
      ..lineTo(x + w, baseY)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = side == OrderSide.buy
            ? theme.pendingBuyBackground
            : theme.pendingSellBackground,
    );
  }

  void _drawRightBadge(
    Canvas canvas,
    Size size,
    double y,
    String text,
    Color accent, {
    Color? fill,
    Color? textColor,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor ?? theme.badgeText,
          fontSize: theme.scaledFontSize(10),
          fontFamily: theme.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double bx = size.width - tp.width - 8;
    final double by = y - tp.height / 2;
    canvas.drawRect(
      Rect.fromLTWH(bx - 3, by - 1, tp.width + 6, tp.height + 2),
      Paint()..color = fill ?? theme.badgeBackground,
    );
    canvas.drawRect(
      Rect.fromLTWH(bx - 3, by - 1, tp.width + 6, tp.height + 2),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(bx, by));
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dot = 2.0;
    const double gap = 4.0;
    final double totalDist = (p2 - p1).distance;
    if (totalDist == 0) return;
    final Offset dir = (p2 - p1) / totalDist;
    double current = 0;
    while (current < totalDist) {
      canvas.drawLine(
        p1 + dir * current,
        p1 + dir * math.min(current + dot, totalDist),
        paint,
      );
      current += dot + gap;
    }
  }

  void _drawEma(
    Canvas canvas,
    Size size,
    List<double?> series,
    Color color,
    double strokeWidth,
  ) {
    if (series.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    bool started = false;
    for (int i = 0; i < series.length; i++) {
      final v = series[i];
      if (v == null) {
        started = false;
        continue;
      }
      final double x = viewport.indexToX(i.toDouble(), size.width);
      final double y = viewport.priceToY(v, size.height);
      if (!started) {
        started = true;
      } else if (i > 0 && series[i - 1] != null) {
        final double px = viewport.indexToX((i - 1).toDouble(), size.width);
        final double py = viewport.priceToY(series[i - 1]!, size.height);
        canvas.drawLine(Offset(px, py), Offset(x, y), paint);
      }
    }
  }

  void _drawPath(
    Canvas canvas,
    Size size,
    CrossTimeframePath path, {
    bool selected = false,
    int? selectedIndex,
  }) {
    if (path.points.isEmpty) return;

    final linePaint = Paint()
      ..color = theme.pathColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final dotPaint = Paint()..color = theme.pathColor;

    final List<Offset> projected = path.points.map((a) {
      final x = viewport.indexToX(
        resolveBarIndex(a.time, candles, barDuration: barDuration),
        size.width,
      );
      return Offset(x, viewport.priceToY(a.price, size.height));
    }).toList();

    if (selected) {
      final haloPaint = Paint()
        ..color = theme.pathColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0;
      for (int i = 0; i < projected.length - 1; i++) {
        canvas.drawLine(projected[i], projected[i + 1], haloPaint);
      }
    }

    for (int i = 0; i < projected.length - 1; i++) {
      canvas.drawLine(projected[i], projected[i + 1], linePaint);
    }
    for (int i = 0; i < projected.length; i++) {
      canvas.drawCircle(projected[i], selected ? 4.5 : 3.5, dotPaint);
      if (selected && selectedIndex == i) {
        canvas.drawCircle(
          projected[i],
          7.0,
          Paint()
            ..color = theme.pathColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dash = 4.0;
    const double gap = 4.0;
    final double totalDist = (p2 - p1).distance;
    if (totalDist == 0) return;
    final Offset dir = (p2 - p1) / totalDist;
    double current = 0;
    while (current < totalDist) {
      canvas.drawLine(
        p1 + dir * current,
        p1 + dir * math.min(current + dash, totalDist),
        paint,
      );
      current += dash + gap;
    }
  }

  /// Vertical dashed bracket with 3px end ticks connecting two price levels.
  void _drawVerticalBracket(
    Canvas canvas,
    double x,
    double yA,
    double yB,
    Color color,
  ) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    _drawDashedLine(canvas, Offset(x, yA), Offset(x, yB), paint);
    canvas.drawLine(Offset(x - 3, yA), Offset(x + 3, yA), paint);
    canvas.drawLine(Offset(x - 3, yB), Offset(x + 3, yB), paint);
  }

  void _drawTag(
    Canvas canvas,
    Offset anchor,
    String text,
    Color bg,
    Color fg,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: fg,
          fontSize: theme.scaledFontSize(10),
          fontFamily: theme.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect r = Rect.fromLTWH(
      anchor.dx,
      anchor.dy - tp.height / 2 - 2,
      tp.width + 8,
      tp.height + 4,
    );
    canvas.drawRect(r, Paint()..color = bg);
    tp.paint(canvas, Offset(anchor.dx + 4, anchor.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant MainChartPainter oldDelegate) => true;
}

// ============================================================================
// PAINTER B: DEDICATED RIGHT PRICE AXIS
// ============================================================================
class PriceAxisPainter extends CustomPainter {
  final ChartViewport viewport;
  final Offset? cursorPos;
  final bool isActive;
  final ChartTheme theme;

  PriceAxisPainter({
    required this.viewport,
    required this.cursorPos,
    required this.isActive,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background + left separator border
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = isActive ? theme.axisActiveBackground : theme.axisBackground,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()
        ..color = theme.border
        ..strokeWidth = 1.0,
    );

    const int priceRows = 6;
    for (int r = 1; r < priceRows; r++) {
      final y = size.height * (r / priceRows);
      final price = viewport.yToPrice(y, size.height);

      // Small tick mark on axis border
      canvas.drawLine(
        Offset(0, y),
        Offset(4, y),
        Paint()..color = theme.textSecondary,
      );

      _drawCenteredText(
        canvas,
        price.toStringAsFixed(2),
        Offset(8, y - 6),
        theme.textSecondary,
      );
    }

    // Active crosshair price badge
    if (cursorPos != null &&
        cursorPos!.dy >= 0 &&
        cursorPos!.dy <= size.height) {
      final double y = cursorPos!.dy;
      final double hoveredPrice = viewport.yToPrice(y, size.height);

      final badgeRect = Rect.fromLTWH(1, y - 10, size.width - 2, 20);
      canvas.drawRect(badgeRect, Paint()..color = theme.badgeBackground);
      _drawCenteredText(
        canvas,
        hoveredPrice.toStringAsFixed(2),
        Offset(8, y - 6),
        theme.badgeText,
      );
    }
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: theme.scaledFontSize(11),
          fontFamily: theme.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant PriceAxisPainter oldDelegate) => true;
}

// ============================================================================
// PAINTER C: DEDICATED BOTTOM TIME AXIS
// ============================================================================
class TimeAxisPainter extends CustomPainter {
  final List<Candle> candles;
  final ChartViewport viewport;
  final Offset? cursorPos;
  final bool isActive;
  final ChartTheme theme;
  final DisplayTimezone displayTimezone;
  final Duration? barDuration;

  TimeAxisPainter({
    required this.candles,
    required this.viewport,
    required this.cursorPos,
    required this.isActive,
    required this.theme,
    this.displayTimezone = DisplayTimezone.utc,
    this.barDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background + top separator border
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = isActive ? theme.axisActiveBackground : theme.axisBackground,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = theme.border
        ..strokeWidth = 1.0,
    );

    if (candles.isEmpty) return;

    final List<_TimeTick> ticks =
        _computeTimeTicks(candles, viewport, size.width, displayTimezone, barDuration);
    for (final _TimeTick tick in ticks) {
      final double x = tick.x;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, 4),
        Paint()..color = theme.textSecondary,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: tick.label,
          style: TextStyle(
            color: tick.major ? theme.textPrimary : theme.textSecondary,
            fontSize: theme.scaledFontSize(11),
            fontFamily: theme.fontFamily,
            fontWeight: tick.major ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      if (x - tp.width / 2 < 0 || x + tp.width / 2 > size.width) continue;
      tp.paint(canvas, Offset(x - tp.width / 2, 7));
    }

    // Active crosshair timestamp badge (extrapolates into empty margins).
    if (cursorPos != null &&
        cursorPos!.dx >= 0 &&
        cursorPos!.dx <= size.width) {
      final Duration barDur = _effectiveBarDuration(candles, barDuration);
      final int snappedIdx = viewport.xToIndex(cursorPos!.dx, size.width).round();
      final double snappedX = viewport.indexToX(
        snappedIdx.toDouble(),
        size.width,
      );
      final String label = _fullTime(
        displayTimezone.toDisplayTime(_timeAtBar(candles, snappedIdx, barDur)),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: theme.badgeText,
            fontSize: theme.scaledFontSize(11),
            fontFamily: theme.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final double badgeW = tp.width + 12;
      final double badgeX = clampDouble(
        snappedX - badgeW / 2,
        0,
        size.width - badgeW,
      );
      canvas.drawRect(
        Rect.fromLTWH(badgeX, 1, badgeW, size.height - 2),
        Paint()..color = theme.badgeBackground,
      );
      tp.paint(canvas, Offset(badgeX + 6, 7));
    }
  }

  String _fullTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$mo-$d ${_hm(dt)}';
  }

  @override
  bool shouldRepaint(covariant TimeAxisPainter oldDelegate) => true;
}

// ============================================================================
// PAINTER D: RSI OSCILLATOR SUB-PANE
// ============================================================================
typedef IndicatorSeries = ({IndicatorConfig config, List<double?> series});

double _rsiY(double value, double height) =>
    height - (value.clamp(0.0, 100.0) / 100.0) * height;

void _drawDashLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
  const double dash = 4.0;
  const double gap = 3.0;
  final double total = (p2 - p1).distance;
  if (total == 0) return;
  final Offset dir = (p2 - p1) / total;
  double current = 0;
  while (current < total) {
    canvas.drawLine(
      p1 + dir * current,
      p1 + dir * math.min(current + dash, total),
      paint,
    );
    current += dash + gap;
  }
}

class RsiSubPanePainter extends CustomPainter {
  final List<Candle> candles;
  final ChartViewport viewport;
  final List<IndicatorSeries> rsiOverlays;
  final Offset? cursorPos;
  final DateTimeRange? syncedCursorRange;
  final ChartTheme theme;
  final Duration? barDuration;

  RsiSubPanePainter({
    required this.candles,
    required this.viewport,
    required this.rsiOverlays,
    required this.cursorPos,
    required this.syncedCursorRange,
    required this.theme,
    this.barDuration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = theme.border
        ..strokeWidth = 1.0,
    );
    if (size.height <= 0 || viewport.visibleBarCount <= 0) return;

    double overbought = 70.0;
    double oversold = 30.0;
    for (final IndicatorSeries overlay in rsiOverlays) {
      if (overlay.config.visible) {
        overbought = overlay.config.overbought;
        oversold = overlay.config.oversold;
        break;
      }
    }

    final Paint guide = Paint()
      ..color = theme.gridLine
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (final double level in <double>[overbought, 50.0, oversold]) {
      final double y = _rsiY(level, size.height);
      _drawDashLine(canvas, Offset(0, y), Offset(size.width, y), guide);
    }

    final int first = math.max(0, viewport.startIndex.floor());
    for (final IndicatorSeries overlay in rsiOverlays) {
      if (!overlay.config.visible) continue;
      final List<double?> series = overlay.series;
      if (series.isEmpty) continue;
      final int last = math.min(
        series.length - 1,
        math.max(first, viewport.endIndex.ceil()),
      );
      final Paint line = Paint()
        ..color = Color(overlay.config.colorValue)
        ..strokeWidth = overlay.config.strokeWidth
        ..style = PaintingStyle.stroke;
      Offset? prev;
      for (int i = first; i <= last; i++) {
        final double? value = series[i];
        if (value == null) {
          prev = null;
          continue;
        }
        final Offset point = Offset(
          viewport.indexToX(i.toDouble(), size.width),
          _rsiY(value, size.height),
        );
        if (prev != null) canvas.drawLine(prev, point, line);
        prev = point;
      }
    }

    final Paint cursorPaint = Paint()
      ..color = theme.crosshair.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    if (cursorPos != null) {
      final int idx =
          viewport.xToIndex(cursorPos!.dx, size.width).round();
      final double x = viewport.indexToX(idx.toDouble(), size.width);
      if (x >= 0 && x <= size.width) {
        _drawDashLine(canvas, Offset(x, 0), Offset(x, size.height), cursorPaint);
      }
    }
    if (syncedCursorRange != null && candles.isNotEmpty) {
      final double idx = resolveBarIndex(
        syncedCursorRange!.start,
        candles,
        barDuration: barDuration,
      );
      final double x = viewport.indexToX(idx, size.width);
      if (x >= 0 && x <= size.width) {
        _drawDashLine(canvas, Offset(x, 0), Offset(x, size.height), cursorPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RsiSubPanePainter old) => true;
}

class RsiAxisPainter extends CustomPainter {
  final ChartViewport viewport;
  final List<IndicatorSeries> rsiOverlays;
  final Offset? cursorPos;
  final double chartWidth;
  final ChartTheme theme;

  RsiAxisPainter({
    required this.viewport,
    required this.rsiOverlays,
    required this.cursorPos,
    required this.chartWidth,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = theme.axisBackground,
    );
    canvas.drawLine(
      Offset.zero,
      Offset(0, size.height),
      Paint()
        ..color = theme.border
        ..strokeWidth = 1.0,
    );

    for (final double level in <double>[70.0, 30.0]) {
      final double y = _rsiY(level, size.height);
      _axisText(
        canvas,
        level.toStringAsFixed(0),
        Offset(8, y - theme.scaledFontSize(10) / 2),
        theme.textSecondary,
      );
    }

    IndicatorSeries? active;
    for (final IndicatorSeries overlay in rsiOverlays) {
      if (overlay.config.visible) {
        active = overlay;
        break;
      }
    }
    if (active == null) return;
    final List<double?> series = active.series;
    int? index;
    if (cursorPos != null && cursorPos!.dx >= 0 && cursorPos!.dx <= chartWidth) {
      final int i = viewport.xToIndex(cursorPos!.dx, chartWidth).round();
      if (i >= 0 && i < series.length) index = i;
    }
    index ??= _lastNonNull(series);
    if (index == null) return;
    final double? value = series[index];
    if (value == null) return;

    final double y = _rsiY(value, size.height);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: value.toStringAsFixed(1),
        style: TextStyle(
          color: theme.badgeText,
          fontSize: theme.scaledFontSize(10),
          fontFamily: theme.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.drawRect(
      Rect.fromLTWH(1, y - 10, size.width - 2, 20),
      Paint()..color = Color(active.config.colorValue),
    );
    tp.paint(canvas, Offset(8, y - tp.height / 2));
  }

  int? _lastNonNull(List<double?> series) {
    for (int i = series.length - 1; i >= 0; i--) {
      if (series[i] != null) return i;
    }
    return null;
  }

  void _axisText(Canvas canvas, String text, Offset offset, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: theme.scaledFontSize(10),
          fontFamily: theme.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant RsiAxisPainter old) => true;
}
