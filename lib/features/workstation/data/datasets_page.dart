import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/data/binary_candle_store.dart';
import '../../../domain/data/dataset_metadata.dart';
import '../../../domain/models/candle.dart';
import '../../../domain/models/display_timezone.dart';
import '../../../domain/models/drawing.dart';
import '../../../domain/models/timeframe.dart';
import '../tiling/tiling_node.dart';
import '../tiling/tiling_tree_view.dart';

/// Full-screen dataset library page: import CSVs, browse cached `.bin`
/// datasets, inspect them in a read-only multi-timeframe view, and delete
/// them with protected-deletion confirmation.
class DatasetsPage extends StatefulWidget {
  final BinaryCandleStore store;
  final ChartTheme theme;
  final DisplayTimezone displayTimezone;

  const DatasetsPage({
    super.key,
    required this.store,
    required this.theme,
    this.displayTimezone = DisplayTimezone.utc,
  });

  @override
  State<DatasetsPage> createState() => _DatasetsPageState();
}

class _DatasetsPageState extends State<DatasetsPage> {
  static const int windowSize = 250000;

  List<DatasetMetadata> _datasets = const <DatasetMetadata>[];
  bool _importing = false;
  String? _error;

  // Read-only inspection state.
  DatasetMetadata? _inspecting;
  List<Candle> _inspectCandles = const <Candle>[];
  int _windowStart = 0;
  late TilingNode _inspectRoot;
  DateTimeRange? _inspectCursorRange;
  final List<ChartAnchor> _inspectPathAnchors = <ChartAnchor>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DatasetsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  void _refresh() {
    setState(() => _datasets = widget.store.listDatasets());
  }

