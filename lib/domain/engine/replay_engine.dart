import 'dart:collection';

import '../models/candle.dart';
import '../models/order.dart';
import '../models/timeframe.dart';

/// Deterministic bar-by-bar replay over a chronologically sorted 1m series.
/// Pure Dart: no Flutter imports.
class ReplayEngine {
  ReplayEngine({
    required List<Candle> base1mCandles,
    required int initialCursorIndex,
    int? maxCursorIndex,
  })  : _candles = base1mCandles,
        _minCursorIndex = initialCursorIndex,
        _cursorIndex = initialCursorIndex,
        _maxCursorIndex =
            maxCursorIndex ?? (base1mCandles.length - 1) {
    if (base1mCandles.isEmpty) {
      throw ArgumentError('base1mCandles must not be empty');
    }
    if (initialCursorIndex < 0 || initialCursorIndex >= base1mCandles.length) {
      throw ArgumentError('initialCursorIndex out of range');
    }
    if (_maxCursorIndex < _cursorIndex ||
        _maxCursorIndex >= base1mCandles.length) {
      throw ArgumentError('maxCursorIndex out of range');
    }
  }

  /// Rebuilds an engine from a persisted session snapshot: a candle slice,
  /// cursor position, and any captured open position, pending orders, and
  /// closed trades.
  factory ReplayEngine.restore({
    required List<Candle> base1mCandles,
    required int initialCursorIndex,
    int? maxCursorIndex,
    OpenPosition? openPosition,
    List<PendingOrder>? pendingOrders,
    List<CompletedTrade>? closedTrades,
    bool isCompleted = false,
  }) {
    final ReplayEngine engine = ReplayEngine(
      base1mCandles: base1mCandles,
      initialCursorIndex: initialCursorIndex,
      maxCursorIndex: maxCursorIndex,
    );
    engine._openPosition = openPosition;
    engine._pendingOrders.addAll(pendingOrders ?? const <PendingOrder>[]);
    engine._closedTrades.addAll(closedTrades ?? const <CompletedTrade>[]);
    engine._isCompleted = isCompleted;

    // Advance the id / event counters past any restored identifiers so new
    // orders and events never collide with persisted ones.
    final List<String> ids = <String>[
      if (openPosition != null) openPosition.id,
      for (final PendingOrder o in engine._pendingOrders) o.id,
      for (final CompletedTrade t in engine._closedTrades) t.id,
    ];
    engine._orderIdCounter = _maxIdSuffix(ids) + 1;

    int maxSeq = -1;
    void scan(Iterable<OrderEvent> events) {
      for (final OrderEvent e in events) {
        if (e.seq > maxSeq) maxSeq = e.seq;
      }
    }

    if (openPosition != null) scan(openPosition.events);
    for (final PendingOrder o in engine._pendingOrders) {
      scan(o.events);
    }
    for (final CompletedTrade t in engine._closedTrades) {
      scan(t.events);
    }
    engine._eventSeq = maxSeq + 1;

    return engine;
  }

  static int _maxIdSuffix(List<String> ids) {
    int max = -1;
    for (final String id in ids) {
      final int dash = id.lastIndexOf('-');
      if (dash < 0 || dash + 1 >= id.length) continue;
      final int? v = int.tryParse(id.substring(dash + 1));
      if (v != null && v > max) max = v;
    }
    return max;
  }

  final List<Candle> _candles;
  final int _minCursorIndex;
  final int _maxCursorIndex;

  int _cursorIndex;
  bool _isCompleted = false;

  OpenPosition? _openPosition;
  final List<PendingOrder> _pendingOrders = [];
  final List<CompletedTrade> _closedTrades = [];

  int _eventSeq = 0;
  int _orderIdCounter = 0;
  int _lastClosedExitIndex = -1;

  // ---------------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------------
  int get cursorIndex => _cursorIndex;
  int get minCursorIndex => _minCursorIndex;
  int get maxCursorIndex => _maxCursorIndex;
  Candle get currentBar => _candles[_cursorIndex];
  DateTime get currentTime => currentBar.time;

  List<Candle> get visibleBase1mCandles =>
      UnmodifiableListView(_candles.sublist(0, _cursorIndex + 1));

