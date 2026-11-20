import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/engine/replay_engine.dart';
import '../../../domain/engine/telemetry_calculator.dart';
import '../../../domain/models/display_timezone.dart';
import '../../../domain/models/order.dart';
import '../../../domain/models/trading_session.dart';

/// Editorial Newsprint-styled telemetry dashboard for a replay session.
class StatsPage extends StatelessWidget {
  final ReplayEngine? replayEngine;
  final ChartTheme theme;
  final VoidCallback onCopyCsv;
  final DisplayTimezone displayTimezone;
  final TradingSession? activeSession;
  final TradingSession? parentSession;
  final VoidCallback onOpenSessions;
  final VoidCallback? onResumeLatest;
  final String? latestSessionName;

  const StatsPage({
    super.key,
    required this.replayEngine,
    required this.theme,
    required this.onCopyCsv,
    required this.onOpenSessions,
    this.displayTimezone = DisplayTimezone.utc,
    this.activeSession,
    this.parentSession,
    this.onResumeLatest,
    this.latestSessionName,
  });

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = theme;
    final ReplayEngine? engine = replayEngine;
    if (activeSession == null || engine == null) {
      return NoActiveSessionView(
        theme: t,
        onOpenSessions: onOpenSessions,
        onResumeLatest: onResumeLatest,
        latestSessionName: latestSessionName,
      );
    }

    final SessionTelemetry stats = TelemetryCalculator.calculate(engine);
    final List<CompletedTrade> trades =
        List<CompletedTrade>.from(engine.closedTrades);

    final List<CanceledOrder> canceled =
        List<CanceledOrder>.from(engine.canceledOrders);
    int filledPending = 0;
    for (final CompletedTrade tr in trades) {
      if (tr.entryType != EntryType.market) filledPending++;
    }
    final OpenPosition? open = engine.openPosition;
    if (open != null && open.entryType != EntryType.market) filledPending++;
    final int pendingNow = engine.pendingOrders.length;
    final int pendingPlaced = filledPending + canceled.length + pendingNow;
    final bool hasPending = pendingPlaced > 0;
    final double fillRate = hasPending ? filledPending / pendingPlaced : 0.0;