  Future<void> _import() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['csv', 'txt'],
    );
    if (picked.isEmpty) return;
    final String? path = picked.first.path;
    if (path == null) return;

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      await widget.store.importCsvFile(path);
      _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(DatasetMetadata meta) async {
    try {
      widget.store.deleteDataset(meta.sha256);
      _refresh();
    } on DatasetInUseException catch (e) {
      final bool? force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: widget.theme.axisBackground,
          title: Text(
            'Dataset In Use',
            style: TextStyle(
              color: widget.theme.textPrimary,
              fontFamily: widget.theme.fontFamily,
            ),
          ),
          content: Text(
            'This dataset is referenced by ${e.sessionIds.length} session(s). '
            'Force delete anyway?',
            style: TextStyle(
              color: widget.theme.textPrimary,
              fontFamily: widget.theme.fontFamily,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: widget.theme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Force Delete',
                style: TextStyle(color: widget.theme.pendingSellBackground),
              ),
            ),
          ],
        ),
      );
      if (force == true) {
        widget.store.deleteDataset(meta.sha256, force: true);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    if (_inspecting != null) {
      return _inspectView(t);
    }
    final int totalMb =
        _datasets.fold<int>(0, (sum, m) => sum + m.binSizeBytes) ~/ (1024 * 1024);

    return Container(
      color: t.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerBar(t, totalMb),
          if (_importing) _importingBar(t),
          if (_error != null) _errorBar(t),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(t, 'DATASET CATALOG'),
                  const SizedBox(height: 8),
                  _catalog(t),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBar(ChartTheme t, int totalMb) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DATASET LIBRARY',
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_datasets.length} cached dataset${_datasets.length == 1 ? '' : 's'}'
                ' · $totalMb MB on disk',
                style: TextStyle(
                  color: t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          _ActionPill(
            theme: t,
            label: 'Import CSV...',
            onTap: _importing ? null : _import,
          ),
        ],
      ),
    );
  }

  Widget _importingBar(ChartTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Converting CSV…',
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBar(ChartTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        _error!,
        style: TextStyle(
          color: t.pendingSellBackground,
          fontFamily: t.fontFamily,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _sectionTitle(ChartTheme t, String text) {
    return Text(
      text,
      style: TextStyle(
        color: t.textPrimary,
        fontFamily: t.fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _catalog(ChartTheme t) {
    if (_datasets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: t.axisBackground,
          border: Border.all(color: t.border, width: 1),
        ),
        child: Text(
          'No datasets yet — import a CSV to begin.',
          style: TextStyle(color: t.textSecondary, fontFamily: t.fontFamily),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double tableWidth = math.max(constraints.maxWidth, 820);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                color: t.axisBackground,
                border: Border.all(color: t.border, width: 1),
              ),
              child: Column(
                children: [
                  _rowHeader(t),
                  ..._datasets.map((m) => _row(t, m)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _rowHeader(ChartTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _cell(t, 'NAME', bold: true)),
          Expanded(flex: 2, child: _cell(t, 'SHA-256', bold: true)),
          Expanded(flex: 1, child: _cell(t, 'BARS', bold: true)),
          Expanded(flex: 3, child: _cell(t, 'RANGE', bold: true)),
          Expanded(flex: 1, child: _cell(t, 'SIZE', bold: true)),
          Expanded(flex: 2, child: _cell(t, 'STATUS', bold: true)),
          SizedBox(
            width: 156,
            child: Align(
              alignment: Alignment.centerRight,
              child: _cell(t, 'ACTIONS', bold: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ChartTheme t, DatasetMetadata m) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.gridLine, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              m.name,
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
          Expanded(flex: 2, child: _cell(t, m.sha256.substring(0, 12))),
          Expanded(flex: 1, child: _cell(t, '${m.barCount}')),
          Expanded(
            flex: 3,
            child: _cell(
              t,
              '${_fmt(m.firstTime)} → ${_fmt(m.lastTime)}',
              color: t.textSecondary,
            ),
          ),
          Expanded(
            flex: 1,
            child: _cell(
              t,
              '${(m.binSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
            ),
          ),
          Expanded(
            flex: 2,
            child: _cell(
              t,
              m.sessionIds.isNotEmpty
                  ? 'Locked: ${m.sessionIds.length} sessions'
                  : 'Unlocked',
              color: m.sessionIds.isNotEmpty
                  ? t.pendingSellBackground
                  : t.textSecondary,
            ),
          ),
          SizedBox(
            width: 156,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionPill(
                    theme: t,
                    label: 'Inspect',
                    onTap: () => _openInspect(m),
                  ),
                  const SizedBox(width: 6),
                  _ActionPill(
                    theme: t,
                    label: 'Delete',
                    secondary: true,
                    onTap: () => _delete(m),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Read-only inspection
  // ---------------------------------------------------------------------------
  void _openInspect(DatasetMetadata m) {
    final int start = m.barCount <= windowSize ? 0 : m.barCount - windowSize;
    final int count = math.min(windowSize, m.barCount - start);
    final List<Candle> candles =
        widget.store.readRange(m.sha256, startIndex: start, count: count);
    setState(() {
      _inspecting = m;
      _windowStart = start;
      _inspectCandles = candles;
      _inspectCursorRange = null;
      _inspectRoot = SplitNode(
        id: 'inspect-root',
        direction: Axis.horizontal,
        ratio: 0.5,
        first: const PaneNode(id: 'inspect-left', timeframe: Timeframe.m15),
        second: const PaneNode(id: 'inspect-right', timeframe: Timeframe.h1),
      );
      _inspectPathAnchors.clear();
    });
  }

  void _shiftInspectWindow(int delta) {
    final DatasetMetadata? m = _inspecting;
    if (m == null) return;
    final int maxStart =
        m.barCount <= windowSize ? 0 : m.barCount - windowSize;
    final int newStart = (_windowStart + delta).clamp(0, maxStart);
    final int count = math.min(windowSize, m.barCount - newStart);
    final List<Candle> candles =
        widget.store.readRange(m.sha256, startIndex: newStart, count: count);
    setState(() {
      _windowStart = newStart;
      _inspectCandles = candles;
      _inspectCursorRange = null;
    });
  }

  void _closeInspect() {
    setState(() {
      _inspecting = null;
      _inspectCandles = const <Candle>[];
      _inspectCursorRange = null;
      _inspectPathAnchors.clear();
    });
  }

  Widget _inspectView(ChartTheme t) {
    final DatasetMetadata meta = _inspecting!;
    final int maxStart = meta.barCount <= windowSize ? 0 : meta.barCount - windowSize;
    final bool canPrev = _windowStart > 0;
    final bool canNext = _windowStart < maxStart;

    return Container(
      color: t.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.axisBackground,
              border: Border(bottom: BorderSide(color: t.border, width: 1)),
            ),
            child: Row(
              children: [
                _ActionPill(
                  theme: t,
                  label: '← Back',
                  secondary: true,
                  onTap: _closeInspect,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          meta.name,
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
                      const SizedBox(width: 8),
                      Text(
                        meta.sha256.substring(0, 12),
                        style: TextStyle(
                          color: t.textSecondary,
                          fontFamily: t.fontFamily,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          'Bars ${_windowStart + 1}–${_windowStart + _inspectCandles.length} of ${meta.barCount}',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textSecondary,
                            fontFamily: t.fontFamily,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.displayTimezone.shortLabel,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontFamily: t.fontFamily,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ActionPill(
                  theme: t,
                  label: '◀ Prev',
                  secondary: true,
                  onTap:
                      canPrev ? () => _shiftInspectWindow(-windowSize) : null,
                ),
                const SizedBox(width: 6),
                _ActionPill(
                  theme: t,
                  label: 'Next ▶',
                  secondary: true,
                  onTap: canNext ? () => _shiftInspectWindow(windowSize) : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: TilingTreeView(
              node: _inspectRoot,
              base1mCandles: _inspectCandles,
              theme: t,
              isDrawingPath: false,
              paths: const <CrossTimeframePath>[],
              activePath: null,
              syncedCursorRange: _inspectCursorRange,
              canClose: _inspectRoot is SplitNode,
              onTreeChanged: (n) => setState(() => _inspectRoot = n),
              onHoverRangeChanged: (r) =>
                  setState(() => _inspectCursorRange = r),
              onAddPathPoint: (a) =>
                  setState(() => _inspectPathAnchors.add(a)),
              onFinishPath: () => setState(() => _inspectPathAnchors.clear()),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final String y = dt.year.toString();
    final String mo = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    return '$y-$mo-$d';
  }

  Widget _cell(
    ChartTheme t,
    String text, {
    Color? color,
    bool bold = false,
  }) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? t.textPrimary,
        fontFamily: t.fontFamily,
        fontSize: 12,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class _ActionPill extends StatefulWidget {
  final ChartTheme theme;
  final String label;
  final VoidCallback? onTap;
  final bool secondary;

  const _ActionPill({
    required this.theme,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  State<_ActionPill> createState() => _ActionPillState();
}

class _ActionPillState extends State<_ActionPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final Color fill = widget.secondary
        ? (_isHovered
            ? t.activePillBackground.withValues(alpha: 0.14)
            : t.background)
        : t.activePillBackground;
    final Color border = widget.secondary ? t.border : t.activePillBackground;
    final Color text = widget.secondary
        ? (_isHovered ? t.textPrimary : t.textSecondary)
        : t.activePillText;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: text,
              fontFamily: t.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
