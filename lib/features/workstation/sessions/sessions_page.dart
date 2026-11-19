import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/data/binary_candle_store.dart';
import '../../../domain/data/session_store.dart';
import '../../../domain/models/trading_session.dart';
import 'session_dialogs.dart';

/// Interactive 2D "Obsidian canvas" of trading sessions: pan/zoom, draggable
/// session cards, cubic-Bezier lineage connectors, forking and auto-layout.
class SessionsPage extends StatefulWidget {
  final SessionStore store;
  final BinaryCandleStore candleStore;
  final String? activeSessionId;
  final ValueChanged<TradingSession> onOpenSession;
  final VoidCallback? onActiveSessionClosed;
  final ChartTheme theme;

  const SessionsPage({
    super.key,
    required this.store,
    required this.candleStore,
    required this.activeSessionId,
    required this.onOpenSession,
    this.onActiveSessionClosed,
    required this.theme,
  });

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  static const double _cardWidth = SessionStore.cardWidth;
  static const double _cardHeight = SessionStore.cardHeight;
  static const double _minZoom = 0.35;
  static const double _maxZoom = 1.8;

  List<TradingSession> _sessions = <TradingSession>[];
  bool _loading = true;

  Offset _panOffset = Offset.zero;
  double _zoom = 1.0;

  // Arena-free pointer bookkeeping (mirrors ChartPaneWidget discipline).
  final Map<int, Offset> _pointers = <int, Offset>{};
  Offset? _panStartPointer;
  Offset _panStartOffset = Offset.zero;
  double? _pinchStartDistance;
  double _pinchStartZoom = 1.0;

