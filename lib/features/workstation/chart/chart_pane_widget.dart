import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/chart_theme.dart';
import '../../../domain/engine/bar_aggregator.dart';
import '../../../domain/models/candle.dart';
import '../../../domain/models/display_timezone.dart';
import '../../../domain/models/drawing.dart';
import '../../../domain/models/order.dart';
import '../../../domain/models/timeframe.dart';
import '../tiling/tiling_node.dart';
import 'chart_painters.dart';
import 'chart_viewport.dart';

/// A self-contained, fully interactive chart pane for a single [PaneNode].
class ChartPaneWidget extends StatefulWidget {
  final PaneNode node;
  final List<Candle> base1mCandles;
  final ChartTheme theme;
  final bool isDrawingPath;
  final List<CrossTimeframePath> paths;
  final CrossTimeframePath? activePath;
  final DateTimeRange? syncedCursorRange;
  final bool canClose;
  final ValueChanged<PaneNode> onUpdatePane;
  final ValueChanged<Axis> onSplit;
  final VoidCallback onClose;
  final ValueChanged<DateTimeRange?> onHoverRangeChanged;
  final void Function(ChartAnchor anchor) onAddPathPoint;
  final VoidCallback onFinishPath;
  final OpenPosition? openPosition;
  final List<PendingOrder> pendingOrders;
  final List<CompletedTrade> closedTrades;
  final OrderSide? pendingPlacementSide;
  final void Function(OrderSide side, double price)? onPlacePendingOrder;
  final ValueChanged<double>? onUpdateSl;
  final void Function(String orderId, double newPrice)? onUpdatePendingPrice;
  final ValueChanged<String>? onCancelPendingOrder;
  final String? selectedPathId;
  final int? selectedPointIndex;
  final void Function(String? pathId, int? pointIndex)? onSelectPath;
  final void Function(String pathId, int pointIndex, ChartAnchor newAnchor)?
      onUpdatePathPoint;
  final VoidCallback? onFocusRequested;
  final VoidCallback? onClosePosition;
  final VoidCallback? onRemoveSl;
  final DisplayTimezone displayTimezone;

  const ChartPaneWidget({
    super.key,
    required this.node,
    required this.base1mCandles,
    required this.theme,
    required this.isDrawingPath,
    required this.paths,
    required this.activePath,
    required this.syncedCursorRange,
    required this.canClose,
    required this.onUpdatePane,
    required this.onSplit,
    required this.onClose,
    required this.onHoverRangeChanged,
    required this.onAddPathPoint,
    required this.onFinishPath,
    this.openPosition,
    this.pendingOrders = const [],
    this.closedTrades = const [],
    this.pendingPlacementSide,
    this.onPlacePendingOrder,
    this.onUpdateSl,
    this.onUpdatePendingPrice,
    this.onCancelPendingOrder,
    this.selectedPathId,
    this.selectedPointIndex,
    this.onSelectPath,
    this.onUpdatePathPoint,
    this.onFocusRequested,
    this.onClosePosition,
    this.onRemoveSl,
    this.displayTimezone = DisplayTimezone.utc,
  });

  @override
  State<ChartPaneWidget> createState() => _ChartPaneWidgetState();
}

class _ChartPaneWidgetState extends State<ChartPaneWidget> {
  static const double priceAxisWidth = 64.0;
  static const double timeAxisHeight = 24.0;
  static const double rightMarginBars = 10.0;
  static const double headerHeight = 30.0;

  List<Candle> _candles = [];
  late ChartViewport _viewport;

  Offset? _cursorPos;
  bool _isPanningChart = false;
  bool _isDraggingPriceAxis = false;
  bool _isDraggingTimeAxis = false;

  Size _chartSize = Size.zero;

  // Instant-click tracking (bypasses GestureArena double-tap delay)
  DateTime? _lastPathClickTime;
  Offset? _lastPathClickPos;

  String? _draggingLineId;
  String? _draggingPathId;
  int? _draggingPointIndex;

  Offset _anchorScreen(ChartAnchor a) {
    final double x = _viewport.indexToX(
      resolveBarIndex(
        a.time,
        _candles,
        barDuration: widget.node.timeframe.duration,
      ),
      _chartSize.width,
    );
    return Offset(x, _viewport.priceToY(a.price, _chartSize.height));
  }

