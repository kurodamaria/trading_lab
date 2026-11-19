import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/engine/replay_engine.dart';
import '../../../domain/engine/telemetry_calculator.dart';
import '../../../domain/models/display_timezone.dart';
import '../../../domain/models/order.dart';

/// Editorial Newsprint-styled telemetry dashboard for a replay session.
class StatsPage extends StatelessWidget {
  final ReplayEngine replayEngine;
  final ChartTheme theme;
  final VoidCallback onCopyCsv;
  final DisplayTimezone displayTimezone;

  const StatsPage({
    super.key,
    required this.replayEngine,
    required this.theme,
    required this.onCopyCsv,
    this.displayTimezone = DisplayTimezone.utc,
  });

  @override
  Widget build(BuildContext context) {
    final ChartTheme t = theme;
    final SessionTelemetry stats = TelemetryCalculator.calculate(replayEngine);
    final List<CompletedTrade> trades =
        List<CompletedTrade>.from(replayEngine.closedTrades);

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
                  _kpiGrid(t, stats),
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
                ],
              ),
            ),
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