    return Container(
      color: t.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderBar(
            theme: t,
            tradeCount: stats.tradeCount,
            barsSeen: stats.barsSeen,
            totalWindowBars: stats.totalWindowBars,
            onCopyCsv: onCopyCsv,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (activeSession != null) ...[
                    _sessionHeader(t, trades),
                    const SizedBox(height: 20),
                  ],
                  _kpiGrid(t, stats),
                  if (hasPending) ...[
                    const SizedBox(height: 20),
                    _sectionTitle(t, 'ORDER FILL RATE'),
                    const SizedBox(height: 8),
                    _fillRateCard(t, filledPending, pendingPlaced, fillRate),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle(t, 'EQUITY CURVE'),
                  const SizedBox(height: 8),
                  _EquityCurveChart(
                    trades: trades,
                    theme: t,
                    displayTimezone: displayTimezone,
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle(t, 'TRADE LEDGER'),
                  const SizedBox(height: 8),
                  _ledger(t, trades),
                  if (canceled.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionTitle(t, 'UNFILLED ORDERS'),
                    const SizedBox(height: 8),
                    _UnfilledOrdersSection(
                      theme: t,
                      orders: canceled,
                      displayTimezone: displayTimezone,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fillRateCard(
    ChartTheme t,
    int filled,
    int placed,
    double rate,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Row(
        children: [
          Text(
            '${(rate * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FILL RATE',
                style: TextStyle(
                  color: t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$filled / $placed pending orders filled',
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
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

  Widget _sessionHeader(ChartTheme t, List<CompletedTrade> trades) {
    final TradingSession s = activeSession!;
    final int n = trades.length;
    final double winPct =
        n == 0 ? 0 : trades.where((x) => x.pnlPoints > 0).length / n * 100.0;
    double net = 0;
    for (final CompletedTrade tr in trades) {
      net += tr.pnlPoints;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                color: t.badgeBackground,
                child: Text(
                  s.changeType.badge,
                  style: TextStyle(
                    color: t.badgeText,
                    fontFamily: t.fontFamily,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontFamily: t.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _sampleBadge(t, n),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.hypothesis.isEmpty ? 'No hypothesis recorded.' : s.hypothesis,
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 12,
              height: 1.35,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (parentSession != null) ...[
            const SizedBox(height: 14),
            _baselineStrip(t, n, winPct, net),
          ],
        ],
      ),
    );
  }

  Widget _sampleBadge(ChartTheme t, int n) {
    final bool low = n < 30;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: low ? t.pendingSellBackground : t.gridLine,
        border: Border.all(
          color: low ? t.pendingSellBackground : t.border,
          width: 1,
        ),
      ),
      child: Text(
        low ? 'Low Sample · N = $n' : 'N = $n trades',
        style: TextStyle(
          color: low ? t.pendingSellText : t.textPrimary,
          fontFamily: t.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _baselineStrip(
    ChartTheme t,
    int curTrades,
    double curWin,
    double curNet,
  ) {
    final TradingSession p = parentSession!;
    final int pTrades = p.tradeCount;
    final double passThrough =
        pTrades == 0 ? 0.0 : (curTrades / pTrades) * 100.0;

    return Container(
      decoration: BoxDecoration(
        color: t.background,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.gridLine, width: 1)),
            ),
            child: Text(
              'BASELINE vs FORK',
              style: TextStyle(
                color: t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _baselinePanel(
                  t,
                  title: 'PARENT',
                  subtitle: p.changeType.badge,
                  trades: pTrades,
                  winPct: p.winRate * 100.0,
                  net: p.netPnlPoints,
                ),
              ),
              Container(width: 1, color: t.border),
              Expanded(
                child: _baselinePanel(
                  t,
                  title: 'CURRENT FORK',
                  subtitle: activeSession!.changeType.badge,
                  trades: curTrades,
                  winPct: curWin,
                  net: curNet,
                  highlight: true,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.gridLine, width: 1)),
            ),
            child: Row(
              children: [
                Text(
                  'Filter pass-through',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontFamily: t.fontFamily,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  pTrades == 0
                      ? '—'
                      : '${passThrough.toStringAsFixed(0)}% '
                          '($curTrades / $pTrades)',
                  style: TextStyle(
                    color: t.textPrimary,
                    fontFamily: t.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _baselinePanel(
    ChartTheme t, {
    required String title,
    required String subtitle,
    required int trades,
    required double winPct,
    required double net,
    bool highlight = false,
  }) {
    final Color netColor =
        net >= 0 ? t.pendingBuyBackground : t.pendingSellBackground;
    return Container(
      padding: const EdgeInsets.all(10),
      color: highlight
          ? t.activePillBackground.withValues(alpha: 0.08)
          : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _baselineMetric(t, 'Trades', '$trades'),
          _baselineMetric(t, 'Win', '${winPct.toStringAsFixed(0)}%'),
          _baselineMetric(
            t,
            'Net PnL',
            '${net >= 0 ? '+' : ''}${net.toStringAsFixed(1)}',
            color: netColor,
          ),
        ],
      ),
    );
  }

  Widget _baselineMetric(
    ChartTheme t,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                color: t.textSecondary,
                fontFamily: t.fontFamily,
                fontSize: 10,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(ChartTheme t, SessionTelemetry s) {
    final List<List<String>> items = <List<String>>[
      <String>['Trades', '${s.tradeCount}'],
      <String>['Win Rate', '${s.winRatePct.toStringAsFixed(1)}%'],
      <String>['Cum Return', '${s.cumulativeReturnPct.toStringAsFixed(2)}%'],
      <String>['Total R', s.totalR.toStringAsFixed(2)],
      <String>['Sharpe', s.perTradeSharpe.toStringAsFixed(2)],
      <String>['Max Drawdown', '${s.maxDrawdownPct.toStringAsFixed(2)}%'],
      <String>['Blunders', '${s.blunders.length}'],
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((kv) => _kpiCard(t, kv[0], kv[1])).toList(),
    );
  }

  Widget _kpiCard(ChartTheme t, String label, String value) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: t.textSecondary,
              fontFamily: t.fontFamily,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: t.textPrimary,
              fontFamily: t.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledger(ChartTheme t, List<CompletedTrade> trades) {
    if (trades.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: t.axisBackground,
          border: Border.all(color: t.border, width: 1),
        ),
        child: Text(
          'No closed trades yet',
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
          _ledgerHeader(t),
          ...trades.asMap().entries.map(
                (e) => _ledgerRow(t, e.key + 1, e.value),
              ),
        ],
      ),
    );
  }

  Widget _ledgerHeader(ChartTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Row(
        children: [
          _cell(t, '#', 40, bold: true),
          _cell(t, 'SIDE', 70, bold: true),
          _cell(t, 'TYPE', 52, bold: true),
          _cell(t, 'TIME', 120, bold: true),
          _cell(t, 'ENTRY', 100, bold: true),
          _cell(t, 'EXIT', 100, bold: true),
          _cell(t, 'PnL', 90, bold: true),
          _cell(t, 'R', 70, bold: true),
        ],
      ),
    );
  }

  Widget _ledgerRow(ChartTheme t, int index, CompletedTrade trade) {
    final bool isLong = trade.side == OrderSide.buy;
    final Color sideColor =
        isLong ? t.pendingBuyBackground : t.pendingSellBackground;
    final Color pnlColor =
        trade.pnlPoints >= 0 ? t.pendingBuyBackground : t.pendingSellBackground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.gridLine, width: 1)),
      ),
      child: Row(
        children: [
          _cell(t, '$index', 40),
          _cell(t, isLong ? 'LONG' : 'SHORT', 70, color: sideColor, bold: true),
          _entryTypeCell(t, trade.entryType),
          _cell(t, _fmtTime(trade.entryTime), 120),
          _cell(t, trade.entryPrice.toStringAsFixed(2), 100),
          _cell(t, trade.exitPrice.toStringAsFixed(2), 100),
          _cell(
            t,
            trade.pnlPoints.toStringAsFixed(2),
            90,
            color: pnlColor,
            bold: true,
          ),
          _cell(
            t,
            trade.realizedR?.toStringAsFixed(2) ?? '—',
            70,
            color: pnlColor,
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime utcTime) {
    final DateTime d = displayTimezone.toDisplayTime(utcTime);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Widget _cell(
    ChartTheme t,
    String text,
    double width, {
    Color? color,
    bool bold = false,
  }) {    return SizedBox(
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

  Widget _entryTypeCell(ChartTheme t, EntryType entryType) {
    return SizedBox(
      width: 52,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          color: t.badgeBackground,
          child: Text(
            entryType.badge,
            style: TextStyle(
              color: t.badgeText,
              fontFamily: t.fontFamily,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable launchpad shown by Practice and Stats when no session is loaded.
/// Newsprint-styled and overflow-safe at any width.
class NoActiveSessionView extends StatelessWidget {
  final ChartTheme theme;
  final VoidCallback onOpenSessions;
  final VoidCallback? onResumeLatest;
  final String? latestSessionName;

  const NoActiveSessionView({
    super.key,
    required this.theme,
    required this.onOpenSessions,
    this.onResumeLatest,
    this.latestSessionName,
  });

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = theme;
    final String? name = latestSessionName;
    return Container(
      color: t.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.axisBackground,
            border: Border.all(color: t.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NO ACTIVE SESSION',
                style: TextStyle(
                  color: t.textPrimary,
                  fontFamily: t.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Select an existing experiment node or create a new Root '
                'session on the canvas to start replay and track telemetry.',
                style: TextStyle(
                  color: t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _launchButton(
                    t,
                    'Open Sessions',
                    onTap: onOpenSessions,
                    primary: true,
                  ),
                  if (onResumeLatest != null)
                    _launchButton(
                      t,
                      name == null || name.isEmpty
                          ? 'Resume last session'
                          : 'Resume "$name"',
                      onTap: onResumeLatest,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _launchButton(
    ChartTheme t,
    String label, {
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? t.activePillText : t.textPrimary,
        backgroundColor: primary ? t.activePillBackground : t.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: primary
            ? BorderSide.none
            : BorderSide(color: t.border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: t.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  final ChartTheme theme;
  final int tradeCount;
  final int barsSeen;
  final int totalWindowBars;
  final VoidCallback onCopyCsv;

  const _HeaderBar({
    required this.theme,
    required this.tradeCount,
    required this.barsSeen,
    required this.totalWindowBars,
    required this.onCopyCsv,
  });

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = theme;
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
                'SESSION TELEMETRY',
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
                '$tradeCount closed trade${tradeCount == 1 ? '' : 's'} · '
                '$barsSeen / $totalWindowBars bars',
                style: TextStyle(
                  color: t.textSecondary,
                  fontFamily: t.fontFamily,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          _CopyCsvPill(theme: t, onTap: onCopyCsv),
        ],
      ),
    );
  }
}

class _CopyCsvPill extends StatefulWidget {
  final ChartTheme theme;
  final VoidCallback onTap;

  const _CopyCsvPill({required this.theme, required this.onTap});

  @override
  State<_CopyCsvPill> createState() => _CopyCsvPillState();
}

class _CopyCsvPillState extends State<_CopyCsvPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: t.activePillBackground,
            border: Border.all(color: t.activePillBackground),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Copy CSV',
            style: TextStyle(
              color: t.activePillText,
              fontFamily: t.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              decoration: _isHovered ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive equity curve: Y-axis PnL rulers, X-axis trade ticks, running-peak
/// drawdown shading, and a hover/scrub crosshair readout.
class _EquityCurveChart extends StatefulWidget {
  final List<CompletedTrade> trades;
  final ChartTheme theme;
  final DisplayTimezone displayTimezone;

  const _EquityCurveChart({
    required this.trades,
    required this.theme,
    required this.displayTimezone,
  });

  @override
  State<_EquityCurveChart> createState() => _EquityCurveChartState();
}

class _EquityCurveChartState extends State<_EquityCurveChart> {
  static const double _left = 14;
  static const double _right = 64;

  int? _hoveredIndex;

  void _updateHover(Offset local, Size size) {
    if (widget.trades.isEmpty) return;
    final int points = widget.trades.length + 1;
    final double plotW = size.width - _left - _right;
    if (plotW <= 0) return;
    final double x = (local.dx - _left).clamp(0.0, plotW);
    final int idx = points <= 1
        ? 0
        : (x / plotW * (points - 1)).round().clamp(0, points - 1).toInt();
    if (idx != _hoveredIndex) setState(() => _hoveredIndex = idx);
  }

  void _clearHover() {
    if (_hoveredIndex != null) setState(() => _hoveredIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    final BoxDecoration deco = BoxDecoration(
      color: t.axisBackground,
      border: Border.all(color: t.border, width: 1),
    );

    if (widget.trades.isEmpty) {
      return Container(
        height: 240,
        decoration: deco,
        alignment: Alignment.center,
        child: Text(
          'No closed trades yet',
          style: TextStyle(
            color: t.textSecondary,
            fontFamily: t.fontFamily,
            fontSize: 13,
          ),
        ),
      );
    }

    return Container(
      height: 240,
      decoration: deco,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size size = constraints.biggest;
          return MouseRegion(
            onHover: (e) => _updateHover(e.localPosition, size),
            onExit: (_) => _clearHover(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _updateHover(d.localPosition, size),
              onTapUp: (_) => _clearHover(),
              onTapCancel: _clearHover,
              onPanUpdate: (d) => _updateHover(d.localPosition, size),
              onPanEnd: (_) => _clearHover(),
              onPanCancel: _clearHover,
              child: CustomPaint(
                size: Size.infinite,
                painter: _EquityCurveChartPainter(
                  trades: widget.trades,
                  theme: t,
                  displayTimezone: widget.displayTimezone,
                  hoveredIndex: _hoveredIndex,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EquityCurveChartPainter extends CustomPainter {
  final List<CompletedTrade> trades;
  final ChartTheme theme;
  final DisplayTimezone displayTimezone;
  final int? hoveredIndex;

  _EquityCurveChartPainter({
    required this.trades,
    required this.theme,
    required this.displayTimezone,
    required this.hoveredIndex,
  });

  static const double _left = 14;
  static const double _top = 14;
  static const double _right = 64;
  static const double _bottom = 24;

  @override
  void paint(Canvas canvas, Size size) {
    if (trades.isEmpty) return;
    final ChartTheme t = theme;

    final double plotL = _left;
    final double plotT = _top;
    final double plotR = size.width - _right;
    final double plotB = size.height - _bottom;
    final double plotW = math.max(1.0, plotR - plotL);
    final double plotH = math.max(1.0, plotB - plotT);

    final int n = trades.length + 1;
    final List<double> eq = List<double>.filled(n, 0.0);
    double cum = 0.0;
    for (int i = 1; i < n; i++) {
      cum += trades[i - 1].pnlPoints;
      eq[i] = cum;
    }

    final List<double> peak = List<double>.filled(n, 0.0);
    double runPeak = 0.0;
    for (int i = 0; i < n; i++) {
      runPeak = math.max(runPeak, eq[i]);
      peak[i] = runPeak;
    }

    double minV = 0.0;
    double maxV = 0.0;
    for (final double v in eq) {
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    if (minV == maxV) {
      minV -= 1.0;
      maxV += 1.0;
    }
    final double pad = (maxV - minV) * 0.08;
    minV -= pad;
    maxV += pad;

    double xFor(int i) =>
        plotL + (n <= 1 ? 0.0 : (i / (n - 1)) * plotW);
    double yFor(double v) => plotT + (maxV - v) / (maxV - minV) * plotH;

    // --- Y-axis rulers + gridlines ---
    final double step = _niceStep((maxV - minV) / 4.0);
    final gridPaint = Paint()
      ..color = t.gridLine
      ..strokeWidth = 1.0;
    final zeroPaint = Paint()
      ..color = t.border
      ..strokeWidth = 1.2;
    final double firstTick = (minV / step).ceil() * step;
    final int tickCount = math.max(1, ((maxV - firstTick) / step).round() + 1);
    for (int i = 0; i < tickCount; i++) {
      final double v = firstTick + i * step;
      final double y = yFor(v);
      if (y < plotT - 0.5 || y > plotB + 0.5) continue;
      canvas.drawLine(
        Offset(plotL, y),
        Offset(plotR, y),
        v.abs() < step * 0.001 ? zeroPaint : gridPaint,
      );
      _text(
        canvas,
        _fmtTick(v),
        Offset(size.width - 6, y),
        _axisStyle(t),
        alignRight: true,
      );
    }

    // --- X-axis trade-index ticks ---
    const int maxXTicks = 6;
    final int stepIdx = math.max(1, ((n - 1) / (maxXTicks - 1)).ceil());
    for (int i = 0; i < n; i += stepIdx) {
      final double x = xFor(i);
      canvas.drawLine(Offset(x, plotB), Offset(x, plotB + 4), gridPaint);
      _text(
        canvas,
        '#$i',
        Offset(x, plotB + 7),
        _axisStyle(t),
        centered: true,
      );
    }

    // --- Drawdown shading (running-peak step line vs equity) ---
    final Path dd = Path()..moveTo(xFor(0), yFor(peak[0]));
    for (int i = 1; i < n; i++) {
      dd.lineTo(xFor(i), yFor(peak[i - 1]));
      dd.lineTo(xFor(i), yFor(peak[i]));
    }
    for (int i = n - 1; i >= 0; i--) {
      dd.lineTo(xFor(i), yFor(eq[i]));
    }
    dd.close();
    canvas.drawPath(
      dd,
      Paint()..color = t.bearBorder.withValues(alpha: 0.08),
    );

    // --- Equity curve ---
    for (int i = 1; i < n; i++) {
      final bool up = eq[i] >= eq[i - 1];
      canvas.drawLine(
        Offset(xFor(i - 1), yFor(eq[i - 1])),
        Offset(xFor(i), yFor(eq[i])),
        Paint()
          ..color = up ? t.bullBorder : t.bearBorder
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }

    // --- Crosshair + readout ---
    final int? h = hoveredIndex;
    if (h != null && h >= 0 && h < n) {
      final double hx = xFor(h);
      final double hy = yFor(eq[h]);
      _drawDashed(
        canvas,
        Offset(hx, plotT),
        Offset(hx, plotB),
        Paint()
          ..color = t.textSecondary
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(Offset(hx, hy), 4.5, Paint()..color = t.textPrimary);
      canvas.drawCircle(
        Offset(hx, hy),
        4.5,
        Paint()
          ..color = t.background
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );

      _drawReadout(canvas, size, plotL, plotT, plotR, plotW, h, eq, peak);
    }
  }

  void _drawReadout(
    Canvas canvas,
    Size size,
    double plotL,
    double plotT,
    double plotR,
    double plotW,
    int h,
    List<double> eq,
    List<double> peak,
  ) {
    final ChartTheme t = theme;
    final List<List<Object>> lines = <List<Object>>[];
    if (h == 0) {
      lines.add(<Object>['Start (0.0)', true]);
    } else {
      final CompletedTrade tr = trades[h - 1];
      lines.add(<Object>[
        '#$h · ${tr.side == OrderSide.buy ? 'LONG' : 'SHORT'} · '
            '${_fmtTime(tr.exitTime)}',
        true,
      ]);
      final String r =
          tr.realizedR != null ? ' (${_signed(tr.realizedR!, 2)}R)' : '';
      lines.add(<Object>['Trade: ${_signed(tr.pnlPoints, 1)} pts$r', false]);
    }
    lines.add(<Object>['Equity: ${_signed(eq[h], 1)} pts', false]);
    lines.add(<Object>[
      'Drawdown: -${(peak[h] - eq[h]).toStringAsFixed(1)} pts',
      false,
    ]);

    final List<TextPainter> tps = <TextPainter>[];
    double boxW = 0;
    double boxH = 0;
    for (final List<Object> line in lines) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: line[0] as String,
          style: TextStyle(
            color: t.textPrimary,
            fontFamily: t.fontFamily,
            fontSize: (line[1] as bool) ? 11 : 10,
            fontWeight: (line[1] as bool) ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tps.add(tp);
      boxW = math.max(boxW, tp.width);
      boxH += tp.height + 2;
    }
    boxH += 12;
    boxW += 16;

    final double hoverX = plotL + (h / math.max(1, trades.length)) * plotW;
    final bool leftHalf = hoverX < plotL + plotW / 2;
    double bx = leftHalf ? plotR - boxW - 6 : plotL + 6;
    bx = bx
        .clamp(plotL + 2, math.max(plotL + 2, plotR - boxW - 2))
        .toDouble();
    final double by = plotT + 6;

    canvas.drawRect(
      Rect.fromLTWH(bx, by, boxW, boxH),
      Paint()..color = t.background,
    );
    canvas.drawRect(
      Rect.fromLTWH(bx, by, boxW, boxH),
      Paint()
        ..color = t.border
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    double ty = by + 6;
    for (final TextPainter tp in tps) {
      tp.paint(canvas, Offset(bx + 8, ty));
      ty += tp.height + 2;
    }
  }

  double _niceStep(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1.0;
    final double exp = (math.log(raw) / math.ln10).floorToDouble();
    final double base = math.pow(10.0, exp).toDouble();
    final double f = raw / base;
    double nice;
    if (f <= 1.0) {
      nice = 1.0;
    } else if (f <= 2.0) {
      nice = 2.0;
    } else if (f <= 5.0) {
      nice = 5.0;
    } else {
      nice = 10.0;
    }
    return nice * base;
  }

  TextStyle _axisStyle(ChartTheme t) => TextStyle(
        color: t.textSecondary,
        fontFamily: t.fontFamily,
        fontSize: 10,
      );

  String _fmtTick(double v) {
    if (v.abs() < 0.05) return '0.0';
    final String s = v.toStringAsFixed(1);
    return v > 0 ? '+$s' : s;
  }

  String _signed(double v, int digits) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}';

  String _fmtTime(DateTime utc) {
    final DateTime d = displayTimezone.toDisplayTime(utc);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor,
    TextStyle style, {
    bool alignRight = false,
    bool centered = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = anchor.dx;
    if (alignRight) {
      dx = anchor.dx - tp.width;
    } else if (centered) {
      dx = anchor.dx - tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
  }

  void _drawDashed(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dash = 4.0;
    const double gap = 4.0;
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

  @override
  bool shouldRepaint(covariant _EquityCurveChartPainter old) {
    return !identical(old.trades, trades) ||
        old.hoveredIndex != hoveredIndex ||
        old.displayTimezone != displayTimezone;
  }
}

/// Collapsible list of canceled / unfilled pending orders.
class _UnfilledOrdersSection extends StatefulWidget {
  final ChartTheme theme;
  final List<CanceledOrder> orders;
  final DisplayTimezone displayTimezone;

  const _UnfilledOrdersSection({
    required this.theme,
    required this.orders,
    required this.displayTimezone,
  });

  @override
  State<_UnfilledOrdersSection> createState() => _UnfilledOrdersSectionState();
}

class _UnfilledOrdersSectionState extends State<_UnfilledOrdersSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = widget.theme;
    return Container(
      decoration: BoxDecoration(
        color: t.axisBackground,
        border: Border.all(color: t.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _expanded ? t.border : Colors.transparent,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      _expanded ? '▼' : '▶',
                      style: TextStyle(
                        fontSize: 9,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'UNFILLED ORDERS',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontFamily: t.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.orders.length} canceled',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontFamily: t.fontFamily,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border, width: 1)),
              ),
              child: Row(
                children: [
                  _cell(t, '#', 40, bold: true),
                  _cell(t, 'SIDE', 60, bold: true),
                  _cell(t, 'TYPE', 50, bold: true),
                  _cell(t, 'PRICE', 90, bold: true),
                  _cell(t, 'CANCELED', 130, bold: true),
                  _cell(t, 'REASON', 110, bold: true),
                ],
              ),
            ),
            ...widget.orders.asMap().entries.map(
                  (e) => _row(t, e.key + 1, e.value),
                ),
          ],
        ],
      ),
    );
  }

  Widget _row(ChartTheme t, int index, CanceledOrder order) {
    final bool isLong = order.side == OrderSide.buy;
    final Color sideColor =
        isLong ? t.pendingBuyBackground : t.pendingSellBackground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.gridLine, width: 1)),
      ),
      child: Row(
        children: [
          _cell(t, '$index', 40),
          _cell(t, isLong ? 'LONG' : 'SHORT', 60,
              color: sideColor, bold: true),
          _cell(t, order.type.name.toUpperCase(), 50),
          _cell(t, order.entryPrice.toStringAsFixed(2), 90),
          _cell(t, _fmtTime(order.canceledTime), 130),
          _cell(t, order.cancelReason.label, 110),
        ],
      ),
    );
  }

  String _fmtTime(DateTime utcTime) {
    final DateTime d = widget.displayTimezone.toDisplayTime(utcTime);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
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