  ChartAnchor _anchorAt(Offset local) {
    final double idx = _viewport.xToIndex(local.dx, _chartSize.width);
    return ChartAnchor(
      time: _barIndexToTime(idx),
      price: _viewport.yToPrice(local.dy, _chartSize.height),
    );
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final Offset ab = b - a;
    final double lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    double t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final Offset proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

  @override
  void initState() {
    super.initState();
    _rebuildCandles(preserveViewport: false);
  }

  @override
  void dispose() {
    _touchLongPressTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChartPaneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool sameTimeframe =
        widget.node.timeframe == oldWidget.node.timeframe;
    if (sameTimeframe &&
        identical(widget.base1mCandles, oldWidget.base1mCandles)) {
      // Hover/cursor-only rebuild: never re-aggregate or touch the viewport.
      return;
    }
    final bool sliceChanged = !identical(
          widget.base1mCandles,
          oldWidget.base1mCandles,
        ) &&
        _sliceChanged(widget.base1mCandles, oldWidget.base1mCandles);
    if (!sameTimeframe || sliceChanged) {
      _rebuildCandles(
        preserveViewport: true,
        previousTimeframe: oldWidget.node.timeframe,
      );
    }
  }

  bool _sliceChanged(List<Candle> a, List<Candle> b) {
    if (a.length != b.length) return true;
    if (a.isEmpty && b.isEmpty) return false;
    if (a.isEmpty || b.isEmpty) return true;
    return a.first.time != b.first.time || a.last.time != b.last.time;
  }

  void _rebuildCandles({
    required bool preserveViewport,
    Timeframe? previousTimeframe,
  }) {
    final bool hasOld =
        preserveViewport && _candles.isNotEmpty && _viewport.visibleBarCount > 0;
    final int oldLen = _candles.length;
    final double oldStart = hasOld ? _viewport.startIndex : 0;
    final double oldEnd = hasOld ? _viewport.endIndex : 0;
    final double oldSpan = hasOld ? _viewport.visibleBarCount : 80.0;
    final bool sameTimeframe =
        previousTimeframe == null || previousTimeframe == widget.node.timeframe;

    _candles = BarAggregator.aggregate(widget.base1mCandles, widget.node.timeframe);

    final double maxEnd = _candles.length + rightMarginBars;
    const double minStart = -10.0;

    double newStart;
    double newEnd;
    if (!hasOld || !sameTimeframe) {
      // Fresh mount or timeframe switch: snap to the right edge.
      newEnd = maxEnd;
      newStart = math.max(0.0, newEnd - oldSpan);
    } else {
      final bool atRightEdge = oldEnd >= oldLen - 1;
      final double shift = atRightEdge
          ? (_candles.length - oldLen).toDouble()
          : 0.0;
      newStart = oldStart + shift;
      newEnd = oldEnd + shift;

      final double span = newEnd - newStart;
      final double maxStart = maxEnd - span;
      if (maxStart <= minStart) {
        newStart = (minStart + maxStart) / 2.0;
        newEnd = newStart + span;
      } else {
        newStart = clampDouble(newStart, minStart, maxStart);
        newEnd = newStart + span;
      }
    }

    _viewport = ChartViewport(
      startIndex: newStart,
      endIndex: newEnd,
      minPrice: 0,
      maxPrice: 100,
      autoScaleY: true,
    );
    _viewport.fitPriceToVisible(_candles);
  }

  // --------------------------------------------------------------------------
  // Path drawing (zero-latency pointer handling)
  // --------------------------------------------------------------------------
  DateTime _barIndexToTime(double barIndex) {
    if (_candles.isEmpty) return DateTime.now();
    final baseMs = _candles.first.time.millisecondsSinceEpoch;
    final stepMs = widget.node.timeframe.duration.inMilliseconds;
    return DateTime.fromMillisecondsSinceEpoch(
      baseMs + (barIndex * stepMs).round(),
      isUtc: _candles.first.time.isUtc,
    );
  }

  void _onChartPointerDown(PointerDownEvent event) {
    if (!widget.isDrawingPath) {
      if (_chartSize.height <= 0 || _chartSize.width <= 0) return;
      widget.onFocusRequested?.call();

      // Cancel a pending order via its ✕ badge or a right-click on the line.
      final double touchHalo = _tol(event.kind, 10.0, 22.0);
      final double touchX = _tol(event.kind, 20.0, 28.0);
      for (final order in widget.pendingOrders) {
        final double orderY =
            _viewport.priceToY(order.entryPrice, _chartSize.height);
        final bool leftCancel = event.buttons == kPrimaryButton &&
            event.localPosition.dx >= _chartSize.width - touchX &&
            (event.localPosition.dy - orderY).abs() <= touchHalo;
        final bool rightCancel = event.kind == PointerDeviceKind.mouse &&
            event.buttons == kSecondaryMouseButton &&
            (event.localPosition.dy - orderY).abs() <= 8.0;
        if (leftCancel || rightCancel) {
          widget.onCancelPendingOrder?.call(order.id);
          return;
        }
      }

      if (event.buttons != kPrimaryButton) return;
      if (widget.pendingPlacementSide != null) {
        final double price =
            _viewport.yToPrice(event.localPosition.dy, _chartSize.height);
        widget.onPlacePendingOrder?.call(widget.pendingPlacementSide!, price);
        return;
      }
      // ✕ on the live position / SL badges.
      if (widget.openPosition != null) {
        final double posY = _viewport.priceToY(
          widget.openPosition!.entryPrice,
          _chartSize.height,
        );
        if (event.localPosition.dx >= _chartSize.width - touchX &&
            (posY - event.localPosition.dy).abs() <= touchHalo) {
          widget.onClosePosition?.call();
          return;
        }
      }
      final double? slBadge = widget.openPosition?.currentSl;
      if (slBadge != null) {
        final double slY = _viewport.priceToY(slBadge, _chartSize.height);
        if (event.localPosition.dx >= _chartSize.width - touchX &&
            (slY - event.localPosition.dy).abs() <= touchHalo) {
          widget.onRemoveSl?.call();
          return;
        }
      }

      final double y = event.localPosition.dy;
      final double lineTol = _tol(event.kind, 8.0, 22.0);
      final double? sl = widget.openPosition?.currentSl;
      if (sl != null &&
          (_viewport.priceToY(sl, _chartSize.height) - y).abs() <= lineTol) {
        setState(() => _draggingLineId = 'SL');
        return;
      }
      for (final order in widget.pendingOrders) {
        if ((_viewport.priceToY(order.entryPrice, _chartSize.height) - y)
                .abs() <=
            lineTol) {
          setState(() => _draggingLineId = order.id);
          return;
        }
      }

      // Path selection / dot dragging.
      final double dotTol = _tol(event.kind, 9.0, 22.0);
      final double segTol = _tol(event.kind, 7.0, 18.0);
      for (final path in widget.paths) {
        for (int i = 0; i < path.points.length; i++) {
          if ((event.localPosition - _anchorScreen(path.points[i])).distance <=
              dotTol) {
            widget.onSelectPath?.call(path.id, i);
            setState(() {
              _draggingPathId = path.id;
              _draggingPointIndex = i;
            });
            return;
          }
        }
      }
      for (final path in widget.paths) {
        for (int i = 0; i + 1 < path.points.length; i++) {
          final Offset a = _anchorScreen(path.points[i]);
          final Offset b = _anchorScreen(path.points[i + 1]);
          if (_distToSegment(event.localPosition, a, b) <= segTol) {
            widget.onSelectPath?.call(path.id, null);
            return;
          }
        }
      }
      if (widget.selectedPathId != null) {
        widget.onSelectPath?.call(null, null);
      }
      return;
    }

    // Secondary button: finish and commit the active path instantly.
    if (event.buttons == kSecondaryMouseButton) {
      widget.onFinishPath();
      return;
    }
    if (event.buttons != kPrimaryButton) return;

    // Double-click detection (fast + close together).
    final bool isDoubleClick = _lastPathClickTime != null &&
        _lastPathClickPos != null &&
        DateTime.now().difference(_lastPathClickTime!).inMilliseconds < 280 &&
        (event.localPosition - _lastPathClickPos!).distance < 6.0;

    if (isDoubleClick) {
      _lastPathClickTime = null;
      _lastPathClickPos = null;
      widget.onFinishPath();
      return;
    }

    // Single click: append an anchor immediately.
    if (_chartSize.width <= 0 || _chartSize.height <= 0) return;

    final barIndex =
        _viewport.xToIndex(event.localPosition.dx, _chartSize.width);
    final price = _viewport.yToPrice(event.localPosition.dy, _chartSize.height);

    setState(() {
      _lastPathClickTime = DateTime.now();
      _lastPathClickPos = event.localPosition;
      _cursorPos = event.localPosition;
    });
    widget.onAddPathPoint(
      ChartAnchor(time: _barIndexToTime(barIndex), price: price),
    );
  }

  // --------------------------------------------------------------------------
  // Chart gestures (arena-free, deterministic pointer tracking)
  // --------------------------------------------------------------------------
  Offset _scaleStartFocal = Offset.zero;
  double _scaleStartSpan = 0;
  double _scaleStartStart = 0;
  double _scaleStartMinPrice = 0;
  double _scaleStartMaxPrice = 0;

  final Map<int, Offset> _pointers = <int, Offset>{};
  final Map<int, PointerDeviceKind> _pointerKinds = <int, PointerDeviceKind>{};
  double _pinchStartDistance = 1.0;

  bool _longPressActive = false;
  Timer? _touchLongPressTimer;
  Offset? _downPos;
  DateTime? _lastTapTime;
  Offset? _lastTapPos;

  double _tol(PointerDeviceKind kind, double mouse, double touch) =>
      kind == PointerDeviceKind.touch ? touch : mouse;

  Offset get _pointerMidpoint {
    final Iterable<Offset> values = _pointers.values;
    if (values.isEmpty) return Offset.zero;
    double sx = 0;
    double sy = 0;
    for (final Offset p in values) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / values.length, sy / values.length);
  }