  bool get isCompleted => _isCompleted;
  OpenPosition? get openPosition => _openPosition;
  List<PendingOrder> get pendingOrders => UnmodifiableListView(_pendingOrders);
  List<CompletedTrade> get closedTrades =>
      UnmodifiableListView(_closedTrades);
  int get eventSeq => _eventSeq;

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------
  int stepForward(Timeframe cadence, {int steps = 1}) {
    final int oldCursor = _cursorIndex;
    final int target = oldCursor + steps * cadence.minutes;
    final int clampedTarget = target > _maxCursorIndex ? _maxCursorIndex : target;

    while (_cursorIndex < clampedTarget) {
      final int next = _cursorIndex + 1;
      _processBar(_candles[next], next);
      _cursorIndex = next;
      if (_isCompleted) break;
    }

    if (_cursorIndex >= _maxCursorIndex && !_isCompleted) {
      _finalizeAtEnd();
    }

    return _cursorIndex - oldCursor;
  }

  /// Fast-forwards toward [targetTime], stopping [leadBars] bars before the
  /// first bar at/after it so the caller can react in real time. Pending orders
  /// and stop-losses are evaluated for every skipped bar. Returns `true` if the
  /// cursor actually advanced.
  bool jumpToTime(DateTime targetTime, {int leadBars = 2}) {
    if (_isCompleted) return false;

    int targetIndex = _maxCursorIndex;
    for (int i = _cursorIndex; i <= _maxCursorIndex; i++) {
      if (!_candles[i].time.isBefore(targetTime)) {
        targetIndex = i;
        break;
      }
    }

    int target = targetIndex - leadBars;
    final int minTarget = _cursorIndex + 1;
    if (target < minTarget) target = minTarget;
    if (target > _maxCursorIndex) target = _maxCursorIndex;
    if (target <= _cursorIndex) return false;

    while (_cursorIndex < target) {
      final int next = _cursorIndex + 1;
      _processBar(_candles[next], next);
      _cursorIndex = next;
      if (_isCompleted) break;
    }
    if (_cursorIndex >= _maxCursorIndex && !_isCompleted) {
      _finalizeAtEnd();
    }
    return true;
  }

  bool canStepBack(Timeframe cadence, {int steps = 1}) {
    if (_isCompleted) return false;
    if (_openPosition != null) return false;
    final int targetIndex = _cursorIndex - steps * cadence.minutes;
    if (targetIndex < _minCursorIndex) return false;
    if (_closedTrades.isNotEmpty && targetIndex < _lastClosedExitIndex) {
      return false;
    }
    return true;
  }

