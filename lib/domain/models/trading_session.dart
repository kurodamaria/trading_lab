import 'drawing.dart';
import 'order.dart';
import 'timeframe.dart';

/// The kind of change a session introduces relative to its parent hypothesis.
enum SessionChangeType { root, entryFilter, exitRule, oosValidation }

extension SessionChangeTypeX on SessionChangeType {
  /// Compact badge shown on the session node card.
  String get badge {
    switch (this) {
      case SessionChangeType.root:
        return 'ROOT';
      case SessionChangeType.entryFilter:
        return 'FILTER';
      case SessionChangeType.exitRule:
        return 'EXIT';
      case SessionChangeType.oosValidation:
        return 'OOS';
    }
  }

  /// Human-readable label used in dialogs and pickers.
  String get label {
    switch (this) {
      case SessionChangeType.root:
        return 'Root';
      case SessionChangeType.entryFilter:
        return 'Entry Filter';
      case SessionChangeType.exitRule:
        return 'Exit Rule';
      case SessionChangeType.oosValidation:
        return 'OOS Validation';
    }
  }
}

/// An entry trigger inherited from a parent session's completed trades. Forked
/// sessions replay against the same candidate entries so hypotheses can be
/// compared apples-to-apples.
class CandidateEntry {
  final DateTime entryTime;
  final OrderSide side;
  final double referencePrice;

  const CandidateEntry({
    required this.entryTime,
    required this.side,
    required this.referencePrice,
  });

  CandidateEntry copyWith({
    DateTime? entryTime,
    OrderSide? side,
    double? referencePrice,
  }) {
    return CandidateEntry(
      entryTime: entryTime ?? this.entryTime,
      side: side ?? this.side,
      referencePrice: referencePrice ?? this.referencePrice,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entryTime': entryTime.toIso8601String(),
        'side': side.name,
        'referencePrice': referencePrice,
      };

  factory CandidateEntry.fromJson(Map<String, dynamic> json) {
    return CandidateEntry(
      entryTime: DateTime.parse(json['entryTime'] as String),
      side: _enumByName(OrderSide.values, json['side'] as String?, OrderSide.buy),
      referencePrice: (json['referencePrice'] as num).toDouble(),
    );
  }
}

const Object _unset = Object();

/// A single hypothesis-driven replay run arranged as a node on the sessions
/// canvas. Immutable; use [copyWith] to derive updated snapshots.
class TradingSession {
  // Identity & lineage.
  final String id;
  final String? parentId;
  final String name;
  final SessionChangeType changeType;
  final String hypothesis;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Dataset & replay window.
  final String datasetId;
  final String datasetLabel;
  final int windowStartIndex;
  final int windowEndIndex;
  final Timeframe initialCadence;

  // Replay progress & captured state.
  final int cursorIndex;
  final bool isCompleted;
  final List<CandidateEntry> candidateEntries;
  final List<CompletedTrade> closedTrades;
  final OpenPosition? openPosition;
  final List<PendingOrder> pendingOrders;
  final List<CrossTimeframePath> paths;

  // Spatial position on the sessions canvas.
  final double canvasX;
  final double canvasY;

  const TradingSession({
    required this.id,
    this.parentId,
    required this.name,
    required this.changeType,
    this.hypothesis = '',
    required this.createdAt,
    required this.updatedAt,
    required this.datasetId,
    required this.datasetLabel,
    required this.windowStartIndex,
    required this.windowEndIndex,
    this.initialCadence = Timeframe.m15,
    this.cursorIndex = 0,
    this.isCompleted = false,
    this.candidateEntries = const [],
    this.closedTrades = const [],
    this.openPosition,
    this.pendingOrders = const [],
    this.paths = const [],
    this.canvasX = 0.0,
    this.canvasY = 0.0,
  });

  /// Number of bars spanned by the replay window (inclusive).
  int get totalBars {
    final int span = windowEndIndex - windowStartIndex;
    return span < 0 ? 0 : span;
  }