  Iterable<Offset> get _firstTwoPointers => _pointers.values.take(2);

  void _snapshotScaleStart(Offset focal) {
    _scaleStartFocal = focal;
    _scaleStartSpan = _viewport.visibleBarCount;
    _scaleStartStart = _viewport.startIndex;
    _scaleStartMinPrice = _viewport.minPrice;
    _scaleStartMaxPrice = _viewport.maxPrice;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    _pointerKinds[event.pointer] = event.kind;

    if (widget.isDrawingPath) {
      _onChartPointerDown(event);
      return;
    }

    if (_pointers.length == 1) {
      _onChartPointerDown(event);
      if (_draggingLineId != null || _draggingPathId != null) return;

      _downPos = event.localPosition;
      _snapshotScaleStart(event.localPosition);
      if (event.kind == PointerDeviceKind.touch) {
        _touchLongPressTimer?.cancel();
        _touchLongPressTimer =
            Timer(const Duration(milliseconds: 450), _activateTouchLongPress);
      }
    } else if (_pointers.length == 2) {
      _touchLongPressTimer?.cancel();
      _touchLongPressTimer = null;
      _longPressActive = false;
      final List<Offset> pts = _firstTwoPointers.toList();
      _pinchStartDistance = math.max((pts[0] - pts[1]).distance, 1.0);
      _snapshotScaleStart(_pointerMidpoint);
    }
  }