  bool stepBack(Timeframe cadence, {int steps = 1}) {
    if (!canStepBack(cadence, steps: steps)) return false;
    _cursorIndex -= steps * cadence.minutes;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Orders
  // ---------------------------------------------------------------------------
  OpenPosition executeMarketOrder({
    required OrderSide side,
    double? stopLoss,
  }) {
    if (_isCompleted) {
      throw StateError('Replay is completed');
    }
    if (_openPosition != null) {
      throw StateError('A position is already open');
    }
    _cancelAllPending(note: 'Canceled on market entry');

    final double entry = currentBar.close;
    final double risk = stopLoss != null ? (entry - stopLoss).abs() : 0.0;

    final position = OpenPosition(
      id: 'pos-${_orderIdCounter++}',
      side: side,
      entryPrice: entry,
      entryTime: currentTime,
      initialSl: stopLoss,
      currentSl: stopLoss,
      initialRisk: risk,
      bestPrice: entry,
      worstPrice: entry,
      events: [
        _evt(currentTime, OrderEventType.filled,
            price: entry, note: 'Market entry'),
        if (stopLoss != null)
          _evt(currentTime, OrderEventType.slSet,
              price: stopLoss, note: 'Initial SL'),
      ],
    );
    _openPosition = position;
    return position;
  }

  PendingOrder placePendingOrder({
    required OrderSide side,
    required double price,
    double? stopLoss,
  }) {
    if (_isCompleted) {
      throw StateError('Replay is completed');
    }
    if (_openPosition != null) {
      throw StateError('A position is already open');
    }
    final PendingOrderType type = _resolveType(side, price);
    final order = PendingOrder(
      id: 'ord-${_orderIdCounter++}',
      side: side,
      type: type,
      entryPrice: price,
      stopLoss: stopLoss,
      createdTime: currentTime,
      events: [
        _evt(currentTime, OrderEventType.created,
            price: price, note: type.name),
      ],
    );
    _pendingOrders.add(order);
    return order;
  }

  void updatePendingOrderPrice(String orderId, double newPrice) {
    final int idx = _pendingOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    final PendingOrder order = _pendingOrders[idx];
    final PendingOrderType type = _resolveType(order.side, newPrice);
    _pendingOrders[idx] = PendingOrder(
      id: order.id,
      side: order.side,
      type: type,
      entryPrice: newPrice,
      stopLoss: order.stopLoss,
      createdTime: order.createdTime,
      events: [
        ...order.events,
        _evt(currentTime, OrderEventType.priceModified,
            price: newPrice, note: type.name),
      ],
    );
  }

  void cancelPendingOrder(String orderId) {
    final int idx = _pendingOrders.indexWhere((o) => o.id == orderId);
    if (idx == -1) return;
    final PendingOrder order = _pendingOrders[idx];
    _pendingOrders[idx] = PendingOrder(
      id: order.id,
      side: order.side,
      type: order.type,
      entryPrice: order.entryPrice,
      stopLoss: order.stopLoss,
      createdTime: order.createdTime,
      events: [
        ...order.events,
        _evt(currentTime, OrderEventType.canceled, price: order.entryPrice),
      ],
    );
    _pendingOrders.removeAt(idx);
  }

  // ---------------------------------------------------------------------------
  // Stop-loss management
  // ---------------------------------------------------------------------------
  void updateStopLoss(double newSl) {
    final OpenPosition? pos = _openPosition;
    if (pos == null) {
      throw StateError('No open position');
    }
    _eventSeq++;
    final entry = SlHistoryEntry(
      seq: _eventSeq,
      time: currentTime,
      oldSl: pos.currentSl,
      newSl: newSl,
      reason: 'SL updated',
    );
    _openPosition = pos.copyWith(
      currentSl: newSl,
      slHistory: [...pos.slHistory, entry],
      events: [
        ...pos.events,
        _evt(currentTime, OrderEventType.slModified, price: newSl),
      ],
    );
  }

  void removeStopLoss() {
    final OpenPosition? pos = _openPosition;
    if (pos == null) {
      throw StateError('No open position');
    }
    _eventSeq++;
    final entry = SlHistoryEntry(
      seq: _eventSeq,
      time: currentTime,
      oldSl: pos.currentSl,
      newSl: null,
      reason: 'SL removed',
    );
    _openPosition = pos.copyWith(
      clearCurrentSl: true,
      slHistory: [...pos.slHistory, entry],
      events: [...pos.events, _evt(currentTime, OrderEventType.slRemoved)],
    );
  }

  CompletedTrade closePositionManually() {
    final OpenPosition? pos = _openPosition;
    if (pos == null) {
      throw StateError('No open position');
    }
    return _closeAt(
      exitPrice: currentBar.close,
      exitTime: currentTime,
      reason: ExitReason.manualClose,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------
  PendingOrderType _resolveType(OrderSide side, double price) {
    final double last = currentBar.close;
    if (side == OrderSide.buy) {
      return price < last ? PendingOrderType.limit : PendingOrderType.stop;
    }
    return price > last ? PendingOrderType.limit : PendingOrderType.stop;
  }

  OrderEvent _evt(
    DateTime time,
    OrderEventType type, {
    double? price,
    String note = '',
  }) {
    return OrderEvent(
      seq: _eventSeq++,
      time: time,
      type: type,
      price: price,
      note: note,
    );
  }

  void _cancelAllPending({required String note}) {
    if (_pendingOrders.isEmpty) return;
    for (int i = 0; i < _pendingOrders.length; i++) {
      final PendingOrder order = _pendingOrders[i];
      _pendingOrders[i] = PendingOrder(
        id: order.id,
        side: order.side,
        type: order.type,
        entryPrice: order.entryPrice,
        stopLoss: order.stopLoss,
        createdTime: order.createdTime,
        events: [
          ...order.events,
          _evt(currentTime, OrderEventType.canceled,
              price: order.entryPrice, note: note),
        ],
      );
    }
    _pendingOrders.clear();
  }

  /// Closes any open position at the window's final close and cancels leftover
  /// pending orders, marking the replay complete.
  void _finalizeAtEnd() {
    if (_openPosition != null) {
      _closeAt(
        exitPrice: currentBar.close,
        exitTime: currentBar.time,
        reason: ExitReason.windowEnd,
      );
    }
    _cancelAllPending(note: 'Window end');
    _isCompleted = true;
  }

  void _processBar(Candle bar, int index) {
    final OpenPosition? pos = _openPosition;
    if (pos != null) {
      final double best = pos.side == OrderSide.buy
          ? (bar.high > pos.bestPrice ? bar.high : pos.bestPrice)
          : (bar.low < pos.bestPrice ? bar.low : pos.bestPrice);
      final double worst = pos.side == OrderSide.buy
          ? (bar.low < pos.worstPrice ? bar.low : pos.worstPrice)
          : (bar.high > pos.worstPrice ? bar.high : pos.worstPrice);
      _openPosition = pos.copyWith(bestPrice: best, worstPrice: worst);

      final double? sl = pos.currentSl;
      if (sl != null) {
        final bool hit = pos.side == OrderSide.buy
            ? bar.low <= sl
            : bar.high >= sl;
        if (hit) {
          _closeAt(
            exitPrice: sl,
            exitTime: bar.time,
            reason: ExitReason.stopLoss,
            exitIndex: index,
          );
        }
      }
      return;
    }

    if (_pendingOrders.isEmpty) return;

    PendingOrder? filled;
    int filledIndex = -1;
    for (int i = 0; i < _pendingOrders.length; i++) {
      final PendingOrder o = _pendingOrders[i];
      final bool isLimit = o.type == PendingOrderType.limit;
      bool triggers;
      if (o.side == OrderSide.buy) {
        triggers = isLimit ? bar.low <= o.entryPrice : bar.high >= o.entryPrice;
      } else {
        triggers = isLimit ? bar.high >= o.entryPrice : bar.low <= o.entryPrice;
      }
      if (triggers) {
        filled = o;
        filledIndex = i;
        break;
      }
    }

    if (filled == null) return;

    final PendingOrder order = filled;
    final double entry = order.entryPrice;
    final double risk =
        order.stopLoss != null ? (entry - order.stopLoss!).abs() : 0.0;

    final OpenPosition position = OpenPosition(
      id: 'pos-${_orderIdCounter++}',
      side: order.side,
      entryPrice: entry,
      entryTime: bar.time,
      initialSl: order.stopLoss,
      currentSl: order.stopLoss,
      initialRisk: risk,
      bestPrice: entry,
      worstPrice: entry,
      events: [
        ...order.events,
        _evt(bar.time, OrderEventType.filled,
            price: entry, note: order.type.name),
        if (order.stopLoss != null)
          _evt(bar.time, OrderEventType.slSet, price: order.stopLoss!),
      ],
    );
    _openPosition = position;

    // Cancel all remaining pending orders.
    _pendingOrders.removeAt(filledIndex);
    _cancelAllPending(note: 'Canceled on fill');

    // Evaluate whether the SL triggers on this same bar after the fill.
    final double? sl = position.currentSl;
    if (sl != null) {
      final bool hit =
          position.side == OrderSide.buy ? bar.low <= sl : bar.high >= sl;
      if (hit) {
        _closeAt(
          exitPrice: sl,
          exitTime: bar.time,
          reason: ExitReason.stopLoss,
          exitIndex: index,
        );
      }
    }
  }

  CompletedTrade _closeAt({
    required double exitPrice,
    required DateTime exitTime,
    required ExitReason reason,
    int? exitIndex,
  }) {
    final OpenPosition pos = _openPosition!;
    final CompletedTrade trade = CompletedTrade.close(
      position: pos,
      exitPrice: exitPrice,
      exitTime: exitTime,
      exitReason: reason,
    );
    _closedTrades.add(trade);
    _openPosition = null;
    _lastClosedExitIndex = exitIndex ?? _cursorIndex;
    return trade;
  }
}
