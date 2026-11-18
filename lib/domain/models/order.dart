/// Order direction. Pure-dart domain model (no Flutter imports).
enum OrderSide { buy, sell }

/// How a pending order is expected to trigger relative to the current price.
enum PendingOrderType { limit, stop }

/// Why a position was closed.
enum ExitReason { stopLoss, manualClose, windowEnd }

/// Every mutation recorded against an order or a position, in sequence order.
enum OrderEventType {
  created,
  priceModified,
  filled,
  canceled,
  slSet,
  slModified,
  slRemoved,
  closed,
}

class OrderEvent {
  final int seq;
  final DateTime time;
  final OrderEventType type;
  final double? price;
  final String note;

  const OrderEvent({
    required this.seq,
    required this.time,
    required this.type,
    this.price,
    this.note = '',
  });
}

class SlHistoryEntry {
  final int seq;
  final DateTime time;
  final double? oldSl;
  final double? newSl;
  final String reason;

  const SlHistoryEntry({
    required this.seq,
    required this.time,
    this.oldSl,
    this.newSl,
    this.reason = '',
  });
}

class PendingOrder {
  final String id;
  final OrderSide side;
  final PendingOrderType type;
  final double entryPrice;
  final double? stopLoss;
  final DateTime createdTime;
  final List<OrderEvent> events;

  const PendingOrder({
    required this.id,
    required this.side,
    required this.type,
    required this.entryPrice,
    this.stopLoss,
    required this.createdTime,
    this.events = const [],
  });

  PendingOrder copyWith({
    double? entryPrice,
    double? stopLoss,
    bool clearStopLoss = false,
    List<OrderEvent>? events,
  }) {
    return PendingOrder(
      id: id,
      side: side,
      type: type,
      entryPrice: entryPrice ?? this.entryPrice,
      stopLoss: clearStopLoss ? null : (stopLoss ?? this.stopLoss),
      createdTime: createdTime,
      events: events ?? this.events,
    );
  }
}

class OpenPosition {
  final String id;
  final OrderSide side;
  final double entryPrice;
  final DateTime entryTime;
  final double? initialSl;
  final double? currentSl;
  final double initialRisk;
  final double bestPrice;
  final double worstPrice;
  final List<SlHistoryEntry> slHistory;
  final List<OrderEvent> events;

  const OpenPosition({
    required this.id,
    required this.side,
    required this.entryPrice,
    required this.entryTime,
    this.initialSl,
    this.currentSl,
    required this.initialRisk,
    required this.bestPrice,
    required this.worstPrice,
    this.slHistory = const [],
    this.events = const [],
  });

  OpenPosition copyWith({
    double? currentSl,
    bool clearCurrentSl = false,
    double? bestPrice,
    double? worstPrice,
    List<SlHistoryEntry>? slHistory,
    List<OrderEvent>? events,
  }) {
    return OpenPosition(
      id: id,
      side: side,
      entryPrice: entryPrice,
      entryTime: entryTime,
      initialSl: initialSl,
      currentSl: clearCurrentSl ? null : (currentSl ?? this.currentSl),
      initialRisk: initialRisk,
      bestPrice: bestPrice ?? this.bestPrice,
      worstPrice: worstPrice ?? this.worstPrice,
      slHistory: slHistory ?? this.slHistory,
      events: events ?? this.events,
    );
  }
}

class CompletedTrade {
  final String id;
  final OrderSide side;
  final double entryPrice;
  final DateTime entryTime;
  final double exitPrice;
  final DateTime exitTime;
  final ExitReason exitReason;
  final double? initialSl;
  final double? finalSl;
  final double initialRisk;
  final double pnlPoints;
  final double returnPct;
  final double? realizedR;
  final double? mfeR;
  final double? maeR;
  final List<SlHistoryEntry> slHistory;
  final List<OrderEvent> events;

  const CompletedTrade({
    required this.id,
    required this.side,
    required this.entryPrice,
    required this.entryTime,
    required this.exitPrice,
    required this.exitTime,
    required this.exitReason,
    this.initialSl,
    this.finalSl,
    required this.initialRisk,
    required this.pnlPoints,
    required this.returnPct,
    this.realizedR,
    this.mfeR,
    this.maeR,
    this.slHistory = const [],
    this.events = const [],
  });

  /// Builds a completed trade from a closing [position] using [bestPrice] and
  /// [worstPrice] as the tracked excursions.
  factory CompletedTrade.close({
    required OpenPosition position,
    required double exitPrice,
    required DateTime exitTime,
    required ExitReason exitReason,
  }) {
    final double pnl = position.side == OrderSide.buy
        ? exitPrice - position.entryPrice
        : position.entryPrice - exitPrice;
    final double risk = position.initialRisk;
    final double? realized = risk > 0 ? pnl / risk : null;
    final double? mfe = risk > 0
        ? (position.side == OrderSide.buy
                  ? position.bestPrice - position.entryPrice
                  : position.entryPrice - position.bestPrice) /
              risk
        : null;
    final double? mae = risk > 0
        ? (position.side == OrderSide.buy
                  ? position.entryPrice - position.worstPrice
                  : position.worstPrice - position.entryPrice) /
              risk
        : null;

    return CompletedTrade(
      id: position.id,
      side: position.side,
      entryPrice: position.entryPrice,
      entryTime: position.entryTime,
      exitPrice: exitPrice,
      exitTime: exitTime,
      exitReason: exitReason,
      initialSl: position.initialSl,
      finalSl: position.currentSl,
      initialRisk: risk,
      pnlPoints: pnl,
      returnPct: (pnl / position.entryPrice) * 100.0,
      realizedR: realized,
      mfeR: mfe,
      maeR: mae,
      slHistory: position.slHistory,
      events: [
        ...position.events,
        OrderEvent(
          seq: -1,
          time: exitTime,
          type: OrderEventType.closed,
          price: exitPrice,
          note: exitReason.name,
        ),
      ],
    );
  }

  /// Convenience helper for P&L in points.
  static double computePnl({
    required OrderSide side,
    required double entryPrice,
    required double exitPrice,
  }) {
    return side == OrderSide.buy
        ? exitPrice - entryPrice
        : entryPrice - exitPrice;
  }
}