  void _activateTouchLongPress() {
    if (!mounted || _downPos == null) return;
    setState(() {
      _longPressActive = true;
      _cursorPos = _downPos;
    });
    _reportHoverTime();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    // Line / path-point dragging takes priority over pan and zoom.
    if (_draggingPathId != null && _draggingPointIndex != null) {
      widget.onUpdatePathPoint?.call(
        _draggingPathId!,
        _draggingPointIndex!,
        _anchorAt(event.localPosition),
      );
      setState(() {});
      return;
    }
    if (_draggingLineId != null) {
      final double price =
          _viewport.yToPrice(event.localPosition.dy, _chartSize.height);
      if (_draggingLineId == 'SL') {
        widget.onUpdateSl?.call(price);
      } else {
        widget.onUpdatePendingPrice?.call(_draggingLineId!, price);
      }
      setState(() {});
      return;
    }

    if (_longPressActive && _pointers.length == 1) {
      if (_chartSize.width <= 0 || _chartSize.height <= 0) return;
      setState(() => _cursorPos = event.localPosition);
      _reportHoverTime();
      return;
    }

    if (_pointers.length == 1) {
      if (_downPos != null &&
          (event.localPosition - _downPos!).distance > 8.0) {
        _touchLongPressTimer?.cancel();
        _touchLongPressTimer = null;
      }
      if (_chartSize.width <= 0 || _chartSize.height <= 0) return;

      setState(() {
        final double dx = event.localPosition.dx - _scaleStartFocal.dx;
        final double dy = event.localPosition.dy - _scaleStartFocal.dy;
        final double barsPerPixel = _scaleStartSpan / _chartSize.width;
        final double deltaBars = -dx * barsPerPixel;

        double newStart = _scaleStartStart + deltaBars;
        double newEnd = newStart + _scaleStartSpan;
        final double maxEnd = _candles.length + rightMarginBars;
        const double minStart = -10.0;
        final double maxStart = maxEnd - _scaleStartSpan;
        if (maxStart <= minStart) {
          newStart = (minStart + maxStart) / 2.0;
          newEnd = newStart + _scaleStartSpan;
        } else {
          newStart = clampDouble(newStart, minStart, maxStart);
          newEnd = newStart + _scaleStartSpan;
        }
        _viewport.startIndex = newStart;
        _viewport.endIndex = newEnd;

        if (!_viewport.autoScaleY) {
          final double pricePerPixel =
              (_scaleStartMaxPrice - _scaleStartMinPrice) / _chartSize.height;
          final double panPrice = dy * pricePerPixel;
          _viewport.minPrice = _scaleStartMinPrice + panPrice;
          _viewport.maxPrice = _scaleStartMaxPrice + panPrice;
        } else {
          _viewport.fitPriceToVisible(_candles);
        }
        _isPanningChart = true;
      });
      _reportHoverTime();
      return;
    }

    if (_pointers.length >= 2) {
      if (_chartSize.width <= 0 || _chartSize.height <= 0) return;
      final List<Offset> pts = _firstTwoPointers.toList();
      final Offset focal = (pts[0] + pts[1]) / 2.0;
      final double scale = (pts[0] - pts[1]).distance / _pinchStartDistance;

      setState(() {
        final double maxSpan = math.max(_candles.length + 30.0, 40.0);
        final double focalRatio = clampDouble(
          _scaleStartFocal.dx / _chartSize.width,
          0.0,
          1.0,
        );
        final double anchorBar = _scaleStartStart + focalRatio * _scaleStartSpan;
        final double newSpan = clampDouble(
          _scaleStartSpan / (scale == 0 ? 1 : scale),
          10.0,
          maxSpan,
        );
        final double barsPerPixel = _scaleStartSpan / _chartSize.width;
        final double panBars = -(focal.dx - _scaleStartFocal.dx) * barsPerPixel;

        double newStart = anchorBar - focalRatio * newSpan + panBars;
        double newEnd = newStart + newSpan;
        final double maxEnd = _candles.length + rightMarginBars;
        const double minStart = -10.0;
        final double maxStart = maxEnd - newSpan;
        if (maxStart <= minStart) {
          newStart = (minStart + maxStart) / 2.0;
          newEnd = newStart + newSpan;
        } else {
          newStart = clampDouble(newStart, minStart, maxStart);
          newEnd = newStart + newSpan;
        }
        _viewport.startIndex = newStart;
        _viewport.endIndex = newEnd;
        _viewport.fitPriceToVisible(_candles);
      });
    }
  }