  /// Fraction of the window that has been replayed, clamped to `0..1`.
  double get progressRatio {
    final int span = totalBars;
    if (span == 0) return isCompleted ? 1.0 : 0.0;
    final double r = (cursorIndex - windowStartIndex) / span;
    return r.clamp(0.0, 1.0);
  }

  int get tradeCount => closedTrades.length;

  /// Share of closed trades with positive P&L, in the range `0..1`.
  double get winRate {
    if (closedTrades.isEmpty) return 0.0;
    int wins = 0;
    for (final CompletedTrade t in closedTrades) {
      if (t.pnlPoints > 0) wins++;
    }
    return wins / closedTrades.length;
  }

  /// Sum of realised P&L across all closed trades, in points.
  double get netPnlPoints {
    double sum = 0.0;
    for (final CompletedTrade t in closedTrades) {
      sum += t.pnlPoints;
    }
    return sum;
  }

  TradingSession copyWith({
    String? id,
    Object? parentId = _unset,
    String? name,
    SessionChangeType? changeType,
    String? hypothesis,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? datasetId,
    String? datasetLabel,
    int? windowStartIndex,
    int? windowEndIndex,
    Timeframe? initialCadence,
    int? cursorIndex,
    bool? isCompleted,
    List<CandidateEntry>? candidateEntries,
    List<CompletedTrade>? closedTrades,
    Object? openPosition = _unset,
    List<PendingOrder>? pendingOrders,
    List<CrossTimeframePath>? paths,
    double? canvasX,
    double? canvasY,
  }) {
    return TradingSession(
      id: id ?? this.id,
      parentId: identical(parentId, _unset) ? this.parentId : parentId as String?,
      name: name ?? this.name,
      changeType: changeType ?? this.changeType,
      hypothesis: hypothesis ?? this.hypothesis,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      datasetId: datasetId ?? this.datasetId,
      datasetLabel: datasetLabel ?? this.datasetLabel,
      windowStartIndex: windowStartIndex ?? this.windowStartIndex,
      windowEndIndex: windowEndIndex ?? this.windowEndIndex,
      initialCadence: initialCadence ?? this.initialCadence,
      cursorIndex: cursorIndex ?? this.cursorIndex,
      isCompleted: isCompleted ?? this.isCompleted,
      candidateEntries: candidateEntries ?? this.candidateEntries,
      closedTrades: closedTrades ?? this.closedTrades,
      openPosition: identical(openPosition, _unset)
          ? this.openPosition
          : openPosition as OpenPosition?,
      pendingOrders: pendingOrders ?? this.pendingOrders,
      paths: paths ?? this.paths,
      canvasX: canvasX ?? this.canvasX,
      canvasY: canvasY ?? this.canvasY,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'parentId': parentId,
        'name': name,
        'changeType': changeType.name,
        'hypothesis': hypothesis,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'datasetId': datasetId,
        'datasetLabel': datasetLabel,
        'windowStartIndex': windowStartIndex,
        'windowEndIndex': windowEndIndex,
        'initialCadence': initialCadence.name,
        'cursorIndex': cursorIndex,
        'isCompleted': isCompleted,
        'candidateEntries':
            candidateEntries.map((e) => e.toJson()).toList(),
        'closedTrades': closedTrades.map(_tradeToJson).toList(),
        'openPosition':
            openPosition == null ? null : _positionToJson(openPosition!),
        'pendingOrders': pendingOrders.map(_pendingToJson).toList(),
        'paths': paths.map(_pathToJson).toList(),
        'canvasX': canvasX,
        'canvasY': canvasY,
      };

  factory TradingSession.fromJson(Map<String, dynamic> json) {
    return TradingSession(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String,
      changeType: _enumByName(
        SessionChangeType.values,
        json['changeType'] as String?,
        SessionChangeType.root,
      ),
      hypothesis: (json['hypothesis'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      datasetId: json['datasetId'] as String,
      datasetLabel: json['datasetLabel'] as String,
      windowStartIndex: json['windowStartIndex'] as int,
      windowEndIndex: json['windowEndIndex'] as int,
      initialCadence: _enumByName(
        Timeframe.values,
        json['initialCadence'] as String?,
        Timeframe.m15,
      ),
      cursorIndex: (json['cursorIndex'] as int?) ?? 0,
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      candidateEntries: _list(json['candidateEntries'])
          .map((e) => CandidateEntry.fromJson(e))
          .toList(),
      closedTrades:
          _list(json['closedTrades']).map(_tradeFromJson).toList(),
      openPosition: json['openPosition'] == null
          ? null
          : _positionFromJson(_map(json['openPosition'])),
      pendingOrders:
          _list(json['pendingOrders']).map(_pendingFromJson).toList(),
      paths: _list(json['paths']).map(_pathFromJson).toList(),
      canvasX: (json['canvasX'] as num?)?.toDouble() ?? 0.0,
      canvasY: (json['canvasY'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// -----------------------------------------------------------------------------
// JSON helpers for nested order/path models (which predate JSON support).
// -----------------------------------------------------------------------------

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final T v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

List<Map<String, dynamic>> _list(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Map<String, dynamic> _map(dynamic raw) =>
    Map<String, dynamic>.from(raw as Map);

Map<String, dynamic> _eventToJson(OrderEvent e) => <String, dynamic>{
      'seq': e.seq,
      'time': e.time.toIso8601String(),
      'type': e.type.name,
      'price': e.price,
      'note': e.note,
    };

OrderEvent _eventFromJson(Map<String, dynamic> j) => OrderEvent(
      seq: j['seq'] as int,
      time: DateTime.parse(j['time'] as String),
      type: _enumByName(
        OrderEventType.values,
        j['type'] as String?,
        OrderEventType.created,
      ),
      price: (j['price'] as num?)?.toDouble(),
      note: (j['note'] as String?) ?? '',
    );

Map<String, dynamic> _slToJson(SlHistoryEntry e) => <String, dynamic>{
      'seq': e.seq,
      'time': e.time.toIso8601String(),
      'oldSl': e.oldSl,
      'newSl': e.newSl,
      'reason': e.reason,
    };

SlHistoryEntry _slFromJson(Map<String, dynamic> j) => SlHistoryEntry(
      seq: j['seq'] as int,
      time: DateTime.parse(j['time'] as String),
      oldSl: (j['oldSl'] as num?)?.toDouble(),
      newSl: (j['newSl'] as num?)?.toDouble(),
      reason: (j['reason'] as String?) ?? '',
    );

Map<String, dynamic> _pendingToJson(PendingOrder o) => <String, dynamic>{
      'id': o.id,
      'side': o.side.name,
      'type': o.type.name,
      'entryPrice': o.entryPrice,
      'stopLoss': o.stopLoss,
      'createdTime': o.createdTime.toIso8601String(),
      'events': o.events.map(_eventToJson).toList(),
    };

PendingOrder _pendingFromJson(Map<String, dynamic> j) => PendingOrder(
      id: j['id'] as String,
      side: _enumByName(OrderSide.values, j['side'] as String?, OrderSide.buy),
      type: _enumByName(
        PendingOrderType.values,
        j['type'] as String?,
        PendingOrderType.limit,
      ),
      entryPrice: (j['entryPrice'] as num).toDouble(),
      stopLoss: (j['stopLoss'] as num?)?.toDouble(),
      createdTime: DateTime.parse(j['createdTime'] as String),
      events: _list(j['events']).map(_eventFromJson).toList(),
    );

Map<String, dynamic> _positionToJson(OpenPosition p) => <String, dynamic>{
      'id': p.id,
      'side': p.side.name,
      'entryType': p.entryType.name,
      'entryPrice': p.entryPrice,
      'entryTime': p.entryTime.toIso8601String(),
      'initialSl': p.initialSl,
      'currentSl': p.currentSl,
      'initialRisk': p.initialRisk,
      'bestPrice': p.bestPrice,
      'worstPrice': p.worstPrice,
      'slHistory': p.slHistory.map(_slToJson).toList(),
      'events': p.events.map(_eventToJson).toList(),
    };

OpenPosition _positionFromJson(Map<String, dynamic> j) => OpenPosition(
      id: j['id'] as String,
      side: _enumByName(OrderSide.values, j['side'] as String?, OrderSide.buy),
      entryType: _enumByName(
        EntryType.values,
        j['entryType'] as String?,
        EntryType.market,
      ),
      entryPrice: (j['entryPrice'] as num).toDouble(),
      entryTime: DateTime.parse(j['entryTime'] as String),
      initialSl: (j['initialSl'] as num?)?.toDouble(),
      currentSl: (j['currentSl'] as num?)?.toDouble(),
      initialRisk: (j['initialRisk'] as num).toDouble(),
      bestPrice: (j['bestPrice'] as num).toDouble(),
      worstPrice: (j['worstPrice'] as num).toDouble(),
      slHistory: _list(j['slHistory']).map(_slFromJson).toList(),
      events: _list(j['events']).map(_eventFromJson).toList(),
    );

Map<String, dynamic> _tradeToJson(CompletedTrade t) => <String, dynamic>{
      'id': t.id,
      'side': t.side.name,
      'entryType': t.entryType.name,
      'entryPrice': t.entryPrice,
      'entryTime': t.entryTime.toIso8601String(),
      'exitPrice': t.exitPrice,
      'exitTime': t.exitTime.toIso8601String(),
      'exitReason': t.exitReason.name,
      'initialSl': t.initialSl,
      'finalSl': t.finalSl,
      'initialRisk': t.initialRisk,
      'pnlPoints': t.pnlPoints,
      'returnPct': t.returnPct,
      'realizedR': t.realizedR,
      'mfeR': t.mfeR,
      'maeR': t.maeR,
      'slHistory': t.slHistory.map(_slToJson).toList(),
      'events': t.events.map(_eventToJson).toList(),
    };

CompletedTrade _tradeFromJson(Map<String, dynamic> j) => CompletedTrade(
      id: j['id'] as String,
      side: _enumByName(OrderSide.values, j['side'] as String?, OrderSide.buy),
      entryType: _enumByName(
        EntryType.values,
        j['entryType'] as String?,
        EntryType.market,
      ),
      entryPrice: (j['entryPrice'] as num).toDouble(),
      entryTime: DateTime.parse(j['entryTime'] as String),
      exitPrice: (j['exitPrice'] as num).toDouble(),
      exitTime: DateTime.parse(j['exitTime'] as String),
      exitReason: _enumByName(
        ExitReason.values,
        j['exitReason'] as String?,
        ExitReason.manualClose,
      ),
      initialSl: (j['initialSl'] as num?)?.toDouble(),
      finalSl: (j['finalSl'] as num?)?.toDouble(),
      initialRisk: (j['initialRisk'] as num).toDouble(),
      pnlPoints: (j['pnlPoints'] as num).toDouble(),
      returnPct: (j['returnPct'] as num).toDouble(),
      realizedR: (j['realizedR'] as num?)?.toDouble(),
      mfeR: (j['mfeR'] as num?)?.toDouble(),
      maeR: (j['maeR'] as num?)?.toDouble(),
      slHistory: _list(j['slHistory']).map(_slFromJson).toList(),
      events: _list(j['events']).map(_eventFromJson).toList(),
    );

Map<String, dynamic> _pathToJson(CrossTimeframePath p) => <String, dynamic>{
      'id': p.id,
      'points': p.points
          .map((a) => <String, dynamic>{
                'time': a.time.toIso8601String(),
                'price': a.price,
              })
          .toList(),
    };

CrossTimeframePath _pathFromJson(Map<String, dynamic> j) => CrossTimeframePath(
      id: j['id'] as String,
      points: _list(j['points'])
          .map(
            (a) => ChartAnchor(
              time: DateTime.parse(a['time'] as String),
              price: (a['price'] as num).toDouble(),
            ),
          )
          .toList(),
    );