  // Card drag.
  String? _draggingId;
  Offset? _dragPointerStart;
  Offset _dragCardStart = Offset.zero;
  bool _dragMoved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SessionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      _load();
    }
  }

  Future<void> _load() async {
    final List<TradingSession> list = await widget.store.loadAll();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Coordinate helpers
  // ---------------------------------------------------------------------------

  Offset _toWorld(Offset screen) => (screen - _panOffset) / _zoom;

  TradingSession? _sessionById(String id) {
    for (final TradingSession s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  bool _hasChildren(String id) =>
      _sessions.any((s) => s.parentId == id);

  String? _hitTestCard(Offset screen) {
    final Offset world = _toWorld(screen);
    for (int i = _sessions.length - 1; i >= 0; i--) {
      final TradingSession s = _sessions[i];
      final Rect r = Rect.fromLTWH(s.canvasX, s.canvasY, _cardWidth, _cardHeight);
      if (r.contains(world)) return s.id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pointer handling
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      final bool secondary = e.buttons == kSecondaryMouseButton;
      final String? hit = _hitTestCard(e.localPosition);
      if (hit != null && !secondary) {
        final TradingSession? s = _sessionById(hit);
        if (s != null) {
          _draggingId = hit;
          _dragPointerStart = e.localPosition;
          _dragCardStart = Offset(s.canvasX, s.canvasY);
          _dragMoved = false;
          return;
        }
      }
      _panStartPointer = e.localPosition;
      _panStartOffset = _panOffset;
    } else if (_pointers.length == 2) {
      _draggingId = null;
      final List<Offset> pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartZoom = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length >= 2 && _pinchStartDistance != null) {
      final List<Offset> pts = _pointers.values.toList();
      final double d = (pts[0] - pts[1]).distance;
      if (_pinchStartDistance! > 0 && d > 0) {
        _applyZoom(
          _pinchStartZoom * d / _pinchStartDistance!,
          (pts[0] + pts[1]) / 2,
        );
      }
      return;
    }

    final String? dragging = _draggingId;
    if (dragging != null) {
      final Offset delta = (e.localPosition - _dragPointerStart!) / _zoom;
      if (delta.distance > 2) _dragMoved = true;
      _setSessionPosition(dragging, _dragCardStart + delta);
      return;
    }

    final Offset? start = _panStartPointer;
    if (start != null) {
      setState(() => _panOffset = _panStartOffset + (e.localPosition - start));
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
    if (_pointers.isEmpty) {
      _panStartPointer = null;
      _pinchStartDistance = null;
      final String? dragging = _draggingId;
      _draggingId = null;
      if (dragging != null && _dragMoved) {
        _persistPosition(dragging);
      }
      _dragMoved = false;
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final double factor = math.exp(-e.scrollDelta.dy * 0.0015);
      _applyZoom(_zoom * factor, e.localPosition);
    }
  }

  void _applyZoom(double target, Offset focal) {
    final double z = target.clamp(_minZoom, _maxZoom);
    if (z == _zoom) return;
    final Offset world = (focal - _panOffset) / _zoom;
    setState(() {
      _zoom = z;
      _panOffset = focal - world * z;
    });
  }

  void _setSessionPosition(String id, Offset canvas) {
    setState(() {
      _sessions = _sessions
          .map(
            (s) => s.id == id
                ? s.copyWith(canvasX: canvas.dx, canvasY: canvas.dy)
                : s,
          )
          .toList();
    });
  }

  Future<void> _persistPosition(String id) async {
    final TradingSession? s = _sessionById(id);
    if (s == null) return;
    await widget.store.upsert(s);
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  List<DatasetOption> _datasetOptions() {
    final List<DatasetOption> options = <DatasetOption>[
      const DatasetOption(
        id: 'synthetic',
        label: 'Synthetic 30k',
        barCount: 30000,
      ),
    ];
    for (final m in widget.candleStore.listDatasets()) {
      options.add(
        DatasetOption(id: m.sha256, label: m.name, barCount: m.barCount),
      );
    }
    return options;
  }

  Future<void> _createRootSession() async {
    final RootSessionRequest? req = await showDialog<RootSessionRequest>(
      context: context,
      builder: (_) => NewRootSessionDialog(
        theme: widget.theme,
        datasets: _datasetOptions(),
      ),
    );
    if (req == null) return;

    final DateTime now = DateTime.now();
    double maxX = SessionStore.originX;
    for (final TradingSession s in _sessions) {
      if (s.canvasX > maxX) maxX = s.canvasX;
    }

    final TradingSession session = TradingSession(
      id: 'ses-${now.microsecondsSinceEpoch}',
      name: req.name,
      changeType: SessionChangeType.root,
      hypothesis: '',
      createdAt: now,
      updatedAt: now,
      datasetId: req.dataset.id,
      datasetLabel: req.dataset.label,
      windowStartIndex: req.windowStartIndex,
      windowEndIndex: req.windowEndIndex,
      initialCadence: req.cadence,
      cursorIndex: req.windowStartIndex,
      canvasX: _sessions.isEmpty
          ? SessionStore.originX
          : maxX + _cardWidth + SessionStore.horizontalGap,
      canvasY: SessionStore.originY,
    );

    await widget.store.upsert(session);
    if (!mounted) return;
    setState(() => _sessions = <TradingSession>[..._sessions, session]);
  }

  Future<void> _forkSession(TradingSession parent) async {
    final ForkRequest? req = await showDialog<ForkRequest>(
      context: context,
      builder: (_) => ForkSessionDialog(theme: widget.theme, parent: parent),
    );
    if (req == null) return;

    final DateTime now = DateTime.now();
    double deepest = parent.canvasY;
    for (final TradingSession s in _sessions) {
      if (s.parentId == parent.id && s.canvasY > deepest) deepest = s.canvasY;
    }

    final TradingSession child = TradingSession(
      id: 'ses-${now.microsecondsSinceEpoch}',
      parentId: parent.id,
      name: req.name,
      changeType: req.changeType,
      hypothesis: req.hypothesis,
      createdAt: now,
      updatedAt: now,
      datasetId: parent.datasetId,
      datasetLabel: parent.datasetLabel,
      windowStartIndex: parent.windowStartIndex,
      windowEndIndex: parent.windowEndIndex,
      initialCadence: parent.initialCadence,
      cursorIndex: parent.windowStartIndex,
      candidateEntries: parent.closedTrades
          .map(
            (t) => CandidateEntry(
              entryTime: t.entryTime,
              side: t.side,
              referencePrice: t.entryPrice,
            ),
          )
          .toList(),
      canvasX: parent.canvasX,
      canvasY: deepest + _cardHeight + SessionStore.verticalGap,
    );

    await widget.store.upsert(child);
    if (!mounted) return;
    setState(() => _sessions = <TradingSession>[..._sessions, child]);
  }

  Future<void> _deleteSession(TradingSession session) async {
    if (_hasChildren(session.id)) return;
    final bool ok = await confirmDeleteSession(
      context,
      theme: widget.theme,
      name: session.name,
    );
    if (!ok || !mounted) return;
    await widget.store.deleteLeaf(session.id);
    if (!mounted) return;
    setState(
      () => _sessions =
          _sessions.where((s) => s.id != session.id).toList(),
    );
    if (widget.activeSessionId == session.id) {
      widget.onActiveSessionClosed?.call();
    }
  }

  Future<void> _autoLayout() async {
    if (_sessions.isEmpty) return;
    final List<TradingSession> arranged =
        widget.store.autoLayout(_sessions);
    setState(() => _sessions = arranged);
    await widget.store.saveAll(arranged);
  }

  void _resetView() {
    setState(() {
      _zoom = 1.0;
      _panOffset = Offset.zero;
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;

    return Container(
      color: t.background,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        onPointerSignal: _onPointerSignal,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SessionCanvasPainter(
                      sessions: _sessions,
                      panOffset: _panOffset,
                      zoom: _zoom,
                      theme: t,
                      activeSessionId: widget.activeSessionId,
                      draggingId: _draggingId,
                    ),
                  ),
                ),
              ),
              // World-space layer: cards are always laid out at their fixed
              // 248x148 size and the whole layer is pan/zoom transformed, so
              // card-internal layout never scales with `_zoom`.
              Positioned.fill(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translateByDouble(
                      _panOffset.dx,
                      _panOffset.dy,
                      0.0,
                      1.0,
                    )
                    ..scaleByDouble(_zoom, _zoom, 1.0, 1.0),
                  transformHitTests: true,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: _cardWidgets(),
                  ),
                ),
              ),
              if (!_loading && _sessions.isEmpty) _emptyHint(t),
              Positioned(left: 12, top: 12, child: _overlayBar(t)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _cardWidgets() {
    final List<Widget> widgets = <Widget>[];
    for (final TradingSession s in _sessions) {
      if (s.id == _draggingId) continue;
      widgets.add(_positionedCard(s));
    }
    final String? dragging = _draggingId;
    if (dragging != null) {
      final TradingSession? s = _sessionById(dragging);
      if (s != null) widgets.add(_positionedCard(s));
    }
    return widgets;
  }

  Widget _positionedCard(TradingSession s) {
    return Positioned(
      left: s.canvasX,
      top: s.canvasY,
      child: SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: _SessionCard(
          session: s,
          theme: widget.theme,
          active: s.id == widget.activeSessionId,
          isLeaf: !_hasChildren(s.id),
          onOpen: () => widget.onOpenSession(s),
          onFork: s.isCompleted ? () => _forkSession(s) : null,
          onDelete: () => _deleteSession(s),
        ),
      ),
    );
  }

  Widget _emptyHint(ChartTheme t) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Text(
            'No sessions yet — click "+ New Root Session" to start.',
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayBar(ChartTheme t) {
    final int total = _sessions.length;
    final TradingSession? active =
        widget.activeSessionId == null ? null : _sessionById(widget.activeSessionId!);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _overlayButton(
            t,
            '+ New Root Session',
            primary: true,
            onTap: _createRootSession,
          ),
          const SizedBox(width: 8),
          _overlayButton(t, 'Auto-Layout', onTap: _autoLayout),
          const SizedBox(width: 8),
          _overlayButton(t, 'Reset View (100%)', onTap: _resetView),
          const SizedBox(width: 12),
          _statusPill(t, '$total session${total == 1 ? '' : 's'}'),
          if (active != null) ...[
            const SizedBox(width: 8),
            _statusPill(t, 'Active: ${active.name}'),
          ],
        ],
      ),
    );
  }

  Widget _overlayButton(
    ChartTheme t,
    String label, {
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? t.activePillText : t.textPrimary,
        backgroundColor: primary ? t.activePillBackground : t.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: primary
            ? BorderSide.none
            : BorderSide(color: t.border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: t.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _statusPill(ChartTheme t, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.background,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.textSecondary,
          fontFamily: t.fontFamily,
          fontSize: 11,
        ),
      ),
    );
  }
}

// =============================================================================
// Session node card
// =============================================================================

class _SessionCard extends StatefulWidget {
  final TradingSession session;
  final ChartTheme theme;
  final bool active;
  final bool isLeaf;
  final VoidCallback onOpen;
  final VoidCallback? onFork;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.theme,
    required this.active,
    required this.isLeaf,
    required this.onOpen,
    required this.onFork,
    required this.onDelete,
  });

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final TradingSession s = widget.session;
    final double pnl = s.netPnlPoints;
    final Color borderColor = widget.active
        ? t.activePillBackground
        : (_hovered ? t.textSecondary : t.border);

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: t.background,
          border: Border.all(
            color: borderColor,
            width: widget.active ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontFamily: t.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _tagPill(t, s.changeType),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.hypothesis.isNotEmpty ? s.hypothesis : s.datasetLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 10,
                height: 1.25,
              ),
            ),
            const Spacer(),
            _progressRow(t, s),
            const SizedBox(height: 5),
            _metricsRow(t, s, pnl),
            const SizedBox(height: 6),
            _footer(t),
          ],
        ),
      ),
    );
  }

  Widget _tagPill(ChartTheme t, SessionChangeType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: t.badgeBackground,
      child: Text(
        type.badge,
        style: TextStyle(
          color: t.badgeText,
          fontFamily: t.fontFamily,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _progressRow(ChartTheme t, TradingSession s) {
    final bool done = s.isCompleted;
    final String label = done
        ? 'Completed'
        : 'Bar ${s.cursorIndex} / ${s.windowEndIndex}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: t.gridLine)),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: s.progressRatio,
                  child: ColoredBox(
                    color: done ? t.activePillBackground : t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricsRow(ChartTheme t, TradingSession s, double pnl) {
    final bool lowSample = s.isCompleted && s.tradeCount < 30;
    final Color pnlColor = pnl >= 0
        ? t.pendingBuyBackground
        : t.pendingSellBackground;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '${s.tradeCount} trades',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: _metricStyle(t),
                ),
              ),
              if (lowSample) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  color: t.pendingSellBackground,
                  child: Text(
                    'N<30',
                    style: TextStyle(
                      color: t.pendingSellText,
                      fontFamily: t.fontFamily,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Win ${(s.winRate * 100).toStringAsFixed(0)}%',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: _metricStyle(t),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Net ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: pnlColor,
              fontFamily: t.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _metricStyle(ChartTheme t) => TextStyle(
        color: t.textSecondary,
        fontFamily: t.fontFamily,
        fontSize: 10,
      );

  Widget _footer(ChartTheme t) {
    return Row(
      children: [
        _cardButton(t, 'Open', onTap: widget.onOpen, primary: true),
        const SizedBox(width: 6),
        Tooltip(
          message: widget.onFork == null
              ? 'Complete parent session before forking'
              : 'Fork this hypothesis',
          child: _cardButton(
            t,
            'Fork',
            onTap: widget.onFork,
          ),
        ),
        const Spacer(),
        if (widget.isLeaf)
          Tooltip(
            message: 'Delete leaf session',
            child: InkWell(
              onTap: widget.onDelete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: t.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardButton(
    ChartTheme t,
    String label, {
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    final bool enabled = onTap != null;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 22),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: primary ? t.activePillText : t.textPrimary,
        backgroundColor: primary ? t.activePillBackground : t.background,
        disabledForegroundColor: t.textSecondary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        side: primary
            ? BorderSide.none
            : BorderSide(
                color: enabled ? t.border : t.gridLine,
                width: 1,
              ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: t.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// =============================================================================
// Canvas painter: dot grid + cubic-Bezier lineage connectors
// =============================================================================

class _SessionCanvasPainter extends CustomPainter {
  final List<TradingSession> sessions;
  final Offset panOffset;
  final double zoom;
  final ChartTheme theme;
  final String? activeSessionId;
  final String? draggingId;

  _SessionCanvasPainter({
    required this.sessions,
    required this.panOffset,
    required this.zoom,
    required this.theme,
    required this.activeSessionId,
    required this.draggingId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintConnectors(canvas);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final double spacing = 32.0 * zoom;
    if (spacing < 6) return;
    final Paint dot = Paint()..color = theme.gridLine;
    double startX = panOffset.dx % spacing;
    if (startX > 0) startX -= spacing;
    double startY = panOffset.dy % spacing;
    if (startY > 0) startY -= spacing;
    for (double x = startX; x <= size.width; x += spacing) {
      for (double y = startY; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  Rect _screenRect(TradingSession s) => Rect.fromLTWH(
        s.canvasX * zoom + panOffset.dx,
        s.canvasY * zoom + panOffset.dy,
        SessionStore.cardWidth * zoom,
        SessionStore.cardHeight * zoom,
      );

  void _paintConnectors(Canvas canvas) {
    final Map<String, TradingSession> byId = <String, TradingSession>{
      for (final TradingSession s in sessions) s.id: s,
    };
    for (final TradingSession child in sessions) {
      final TradingSession? parent =
          child.parentId == null ? null : byId[child.parentId];
      if (parent == null) continue;

      final Rect pr = _screenRect(parent);
      final Rect cr = _screenRect(child);
      final Offset from = Offset(pr.center.dx, pr.bottom);
      final Offset to = Offset(cr.center.dx, cr.top);
      final double dy = (to.dy - from.dy).abs().clamp(24.0, 200.0);
      final bool hot = child.id == draggingId ||
          child.id == activeSessionId ||
          parent.id == activeSessionId;
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hot ? 2.0 : 1.4
        ..color = (hot ? theme.activePillBackground : theme.pathColor)
            .withValues(alpha: hot ? 0.9 : 0.55);

      final Path path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(
          from.dx,
          from.dy + dy,
          to.dx,
          to.dy - dy,
          to.dx,
          to.dy,
        );
      canvas.drawPath(path, paint);
      canvas.drawCircle(
        to,
        2.5,
        Paint()..color = theme.pathColor.withValues(alpha: hot ? 0.9 : 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SessionCanvasPainter old) {
    return !identical(old.sessions, sessions) ||
        old.panOffset != panOffset ||
        old.zoom != zoom ||
        old.activeSessionId != activeSessionId ||
        old.draggingId != draggingId;
  }
}
