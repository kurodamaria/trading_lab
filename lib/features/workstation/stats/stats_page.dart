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
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: t.axisBackground,
                      border: Border.all(color: t.border, width: 1),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _EquityCurvePainter(
                        trades: trades,
                        theme: t,
                      ),
                    ),
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

class _EquityCurvePainter extends CustomPainter {
  final List<CompletedTrade> trades;
  final ChartTheme theme;

  _EquityCurvePainter({required this.trades, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final ChartTheme t = theme;

    if (trades.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'No closed trades yet',
          style: TextStyle(
            color: t.textSecondary,
            fontFamily: t.fontFamily,
            fontSize: 13,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
      return;
    }

    final List<double> series = <double>[0.0];
    double cumulative = 0.0;
    for (final trade in trades) {
      cumulative += trade.pnlPoints;
      series.add(cumulative);
    }

    double minV = series.reduce(math.min);
    double maxV = series.reduce(math.max);
    if (minV == maxV) {
      minV -= 1.0;
      maxV += 1.0;
    }
    final double pad = (maxV - minV) * 0.1;
    minV -= pad;
    maxV += pad;

    final double zeroY =
        size.height - ((0.0 - minV) / (maxV - minV)) * size.height;

    final gridPaint = Paint()
      ..color = t.gridLine
      ..strokeWidth = 1.0;
    for (int r = 1; r < 4; r++) {
      final double y = size.height * (r / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = t.border.withValues(alpha: 0.5)
        ..strokeWidth = 1.0,
    );

    Offset pointAt(int i) {
      final double x = series.length <= 1
          ? 0
          : (i / (series.length - 1)) * size.width;
      final double y =
          size.height - ((series[i] - minV) / (maxV - minV)) * size.height;
      return Offset(x, y);
    }

    for (int i = 0; i < series.length - 1; i++) {
      final double v = series[i + 1];
      canvas.drawLine(
        pointAt(i),
        pointAt(i + 1),
        Paint()
          ..color =
              v >= 0 ? t.pendingBuyBackground : t.pendingSellBackground
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(pointAt(series.length - 1), 3.0,
        Paint()..color = cumulative >= 0 ? t.bullBorder : t.pendingSellBackground);
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) => true;
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