  void _maybeHandleDoubleTap(PointerUpEvent event, bool wasSingle) {
    if (widget.isDrawingPath || !wasSingle) return;
    if (_downPos == null) return;
    if ((event.localPosition - _downPos!).distance >= 12.0) return;
    if (_longPressActive) return;

    final DateTime now = DateTime.now();
    final bool isDouble = _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300 &&
        _lastTapPos != null &&
        (event.localPosition - _lastTapPos!).distance < 24.0;
    if (isDouble) {
      _lastTapTime = null;
      _lastTapPos = null;
      _onAutoFit();
    } else {
      _lastTapTime = now;
      _lastTapPos = event.localPosition;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final bool wasSingle = _pointers.length == 1;
    _maybeHandleDoubleTap(event, wasSingle);

    _pointers.remove(event.pointer);
    _pointerKinds.remove(event.pointer);

    _touchLongPressTimer?.cancel();
    _touchLongPressTimer = null;

    if (_pointers.length == 1) {
      _downPos = _pointers.values.first;
      _snapshotScaleStart(_pointers.values.first);
    } else if (_pointers.isEmpty) {
      _longPressActive = false;
      _downPos = null;
      setState(() {
        _isPanningChart = false;
        _draggingLineId = null;
        _draggingPathId = null;
        _draggingPointIndex = null;
        if (event.kind == PointerDeviceKind.touch && _cursorPos != null) {
          _cursorPos = null;
        }
      });
      if (event.kind == PointerDeviceKind.touch) {
        widget.onHoverRangeChanged(null);
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _pointerKinds.remove(event.pointer);
    _touchLongPressTimer?.cancel();
    _touchLongPressTimer = null;

    if (_pointers.length == 1) {
      _downPos = _pointers.values.first;
      _snapshotScaleStart(_pointers.values.first);
    } else if (_pointers.isEmpty) {
      _longPressActive = false;
      _downPos = null;
      setState(() {
        _isPanningChart = false;
        _draggingLineId = null;
        _draggingPathId = null;
        _draggingPointIndex = null;
        _cursorPos = null;
      });
      widget.onHoverRangeChanged(null);
    }
  }

  void _onChartWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _chartSize.width <= 0) return;

    setState(() {
      final zoomFactor = event.scrollDelta.dy > 0 ? 1.12 : 0.88;
      final currentSpan = _viewport.visibleBarCount;
      final newSpan = clampDouble(
        currentSpan * zoomFactor,
        10.0,
        math.max(_candles.length + 30.0, 40.0),
      );

      final cursorRatio = clampDouble(
        event.localPosition.dx / _chartSize.width,
        0.0,
        1.0,
      );
      final anchorBar = _viewport.startIndex + cursorRatio * currentSpan;

      _viewport.startIndex = anchorBar - cursorRatio * newSpan;
      _viewport.endIndex = _viewport.startIndex + newSpan;
      _viewport.fitPriceToVisible(_candles);
    });
  }

  void _onPriceAxisDragUpdate(DragUpdateDetails details) {
    setState(() {
      _viewport.autoScaleY = false;
      final scaleFactor = math.exp(details.delta.dy * 0.008);
      final centerPrice = (_viewport.minPrice + _viewport.maxPrice) / 2.0;
      final halfSpan = (_viewport.priceRange / 2.0) * scaleFactor;
      final clampedHalfSpan = clampDouble(halfSpan, 0.05, 100000.0);
      _viewport.minPrice = centerPrice - clampedHalfSpan;
      _viewport.maxPrice = centerPrice + clampedHalfSpan;
    });
  }

  void _onAutoFit() {
    setState(() {
      _viewport.autoScaleY = true;
      _viewport.fitPriceToVisible(_candles);
    });
  }

  void _onTimeAxisDragUpdate(DragUpdateDetails details) {
    setState(() {
      final scaleFactor = math.exp(-details.delta.dx * 0.006);
      final currentSpan = _viewport.visibleBarCount;
      final newSpan = clampDouble(
        currentSpan * scaleFactor,
        10.0,
        math.max(_candles.length + 30.0, 40.0),
      );
      final rightAnchor = _viewport.endIndex;
      _viewport.endIndex = rightAnchor;
      _viewport.startIndex = rightAnchor - newSpan;
      _viewport.fitPriceToVisible(_candles);
    });
  }

  void _onResetView() {
    setState(() {
      _viewport.endIndex = _candles.length + rightMarginBars;
      _viewport.startIndex = math.max(0.0, _viewport.endIndex - 80.0);
      _viewport.fitPriceToVisible(_candles);
    });
  }

  void _reportHoverTime() {
    if (_cursorPos == null || _chartSize.width <= 0 || _candles.isEmpty) {
      widget.onHoverRangeChanged(null);
      return;
    }
    final idx =
        _viewport.xToIndex(_cursorPos!.dx, _chartSize.width).round();
    if (idx >= 0 && idx < _candles.length) {
      final DateTime start = _candles[idx].time;
      widget.onHoverRangeChanged(
        DateTimeRange(
          start: start,
          end: start.add(widget.node.timeframe.duration),
        ),
      );
    } else {
      widget.onHoverRangeChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final ema20 =
        widget.node.showEma20 ? BarAggregator.computeEma(_candles, 20) : null;
    final ema50 =
        widget.node.showEma50 ? BarAggregator.computeEma(_candles, 50) : null;
    final ema200 =
        widget.node.showEma200 ? BarAggregator.computeEma(_candles, 200) : null;

    Candle? hovered;
    if (_cursorPos != null && _chartSize.width > 0 && _candles.isNotEmpty) {
      final idx = _viewport.xToIndex(_cursorPos!.dx, _chartSize.width).round();
      if (idx >= 0 && idx < _candles.length) hovered = _candles[idx];
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.border, width: 1),
      ),
      child: Column(
        children: [
          _buildHeader(hovered),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double chartW =
                    math.max(1.0, constraints.maxWidth - priceAxisWidth);
                final double chartH =
                    math.max(1.0, constraints.maxHeight - timeAxisHeight);
                _chartSize = Size(chartW, chartH);

                return Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerSignal: _onChartWheel,
                              onPointerDown: _onPointerDown,
                              onPointerMove: _onPointerMove,
                              onPointerUp: _onPointerUp,
                              onPointerCancel: _onPointerCancel,
                              child: MouseRegion(
                                cursor: widget.isDrawingPath
                                    ? SystemMouseCursors.precise
                                    : _isPanningChart
                                        ? SystemMouseCursors.grabbing
                                        : SystemMouseCursors.precise,
                                onHover: (e) {
                                  setState(() => _cursorPos = e.localPosition);
                                  _reportHoverTime();
                                },
                                onExit: (_) {
                                  setState(() => _cursorPos = null);
                                  widget.onHoverRangeChanged(null);
                                },
                                child: ClipRect(
                                    child: Stack(
                                      children: [
                                        CustomPaint(
                                          size: _chartSize,
                                          painter: MainChartPainter(
                                            candles: _candles,
                                            viewport: _viewport,
                                            cursorPos: _cursorPos,
                                            theme: t,
                                            paths: widget.paths,
                                            activePath: widget.activePath,
                                            ema20: ema20,
                                            ema50: ema50,
                                            ema200: ema200,
                                            syncedCursorRange:
                                                widget.syncedCursorRange,
                                            barDuration:
                                                widget.node.timeframe.duration,
                                            showVolume: widget.node.showVolume,
                                            openPosition: widget.openPosition,
                                            pendingOrders: widget.pendingOrders,
                                            closedTrades: widget.closedTrades,
                                            selectedPathId:
                                                widget.selectedPathId,
                                            selectedPointIndex:
                                                widget.selectedPointIndex,
                                            highlightedRange: hovered != null
                                                ? DateTimeRange(
                                                    start: hovered.time,
                                                    end: hovered.time.add(widget
                                                        .node
                                                        .timeframe
                                                        .duration),
                                                  )
                                                : widget.syncedCursorRange,
                                            displayTimezone:
                                                widget.displayTimezone,
                                          ),
                                        ),
                                        if (hovered != null)
                                          Positioned(
                                            top: 6,
                                            left: 8,
                                            child: IgnorePointer(
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: t.background
                                                      .withValues(alpha: 0.78),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Text(
                                                    '${widget.node.timeframe.label}  '
                                                    'O ${hovered.open.toStringAsFixed(2)}  '
                                                    'H ${hovered.high.toStringAsFixed(2)}  '
                                                    'L ${hovered.low.toStringAsFixed(2)}  '
                                                    'C ${hovered.close.toStringAsFixed(2)}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontFamily: t.fontFamily,
                                                      fontSize: 11,
                                                      color: hovered.close >=
                                                              hovered.open
                                                          ? t.bullBorder
                                                          : t.bearBorder,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(
                            width: priceAxisWidth,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeUpDown,
                              child: GestureDetector(
                                onVerticalDragStart: (_) => setState(
                                    () => _isDraggingPriceAxis = true),
                                onVerticalDragEnd: (_) => setState(
                                    () => _isDraggingPriceAxis = false),
                                onVerticalDragUpdate: _onPriceAxisDragUpdate,
                                onDoubleTap: _onAutoFit,
                                child: ClipRect(
                                  child: CustomPaint(
                                    size: Size(priceAxisWidth, chartH),
                                    painter: PriceAxisPainter(
                                      viewport: _viewport,
                                      cursorPos: _cursorPos,
                                      isActive: _isDraggingPriceAxis,
                                      theme: t,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: timeAxisHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: GestureDetector(
                                onHorizontalDragStart: (_) => setState(
                                    () => _isDraggingTimeAxis = true),
                                onHorizontalDragEnd: (_) => setState(
                                    () => _isDraggingTimeAxis = false),
                                onHorizontalDragUpdate: _onTimeAxisDragUpdate,
                                onDoubleTap: _onResetView,
                                child: ClipRect(
                                  child: CustomPaint(
                                    size: Size(chartW, timeAxisHeight),
                                    painter: TimeAxisPainter(
                                      candles: _candles,
                                      viewport: _viewport,
                                      cursorPos: _cursorPos,
                                      isActive: _isDraggingTimeAxis,
                                      theme: t,
                                      displayTimezone: widget.displayTimezone,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _onAutoFit,
                            child: Container(
                              width: priceAxisWidth,
                              height: timeAxisHeight,
                              decoration: BoxDecoration(
                                color: t.axisBackground,
                                border: Border(
                                  top: BorderSide(color: t.border),
                                  left: BorderSide(color: t.border),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _viewport.autoScaleY ? 'AUTO' : 'FREE',
                                style: TextStyle(
                                  color: _viewport.autoScaleY
                                      ? t.textSecondary
                                      : t.activePillBackground,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: t.fontFamily,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Candle? hovered) {
    final t = widget.theme;
    final n = widget.node;

    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...Timeframe.values.map(
                    (tf) => _PaneHeaderChip(
                      label: tf.label,
                      theme: t,
                      active: widget.node.timeframe == tf,
                      onTap: () => widget.onUpdatePane(
                        widget.node.copyWith(timeframe: tf),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PaneHeaderChip(
                    label: 'E20',
                    active: n.showEma20,
                    theme: t,
                    tooltip: 'Toggle EMA 20',
                    onTap: () => widget.onUpdatePane(
                      n.copyWith(showEma20: !n.showEma20),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PaneHeaderChip(
                    label: 'E50',
                    active: n.showEma50,
                    theme: t,
                    tooltip: 'Toggle EMA 50',
                    onTap: () => widget.onUpdatePane(
                      n.copyWith(showEma50: !n.showEma50),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PaneHeaderChip(
                    label: 'E200',
                    active: n.showEma200,
                    theme: t,
                    tooltip: 'Toggle EMA 200',
                    onTap: () => widget.onUpdatePane(
                      n.copyWith(showEma200: !n.showEma200),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PaneHeaderChip(
                    label: 'Vol',
                    active: n.showVolume,
                    theme: t,
                    tooltip: 'Toggle Volume Histogram',
                    onTap: () => widget.onUpdatePane(
                      n.copyWith(showVolume: !n.showVolume),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PaneHeaderChip(
            label: '◫',
            theme: t,
            onTap: () => widget.onSplit(Axis.horizontal),
            tooltip: 'Split Pane Right',
          ),
          _PaneHeaderChip(
            label: '⊟',
            theme: t,
            onTap: () => widget.onSplit(Axis.vertical),
            tooltip: 'Split Pane Down',
          ),
          if (widget.canClose)
            _PaneHeaderChip(
              label: '✕',
              theme: t,
              onTap: widget.onClose,
              tooltip: 'Close Pane',
            ),
        ],
      ),
    );
  }

}

class _PaneHeaderChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final ChartTheme theme;
  final bool active;
  final String? tooltip;

  const _PaneHeaderChip({
    required this.label,
    required this.onTap,
    required this.theme,
    this.active = false,
    this.tooltip,
  });

  @override
  State<_PaneHeaderChip> createState() => _PaneHeaderChipState();
}

class _PaneHeaderChipState extends State<_PaneHeaderChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final bool active = widget.active;

    final Color fill;
    final Color border;
    final Color textColor;
    final FontWeight weight;

    if (active) {
      fill = t.activePillBackground;
      border = t.activePillBackground;
      textColor = t.activePillText;
      weight = FontWeight.bold;
    } else if (_isHovered) {
      fill = t.activePillBackground.withValues(alpha: 0.14);
      border = t.activePillBackground.withValues(alpha: 0.55);
      textColor = t.textPrimary;
      weight = FontWeight.normal;
    } else {
      fill = t.background;
      border = t.border;
      textColor = t.textSecondary;
      weight = FontWeight.normal;
    }

    final Widget chip = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 0.8),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: t.fontFamily,
              color: textColor,
              fontWeight: weight,
            ),
          ),
        ),
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip == null) return chip;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: chip,
    );
  }
}
