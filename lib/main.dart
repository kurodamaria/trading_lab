import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/theme/chart_theme.dart';
import 'domain/data/binary_candle_store.dart';
import 'domain/data/session_store.dart';
import 'domain/engine/replay_engine.dart';
import 'domain/engine/telemetry_calculator.dart';
import 'domain/models/candle.dart';
import 'domain/models/display_timezone.dart';
import 'domain/models/drawing.dart';
import 'domain/models/order.dart';
import 'domain/models/timeframe.dart';
import 'domain/models/trading_session.dart';
import 'features/workstation/data/datasets_page.dart';
import 'features/workstation/sessions/sessions_page.dart';
import 'features/workstation/settings/settings_page.dart';
import 'features/workstation/stats/stats_page.dart';
import 'features/workstation/tiling/tiling_node.dart';
import 'features/workstation/tiling/tiling_tree_view.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: ChartScreen()),
  );
}

// ============================================================================
// MULTI-PANE CHART WORKSTATION
// ============================================================================
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  static const Duration baseBarStep = Duration(minutes: 1);

  static const ChartTheme _theme = ChartTheme.nytNewsprint;

  List<Candle>? _base1mCandles;
  ReplayEngine? _replayEngine;
  List<Candle> _visibleBase1mCandles = const <Candle>[];

  BinaryCandleStore? _candleStore;
  late SessionStore _sessionStore;
  String? _activeSessionId;
  TradingSession? _activeSession;
  TradingSession? _parentSession;
  TradingSession? _latestResumableSession;
  Timer? _sessionSaveTimer;

  Timeframe _replayCadence = Timeframe.m15;
  OrderSide? _pendingPlacementSide;

  final FocusNode _keyboardFocusNode = FocusNode();

  int _selectedPageIndex = 1;

  DisplayTimezone _displayTimezone = DisplayTimezone.utcPlus8;

  @override
  void dispose() {
    _sessionSaveTimer?.cancel();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // Tiling tree: default 2-pane horizontal split (15m | 1h).
  late TilingNode _rootNode;

  // Shared cross-pane state
  bool _isDrawingPath = false;
  final List<CrossTimeframePath> _paths = [];
  CrossTimeframePath? _activePath;
  int _nextPathId = 0;
  DateTimeRange? _syncedCursorRange;
  String? _selectedPathId;
  int? _selectedPointIndex;

  @override
  void initState() {
    super.initState();
    _initDatasetStore();
    _sessionStore = SessionStore(
      Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}trading_lab_sessions',
      ),
    );

    final Size viewSize =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final double logicalWidth =
        viewSize.width / WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final Axis initialDirection =
        logicalWidth < 600 ? Axis.vertical : Axis.horizontal;

    _rootNode = SplitNode(
      id: 'root-split',
      direction: initialDirection,
      ratio: 0.5,
      first: const PaneNode(id: 'pane-left', timeframe: Timeframe.m15),
      second: const PaneNode(id: 'pane-right', timeframe: Timeframe.h1),
    );
  }

  /// Lazily materializes the synthetic dataset only when a session references
  /// it, so the app no longer boots a 30,000-bar sandbox.
  List<Candle> _syntheticCandles() {
    return _base1mCandles ??= _generateBase1mCandles(30000);
  }

  List<Candle> _generateBase1mCandles(int count) {
    final rng = Random(42);
    final list = <Candle>[];
    double price = 100.0;
    // Start `count` 1-minute bars ago.
    DateTime t = DateTime(2026, 11, 16, 9, 30);

    for (int i = 0; i < count; i++) {
      final change = (rng.nextDouble() - 0.49) * 2.5;
      final open = price;
      final close = max(10.0, open + change);
      final high = max(open, close) + rng.nextDouble() * 1.5;
      final low = min(open, close) - rng.nextDouble() * 1.5;
      final volume = (100.0 + (high - low) * 250.0) * (0.6 + rng.nextDouble() * 0.8);
      list.add(
        Candle(
          index: i,
          time: t,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ),
      );
      price = close;
      t = t.add(baseBarStep);
    }
    return list;
  }

  // --------------------------------------------------------------------------
  // PATH DRAWING
  // --------------------------------------------------------------------------
  void _togglePathDrawing() {
    setState(() {
      _isDrawingPath = !_isDrawingPath;
      if (!_isDrawingPath) {
        _activePath = null;
        _selectedPathId = null;
        _selectedPointIndex = null;
      }
    });
  }

  void _updatePathPoint(String pathId, int pointIndex, ChartAnchor newAnchor) {
    setState(() {
      for (int p = 0; p < _paths.length; p++) {
        final CrossTimeframePath path = _paths[p];
        if (path.id != pathId) continue;
        if (pointIndex < 0 || pointIndex >= path.points.length) return;
        final List<ChartAnchor> pts = List<ChartAnchor>.from(path.points);
        pts[pointIndex] = newAnchor;
        _paths[p] = CrossTimeframePath(id: path.id, points: pts);
        return;
      }
    });
    _scheduleSessionSave();
  }

  void _deleteSelectedPathOrPoint() {
    final String? selId = _selectedPathId;
    if (selId == null) return;
    setState(() {
      final int idx = _paths.indexWhere((p) => p.id == selId);
      if (idx != -1) {
        final CrossTimeframePath path = _paths[idx];
        final int? selPoint = _selectedPointIndex;
        if (selPoint == null) {
          _paths.removeAt(idx);
        } else if (selPoint == 0 || selPoint == path.points.length - 1) {
          final List<ChartAnchor> remaining =
              List<ChartAnchor>.from(path.points)..removeAt(selPoint);
          if (remaining.length >= 2) {
            _paths[idx] = CrossTimeframePath(id: path.id, points: remaining);
          } else {
            _paths.removeAt(idx);
          }
        } else {
          final List<ChartAnchor> left =
              List<ChartAnchor>.from(path.points.sublist(0, selPoint));
          final List<ChartAnchor> right =
              List<ChartAnchor>.from(path.points.sublist(selPoint + 1));
          bool kept = false;
          if (left.length >= 2) {
            _paths[idx] = CrossTimeframePath(id: path.id, points: left);
            kept = true;
          }
          if (right.length >= 2) {
            final CrossTimeframePath split = CrossTimeframePath(
              id: 'path-${_nextPathId++}',
              points: right,
            );
            if (kept) {
              _paths.insert(idx + 1, split);
            } else {
              _paths[idx] = split;
              kept = true;
            }
          }
          if (!kept) {
            _paths.removeAt(idx);
          }
        }
      }
      _selectedPathId = null;
      _selectedPointIndex = null;
    });
    _scheduleSessionSave();
  }

  void _addPathPoint(ChartAnchor anchor) {
    setState(() {
      _activePath = _activePath == null
          ? CrossTimeframePath(id: 'path-${_nextPathId++}', points: [anchor])
          : (CrossTimeframePath(
              id: _activePath!.id,
              points: [..._activePath!.points, anchor],
            ));
    });
    _scheduleSessionSave();
  }

  void _finishActivePath() {
    setState(() {
      if (_activePath != null && _activePath!.points.length >= 2) {
        _paths.add(_activePath!);
      }
      _activePath = null;
      _isDrawingPath = false;
    });
    _scheduleSessionSave();
  }

  // --------------------------------------------------------------------------
  // TILING OPERATIONS
  // --------------------------------------------------------------------------
  void _cycleTimezoneQuick() {
    setState(() {
      _displayTimezone = _displayTimezone == DisplayTimezone.utc
          ? DisplayTimezone.utcPlus8
          : DisplayTimezone.utc;
    });
  }

  void _onTreeChanged(TilingNode newNode) {
    setState(() => _rootNode = newNode);
  }

  // --------------------------------------------------------------------------
  // REPLAY & EXECUTION
  // --------------------------------------------------------------------------
  static const List<Timeframe> _cadenceOrder = [
    Timeframe.m1,
    Timeframe.m5,
    Timeframe.m15,
    Timeframe.h1,
  ];

  void _stepForward({int steps = 1}) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() {
      engine.stepForward(_replayCadence, steps: steps);
      _refreshVisibleCandles();
    });
    _scheduleSessionSave();
  }

  void _stepBack() {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() {
      engine.stepBack(_replayCadence);
      _refreshVisibleCandles();
    });
    _scheduleSessionSave();
  }

  void _refreshVisibleCandles() {
    final ReplayEngine? engine = _replayEngine;
    _visibleBase1mCandles = engine == null
        ? const <Candle>[]
        : engine.visibleBase1mCandles.toList();
  }

  void _cycleCadence() {
    setState(() {
      final int i = _cadenceOrder.indexOf(_replayCadence);
      _replayCadence = _cadenceOrder[(i + 1) % _cadenceOrder.length];
    });
  }

  void _marketEntry(OrderSide side) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    final double close = engine.currentBar.close;
    setState(() {
      engine.executeMarketOrder(
        side: side,
        stopLoss: side == OrderSide.buy ? close - 3.0 : close + 3.0,
      );
    });
    _scheduleSessionSave();
  }

  void _placePending(OrderSide side, double price) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() {
      engine.placePendingOrder(
        side: side,
        price: price,
        stopLoss: side == OrderSide.buy ? price - 3.0 : price + 3.0,
      );
      _pendingPlacementSide = null;
    });
    _scheduleSessionSave();
  }

  void _closePosition() {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() => engine.closePositionManually());
    _scheduleSessionSave();
  }

  void _removeStopLoss() {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() => engine.removeStopLoss());
    _scheduleSessionSave();
  }

  void _updateSl(double price) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() => engine.updateStopLoss(price));
    _scheduleSessionSave();
  }

  void _updatePendingPrice(String orderId, double price) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    setState(() => engine.updatePendingOrderPrice(orderId, price));
    _scheduleSessionSave();
  }

  void _copyCsv() {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return;
    Clipboard.setData(
      ClipboardData(
        text: TelemetryCalculator.exportTradesCsv(engine.closedTrades),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trades CSV copied to clipboard')),
    );
  }

  // --------------------------------------------------------------------------
  // DATASET LIBRARY
  // --------------------------------------------------------------------------
  Future<void> _initDatasetStore() async {
    try {
      final Directory support = await getApplicationSupportDirectory();
      final Directory dir = Directory(
        '${support.path}${Platform.pathSeparator}datasets',
      );
      final Directory sessionsDir = Directory(
        '${support.path}${Platform.pathSeparator}sessions',
      );
      final BinaryCandleStore candleStore = BinaryCandleStore(dir);
      final SessionStore sessionStore = SessionStore(sessionsDir);
      final List<TradingSession> sessions = await sessionStore.loadAll();
      final String? lastId = await sessionStore.loadLastActiveSessionId();

      TradingSession? matched;
      if (lastId != null) {
        for (final TradingSession s in sessions) {
          if (s.id == lastId) {
            matched = s;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _candleStore = candleStore;
        _sessionStore = sessionStore;
        _latestResumableSession = _mostRecent(sessions);
        if (sessions.isEmpty) _selectedPageIndex = 1;
      });

      if (matched != null) {
        await _openSession(matched, switchToPractice: false);
      }
    } catch (_) {
      // Keep the synthetic fallback if the platform dir is unavailable.
    }
  }

  TradingSession? _mostRecent(List<TradingSession> sessions) {
    TradingSession? best;
    for (final TradingSession s in sessions) {
      if (best == null || s.updatedAt.isAfter(best.updatedAt)) {
        best = s;
      }
    }
    return best;
  }

  void _resumeLatestSession() {
    final TradingSession? session = _latestResumableSession;
    if (session == null) return;
    _openSession(session);
  }

  void _closeActiveSession() {
    if (_activeSession == null && _replayEngine == null) return;
    setState(() {
      _activeSession = null;
      _parentSession = null;
      _activeSessionId = null;
      _replayEngine = null;
      _visibleBase1mCandles = const <Candle>[];
      _paths.clear();
      _activePath = null;
      _selectedPathId = null;
      _selectedPointIndex = null;
      _isDrawingPath = false;
      _pendingPlacementSide = null;
    });
    _sessionStore.saveLastActiveSessionId(null);
  }

  Future<void> _openSession(
    TradingSession session, {
    bool switchToPractice = true,
  }) async {
    final int start = session.windowStartIndex;

    late List<Candle> slice;
    late int originIndex;
    if (session.datasetId == 'synthetic' || _candleStore == null) {
      final List<Candle> base = _syntheticCandles();
      originIndex = start.clamp(0, base.length - 1);
      final int end = session.windowEndIndex.clamp(originIndex, base.length - 1);
      slice = base.sublist(originIndex, end + 1);
    } else {
      try {
        final int s0 = start < 0 ? 0 : start;
        final List<Candle> raw = _candleStore!.readRange(
          session.datasetId,
          startIndex: s0,
          count: (session.windowEndIndex - s0 + 1).clamp(1, 1 << 30),
        );
        if (raw.isEmpty) {
          slice = _syntheticCandles();
          originIndex = 0;
        } else {
          slice = raw;
          originIndex = s0;
        }
      } catch (_) {
        slice = _syntheticCandles();
        originIndex = 0;
      }
    }

    final int cursor =
        (session.cursorIndex - originIndex).clamp(0, slice.length - 1);
    final ReplayEngine engine = ReplayEngine.restore(
      base1mCandles: slice,
      initialCursorIndex: cursor,
      maxCursorIndex: slice.length - 1,
      openPosition: session.openPosition,
      pendingOrders: session.pendingOrders,
      closedTrades: session.closedTrades,
      canceledOrders: session.canceledOrders,
      isCompleted: session.isCompleted,
    );

    TradingSession? parent;
    final String? parentId = session.parentId;
    if (parentId != null) {
      try {
        final List<TradingSession> all = await _sessionStore.loadAll();
        for (final TradingSession s in all) {
          if (s.id == parentId) {
            parent = s;
            break;
          }
        }
      } catch (_) {
        // Parent lookup is best-effort.
      }
    }

    if (!mounted) return;
    setState(() {
      _replayEngine = engine;
      _activeSession = session;
      _parentSession = parent;
      _activeSessionId = session.id;
      _latestResumableSession = session;
      _replayCadence = session.initialCadence;
      _paths
        ..clear()
        ..addAll(session.paths);
      _nextPathId = _paths.length;
      _activePath = null;
      _selectedPathId = null;
      _selectedPointIndex = null;
      _isDrawingPath = false;
      _pendingPlacementSide = null;
      _refreshVisibleCandles();
      if (switchToPractice) _selectedPageIndex = 2;
    });
    _sessionStore.saveLastActiveSessionId(session.id);
    _scheduleSessionSave();
  }

  // --------------------------------------------------------------------------
  // SESSION AUTO-SAVE
  // --------------------------------------------------------------------------
  void _scheduleSessionSave() {
    if (_activeSession == null) return;
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(
      const Duration(milliseconds: 350),
      _persistActiveSession,
    );
  }

  Future<void> _persistActiveSession() async {
    final TradingSession? session = _activeSession;
    final ReplayEngine? engine = _replayEngine;
    if (session == null || engine == null) return;
    final TradingSession updated = session.copyWith(
      cursorIndex: engine.cursorIndex,
      isCompleted: engine.isCompleted,
      closedTrades: List<CompletedTrade>.from(engine.closedTrades),
      openPosition: engine.openPosition,
      pendingOrders: List<PendingOrder>.from(engine.pendingOrders),
      canceledOrders: List<CanceledOrder>.from(engine.canceledOrders),
      paths: List<CrossTimeframePath>.from(_paths),
      updatedAt: DateTime.now(),
    );
    _activeSession = updated;
    _latestResumableSession = updated;
    await _sessionStore.upsert(updated);
  }

  // --------------------------------------------------------------------------
  // NEXT CANDIDATE ENTRY
  // --------------------------------------------------------------------------
  int _nextEntryIndex() {
    final TradingSession? session = _activeSession;
    final ReplayEngine? engine = _replayEngine;
    if (session == null || engine == null) return -1;
    final DateTime now = engine.currentBar.time;
    final List<CandidateEntry> entries = session.candidateEntries;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i].entryTime.isAfter(now)) return i;
    }
    return -1;
  }

  void _jumpToNextEntry() {
    final TradingSession? session = _activeSession;
    final ReplayEngine? engine = _replayEngine;
    final int idx = _nextEntryIndex();
    if (session == null || engine == null || idx < 0) return;
    final bool advanced =
        engine.jumpToTime(session.candidateEntries[idx].entryTime);
    if (!advanced) return;
    setState(_refreshVisibleCandles);
    _scheduleSessionSave();
  }

  @override
  Widget build(BuildContext context) {
    final t = _theme;
    final ReplayEngine? engine = _replayEngine;
    final bool hasSession = _activeSession != null && engine != null;

    final Widget practice = hasSession
        ? Column(
            children: [
              _buildTopToolbar(),
              Expanded(
                child: TilingTreeView(
                  node: _rootNode,
                  base1mCandles: _visibleBase1mCandles,
                  theme: t,
                  isDrawingPath: _isDrawingPath,
                  paths: _paths,
                  activePath: _activePath,
                  syncedCursorRange: _syncedCursorRange,
                  canClose: _rootNode is SplitNode,
                  onTreeChanged: _onTreeChanged,
                  onHoverRangeChanged: (range) =>
                      setState(() => _syncedCursorRange = range),
                  onAddPathPoint: _addPathPoint,
                  onFinishPath: _finishActivePath,
                  openPosition: engine.openPosition,
                  pendingOrders: engine.pendingOrders,
                  closedTrades: engine.closedTrades,
                  pendingPlacementSide: _pendingPlacementSide,
                  onPlacePendingOrder: _placePending,
                  onUpdateSl: _updateSl,
                  onUpdatePendingPrice: _updatePendingPrice,
                  onCancelPendingOrder: (orderId) {
                    setState(() => engine.cancelPendingOrder(orderId));
                    _scheduleSessionSave();
                  },
                  selectedPathId: _selectedPathId,
                  selectedPointIndex: _selectedPointIndex,
                  onSelectPath: (pathId, pointIndex) => setState(() {
                    _selectedPathId = pathId;
                    _selectedPointIndex = pointIndex;
                  }),
                  onUpdatePathPoint: _updatePathPoint,
                  onFocusRequested: _keyboardFocusNode.requestFocus,
                  onClosePosition: _closePosition,
                  onRemoveSl: _removeStopLoss,
                  displayTimezone: _displayTimezone,
                ),
              ),
            ],
          )
        : NoActiveSessionView(
            theme: t,
            onOpenSessions: () => setState(() => _selectedPageIndex = 1),
            onResumeLatest: _latestResumableSession == null
                ? null
                : _resumeLatestSession,
            latestSessionName: _latestResumableSession?.name,
          );

    final Widget content = Focus(
      autofocus: true,
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: _onKeyEvent,
        child: Row(
          children: [
            _navRail(t),
            Expanded(
              child: IndexedStack(
                index: _selectedPageIndex,
                children: [
                  DatasetsPage(
                    store: _candleStore ??
                        BinaryCandleStore(Directory.systemTemp),
                    theme: t,
                    displayTimezone: _displayTimezone,
                  ),
                  SessionsPage(
                    store: _sessionStore,
                    candleStore: _candleStore ??
                        BinaryCandleStore(Directory.systemTemp),
                    activeSessionId: _activeSessionId,
                    onOpenSession: _openSession,
                    onActiveSessionClosed: _closeActiveSession,
                    theme: t,
                  ),
                  practice,
                  StatsPage(
                    replayEngine: _replayEngine,
                    theme: t,
                    onCopyCsv: _copyCsv,
                    displayTimezone: _displayTimezone,
                    activeSession: _activeSession,
                    parentSession: _parentSession,
                    onOpenSessions: () =>
                        setState(() => _selectedPageIndex = 1),
                    onResumeLatest: _latestResumableSession == null
                        ? null
                        : _resumeLatestSession,
                    latestSessionName: _latestResumableSession?.name,
                  ),
                  SettingsPage(
                    theme: t,
                    selected: _displayTimezone,
                    onChanged: (tz) => setState(() => _displayTimezone = tz),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: t.background,
      body: content,
    );
  }

  Widget _navRail(ChartTheme t) {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border(right: BorderSide(color: t.border, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
            _NavRailItem(
              label: 'Datasets',
              icon: Icons.storage_outlined,
              theme: t,
              active: _selectedPageIndex == 0,
              onTap: () => setState(() => _selectedPageIndex = 0),
            ),
            const SizedBox(height: 4),
            _NavRailItem(
              label: 'Sessions',
              icon: Icons.history_toggle_off,
              theme: t,
              active: _selectedPageIndex == 1,
              onTap: () => setState(() => _selectedPageIndex = 1),
            ),
            const SizedBox(height: 4),
            _NavRailItem(
              label: 'Practice',
              icon: Icons.candlestick_chart,
              theme: t,
              active: _selectedPageIndex == 2,
              onTap: () => setState(() => _selectedPageIndex = 2),
            ),
            const SizedBox(height: 4),
            _NavRailItem(
              label: 'Stats',
              icon: Icons.insert_chart_outlined,
              theme: t,
              active: _selectedPageIndex == 3,
              onTap: () => setState(() => _selectedPageIndex = 3),
            ),
            const Spacer(),
            _NavRailItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              theme: t,
              active: _selectedPageIndex == 4,
              onTap: () => setState(() => _selectedPageIndex = 4),
            ),
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_activeSession == null || _replayEngine == null) return;
    if (_selectedPageIndex != 2) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _stepForward();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _stepBack();
    } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
      final bool shift = HardwareKeyboard.instance.isShiftPressed;
      final OrderSide target = shift ? OrderSide.sell : OrderSide.buy;
      setState(() {
        _pendingPlacementSide =
            _pendingPlacementSide == target ? null : target;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete ||
        event.physicalKey == PhysicalKeyboardKey.backspace ||
        event.physicalKey == PhysicalKeyboardKey.delete) {
      _deleteSelectedPathOrPoint();
    } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
      _togglePathDrawing();
    } else if (event.logicalKey == LogicalKeyboardKey.keyN) {
      _jumpToNextEntry();
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_pendingPlacementSide != null) {
        setState(() => _pendingPlacementSide = null);
      } else if (_isDrawingPath) {
        _finishActivePath();
      }
    }
  }

  Widget _buildTopToolbar() {
    final t = _theme;
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return const SizedBox.shrink();
    final int nextEntry = _nextEntryIndex();
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Text(
            'K-LINE ENGINE',
            style: TextStyle(
              color: t.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          _sessionBadge(t),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _toolbarButton(
                    label: _replayCadence.label,
                    onTap: _cycleCadence,
                    highlighted: true,
                    tooltip:
                        'Replay Step Cadence (click to cycle 1m / 5m / 15m / 1h)',
                  ),
                  const SizedBox(width: 6),
                  _toolbarButton(
                    label: '◀',
                    onTap: _stepBack,
                    tooltip: 'Step Back 1 Bar (←)',
                  ),
                  const SizedBox(width: 6),
                  _toolbarButton(
                    label: '▶',
                    onTap: _stepForward,
                    tooltip: 'Step Forward 1 Bar (→)',
                  ),
                  const SizedBox(width: 6),
                  _toolbarButton(
                    label: '+5▶',
                    onTap: () => _stepForward(steps: 5),
                    tooltip: 'Step Forward 5 Bars',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${engine.cursorIndex - engine.minCursorIndex}'
                    '/${engine.maxCursorIndex - engine.minCursorIndex}',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 11,
                      fontFamily: t.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (nextEntry >= 0) ...[
                    _toolbarButton(
                      label: 'Next Entry (${nextEntry + 1})',
                      onTap: _jumpToNextEntry,
                      highlighted: true,
                      tooltip: 'Fast-forward to next candidate entry (N)',
                    ),
                    const SizedBox(width: 16),
                  ],
                  ..._buildExecutionCluster(t),
                  const SizedBox(width: 16),
                  _toolbarButton(
                    label: _isDrawingPath ? '✎ Path (P) [ON]' : '✎ Path (P)',
                    onTap: _togglePathDrawing,
                    highlighted: _isDrawingPath,
                    tooltip:
                        'Draw Cross-Timeframe Path (P to toggle, Esc to finish)',
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onSecondaryTap: _cycleTimezoneQuick,
            child: _toolbarButton(
              label: _displayTimezone.shortLabel,
              onTap: () => setState(() => _selectedPageIndex = 4),
              tooltip: 'Display Timezone (click to configure in Settings)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sessionBadge(ChartTheme t) {
    final TradingSession? s = _activeSession;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.background,
          border: Border.all(color: t.border, width: 1),
        ),
        child: Text(
          'Sandbox',
          style: TextStyle(
            color: t.textSecondary,
            fontFamily: t.fontFamily,
            fontSize: 11,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: t.background,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: t.badgeBackground,
            child: Text(
              s.changeType.badge,
              style: TextStyle(
                color: t.badgeText,
                fontFamily: t.fontFamily,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              s.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textPrimary,
                fontFamily: t.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildExecutionCluster(ChartTheme t) {
    final ReplayEngine? engine = _replayEngine;
    if (engine == null) return const <Widget>[];
    final OpenPosition? pos = engine.openPosition;
    if (pos != null) {
      final double close = engine.currentBar.close;
      final double pnl = pos.side == OrderSide.buy
          ? close - pos.entryPrice
          : pos.entryPrice - close;
      return [
        Text(
          'PnL ${pnl.toStringAsFixed(2)}',
          style: TextStyle(
            color: pnl >= 0 ? t.bullBorder : t.bearBorder,
            fontSize: 11,
            fontFamily: t.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        _toolbarButton(
          label: 'Close',
          onTap: _closePosition,
          tooltip: 'Close Open Position at Market',
        ),
        const SizedBox(width: 6),
        _toolbarButton(
          label: 'NoSL',
          onTap: _removeStopLoss,
          tooltip: 'Remove Stop-Loss',
        ),
      ];
    }

    if (engine.isCompleted) {
      return [
        Text(
          'Session complete',
          style: TextStyle(color: t.textSecondary, fontSize: 11),
        ),
      ];
    }

    return [
      _toolbarButton(
        label: 'Buy',
        onTap: () => _marketEntry(OrderSide.buy),
        tooltip: 'Market Buy (with default SL)',
      ),
      const SizedBox(width: 6),
      _toolbarButton(
        label: 'Sell',
        onTap: () => _marketEntry(OrderSide.sell),
        tooltip: 'Market Sell (with default SL)',
      ),
      const SizedBox(width: 6),
      _toolbarButton(
        label: 'PBuy',
        highlighted: _pendingPlacementSide == OrderSide.buy,
        onTap: () => setState(() {
          _pendingPlacementSide = _pendingPlacementSide == OrderSide.buy
              ? null
              : OrderSide.buy;
        }),
        tooltip:
            'Pending Buy — click chart to place Limit (below) or Stop (above) [L]',
      ),
      const SizedBox(width: 6),
      _toolbarButton(
        label: 'PSell',
        highlighted: _pendingPlacementSide == OrderSide.sell,
        onTap: () => setState(() {
          _pendingPlacementSide = _pendingPlacementSide == OrderSide.sell
              ? null
              : OrderSide.sell;
        }),
        tooltip:
            'Pending Sell — click chart to place Limit (above) or Stop (below) [Shift+L]',
      ),
    ];
  }

  Widget _toolbarButton({
    required String label,
    required VoidCallback onTap,
    bool highlighted = false,
    String? tooltip,
  }) {
    return _ToolbarButton(
      label: label,
      onTap: onTap,
      theme: _theme,
      highlighted: highlighted,
      tooltip: tooltip,
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final ChartTheme theme;
  final bool highlighted;
  final String? tooltip;

  const _ToolbarButton({
    required this.label,
    required this.onTap,
    required this.theme,
    required this.highlighted,
    this.tooltip,
  });

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final bool highlighted = widget.highlighted;

    final Color fill;
    final Color border;
    final Color textColor;
    final FontWeight weight;

    if (highlighted) {
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

    final Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontFamily: t.fontFamily,
              fontWeight: weight,
            ),
          ),
        ),
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip == null) return button;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: button,
    );
  }
}

class _NavRailItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final ChartTheme theme;
  final bool active;
  final VoidCallback onTap;

  const _NavRailItem({
    required this.label,
    required this.icon,
    required this.theme,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final bool active = widget.active;
    final bool highlight = active || _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: highlight
                ? t.activePillBackground.withValues(alpha: 0.14)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: active ? t.activePillBackground : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: active ? t.activePillBackground : t.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? t.textPrimary : t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
