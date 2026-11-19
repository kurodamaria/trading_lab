import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/models/timeframe.dart';
import '../../../domain/models/trading_session.dart';

/// A dataset choice surfaced in the new-session dialog.
class DatasetOption {
  final String id;
  final String label;
  final int barCount;

  const DatasetOption({
    required this.id,
    required this.label,
    required this.barCount,
  });
}

/// Values collected by [NewRootSessionDialog].
class RootSessionRequest {
  final String name;
  final DatasetOption dataset;
  final int windowStartIndex;
  final int windowEndIndex;
  final Timeframe cadence;

  const RootSessionRequest({
    required this.name,
    required this.dataset,
    required this.windowStartIndex,
    required this.windowEndIndex,
    required this.cadence,
  });
}

/// Values collected by [ForkSessionDialog].
class ForkRequest {
  final String name;
  final String hypothesis;
  final SessionChangeType changeType;

  const ForkRequest({
    required this.name,
    required this.hypothesis,
    required this.changeType,
  });
}

// -----------------------------------------------------------------------------
// Shared newsprint dialog chrome
// -----------------------------------------------------------------------------

Widget _dialogFrame({
  required ChartTheme theme,
  required String title,
  required String subtitle,
  required Widget body,
  required List<Widget> actions,
}) {
  return Dialog(
    backgroundColor: theme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    ),
    child: Container(
      width: 460,
      decoration: BoxDecoration(
        color: theme.background,
        border: Border.all(color: theme.border, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.axisBackground,
              border: Border(
                bottom: BorderSide(color: theme.border, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontFamily: theme.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontFamily: theme.fontFamily,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: body,
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _label(ChartTheme theme, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: theme.textSecondary,
          fontFamily: theme.fontFamily,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );

InputDecoration _inputDecoration(ChartTheme theme, {String? hint}) {
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(
      color: theme.textSecondary,
      fontFamily: theme.fontFamily,
      fontSize: 12,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: theme.border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: theme.activePillBackground, width: 1.5),
    ),
  );
}

TextStyle _fieldStyle(ChartTheme theme) => TextStyle(
      color: theme.textPrimary,
      fontFamily: theme.fontFamily,
      fontSize: 12,
    );

Widget _dropdown<T>({
  required ChartTheme theme,
  required T value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: theme.border, width: 1),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        isDense: true,
        dropdownColor: theme.background,
        style: _fieldStyle(theme),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

Widget _button(
  ChartTheme theme,
  String label, {
  required VoidCallback? onTap,
  bool primary = false,
}) {
  final bool enabled = onTap != null;
  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor:
            primary ? theme.activePillText : theme.textPrimary,
        backgroundColor:
            primary ? theme.activePillBackground : Colors.transparent,
        disabledForegroundColor: theme.textSecondary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        side: primary
            ? BorderSide.none
            : BorderSide(
                color: enabled ? theme.border : theme.gridLine,
                width: 1,
              ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// New root session
// -----------------------------------------------------------------------------

class NewRootSessionDialog extends StatefulWidget {
  final ChartTheme theme;
  final List<DatasetOption> datasets;

  const NewRootSessionDialog({
    super.key,
    required this.theme,
    required this.datasets,
  });

  @override
  State<NewRootSessionDialog> createState() => _NewRootSessionDialogState();
}

class _NewRootSessionDialogState extends State<NewRootSessionDialog> {
  late final TextEditingController _name;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late DatasetOption _dataset;
  Timeframe _cadence = Timeframe.m15;

  @override
  void initState() {
    super.initState();
    _dataset = widget.datasets.isNotEmpty
        ? widget.datasets.first
        : const DatasetOption(id: 'synthetic', label: 'Synthetic 30k', barCount: 30000);
    _name = TextEditingController(text: 'Hypothesis ${_dataset.id == 'synthetic' ? 'Root' : _dataset.label}');
    _start = TextEditingController(text: '0');
    _end = TextEditingController(
      text: '${_dataset.barCount > 0 ? _dataset.barCount - 1 : 0}',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _onDatasetChanged(DatasetOption? d) {
    if (d == null) return;
    setState(() {
      _dataset = d;
      _end.text = '${d.barCount > 0 ? d.barCount - 1 : 0}';
    });
  }

  bool get _valid {
    if (_name.text.trim().isEmpty) return false;
    final int? s = int.tryParse(_start.text.trim());
    final int? e = int.tryParse(_end.text.trim());
    if (s == null || e == null) return false;
    return s >= 0 && e > s && e < _dataset.barCount;
  }

  void _submit() {
    final int s = int.parse(_start.text.trim());
    final int e = int.parse(_end.text.trim());
    Navigator.of(context).pop(
      RootSessionRequest(
        name: _name.text.trim(),
        dataset: _dataset,
        windowStartIndex: s,
        windowEndIndex: e,
        cadence: _cadence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return _dialogFrame(
      theme: t,
      title: 'NEW ROOT SESSION',
      subtitle: 'Start a fresh hypothesis on a dataset window.',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'SESSION NAME'),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: _fieldStyle(t),
            decoration: _inputDecoration(t, hint: 'e.g. Trend pullback v1'),
          ),
          const SizedBox(height: 12),
          _label(t, 'DATASET'),
          _dropdown<DatasetOption>(
            theme: t,
            value: _dataset,
            items: widget.datasets
                .map(
                  (d) => DropdownMenuItem<DatasetOption>(
                    value: d,
                    child: Text(
                      '${d.label}  ·  ${d.barCount} bars',
                      style: _fieldStyle(t),
                    ),
                  ),
                )
                .toList(),
            onChanged: _onDatasetChanged,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(t, 'START BAR'),
                    TextField(
                      controller: _start,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: _fieldStyle(t),
                      decoration: _inputDecoration(t),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(t, 'END BAR'),
                    TextField(
                      controller: _end,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: _fieldStyle(t),
                      decoration: _inputDecoration(t),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label(t, 'INITIAL CADENCE'),
          _dropdown<Timeframe>(
            theme: t,
            value: _cadence,
            items: Timeframe.values
                .map(
                  (tf) => DropdownMenuItem<Timeframe>(
                    value: tf,
                    child: Text(tf.label, style: _fieldStyle(t)),
                  ),
                )
                .toList(),
            onChanged: (tf) => setState(() => _cadence = tf ?? _cadence),
          ),
        ],
      ),
      actions: [
        _button(t, 'Cancel', onTap: () => Navigator.of(context).pop()),
        _button(
          t,
          'Create Session',
          primary: true,
          onTap: _valid ? _submit : null,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Fork session
// -----------------------------------------------------------------------------

class ForkSessionDialog extends StatefulWidget {
  final ChartTheme theme;
  final TradingSession parent;

  const ForkSessionDialog({
    super.key,
    required this.theme,
    required this.parent,
  });

  @override
  State<ForkSessionDialog> createState() => _ForkSessionDialogState();
}

class _ForkSessionDialogState extends State<ForkSessionDialog> {
  late final TextEditingController _name;
  late final TextEditingController _hypothesis;
  SessionChangeType _changeType = SessionChangeType.entryFilter;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.parent.name} fork');
    _hypothesis = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _hypothesis.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _hypothesis.text.trim().isNotEmpty;

  void _submit() {
    Navigator.of(context).pop(
      ForkRequest(
        name: _name.text.trim(),
        hypothesis: _hypothesis.text.trim(),
        changeType: _changeType,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return _dialogFrame(
      theme: t,
      title: 'FORK SESSION',
      subtitle: 'Inherit ${widget.parent.tradeCount} candidate entries '
          'from "${widget.parent.name}".',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(t, 'CHILD SESSION NAME'),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: _fieldStyle(t),
            decoration: _inputDecoration(t),
          ),
          const SizedBox(height: 12),
          _label(t, 'CHANGE TYPE'),
          _dropdown<SessionChangeType>(
            theme: t,
            value: _changeType,
            items: SessionChangeType.values
                .where((c) => c != SessionChangeType.root)
                .map(
                  (c) => DropdownMenuItem<SessionChangeType>(
                    value: c,
                    child: Text(
                      '${c.badge}  ·  ${c.label}',
                      style: _fieldStyle(t),
                    ),
                  ),
                )
                .toList(),
            onChanged: (c) => setState(() => _changeType = c ?? _changeType),
          ),
          const SizedBox(height: 12),
          _label(t, 'HYPOTHESIS (ONE SENTENCE)'),
          TextField(
            controller: _hypothesis,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            style: _fieldStyle(t),
            decoration: _inputDecoration(
              t,
              hint: 'e.g. Skipping entries below the 200 EMA lifts win rate.',
            ),
          ),
        ],
      ),
      actions: [
        _button(t, 'Cancel', onTap: () => Navigator.of(context).pop()),
        _button(
          t,
          'Create Fork',
          primary: true,
          onTap: _valid ? _submit : null,
        ),
      ],
    );
  }
}

/// Confirmation used before deleting a leaf session.
Future<bool> confirmDeleteSession(
  BuildContext context, {
  required ChartTheme theme,
  required String name,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _dialogFrame(
      theme: theme,
      title: 'DELETE SESSION',
      subtitle: 'This removes the leaf session and cannot be undone.',
      body: Text(
        'Delete "$name"?',
        style: TextStyle(
          color: theme.textPrimary,
          fontFamily: theme.fontFamily,
          fontSize: 13,
        ),
      ),
      actions: [
        _button(theme, 'Cancel', onTap: () => Navigator.of(ctx).pop(false)),
        _button(
          theme,
          'Delete',
          primary: true,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  return ok ?? false;
}
