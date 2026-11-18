import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/data/binary_candle_store.dart';
import '../../../domain/data/dataset_metadata.dart';

/// Full-screen dataset library page: import CSVs, browse cached `.bin`
/// datasets, and load or delete them with protected-deletion confirmation.
class DatasetsPage extends StatefulWidget {
  final BinaryCandleStore store;
  final ChartTheme theme;
  final String? activeSha256;
  final void Function(DatasetMetadata meta) onLoad;

  const DatasetsPage({
    super.key,
    required this.store,
    required this.theme,
    required this.activeSha256,
    required this.onLoad,
  });

  @override
  State<DatasetsPage> createState() => _DatasetsPageState();
}

class _DatasetsPageState extends State<DatasetsPage> {
  List<DatasetMetadata> _datasets = const <DatasetMetadata>[];
  bool _importing = false;
  String? _error;

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

    return Container(
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
          _cell(t, 'NAME', 180, bold: true),
          _cell(t, 'SHA-256', 120, bold: true),
          _cell(t, 'BARS', 80, bold: true),
          _cell(t, 'RANGE', 230, bold: true),
          _cell(t, 'SIZE', 90, bold: true),
          _cell(t, 'STATUS', 130, bold: true),
          const Spacer(),
          _cell(t, 'ACTIONS', 130, bold: true),
        ],
      ),
    );
  }

  Widget _row(ChartTheme t, DatasetMetadata m) {
    final bool isActive = m.sha256 == widget.activeSha256;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.gridLine, width: 1)),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                child: Text(
                  m.name,
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
              if (isActive) _activePill(t),
            ],
          ),
          _cell(t, m.sha256.substring(0, 12), 120),
          _cell(t, '${m.barCount}', 80),
          SizedBox(
            width: 230,
            child: Text(
              '${_fmt(m.firstTime)} → ${_fmt(m.lastTime)}',
              style: TextStyle(
                color: t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 12,
              ),
            ),
          ),
          _cell(
            t,
            '${(m.binSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
            90,
          ),
          SizedBox(
            width: 130,
            child: Text(
              m.sessionIds.isNotEmpty
                  ? 'Locked: ${m.sessionIds.length} sessions'
                  : 'Unlocked',
              style: TextStyle(
                color: m.sessionIds.isNotEmpty
                    ? t.pendingSellBackground
                    : t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 12,
              ),
            ),
          ),
          const Spacer(),
          _ActionPill(
            theme: t,
            label: 'Load',
            onTap: () => widget.onLoad(m),
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
    );
  }

  Widget _activePill(ChartTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.activePillBackground,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'ACTIVE',
        style: TextStyle(
          color: t.activePillText,
          fontFamily: t.fontFamily,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
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
    String text,
    double width, {
    Color? color,
    bool bold = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          color: color ?? t.textPrimary,
          fontFamily: t.fontFamily,
          fontSize: 12,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
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
