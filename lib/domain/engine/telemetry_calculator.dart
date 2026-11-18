import 'dart:math' as math;

import '../models/order.dart';
import 'replay_engine.dart';

/// A recorded execution mistake attributed to a single trade.
class ExecutionBlunder {
  final String tradeId;
  final String code;
  final String description;

  const ExecutionBlunder({
    required this.tradeId,
    required this.code,
    required this.description,
  });
}

/// Deterministic session KPIs derived from a replay run. Pure Dart.
class SessionTelemetry {
  final int barsSeen;
  final int totalWindowBars;
  final int tradeCount;
  final int winCount;
  final int lossCount;
  final double winRatePct;
  final double cumulativeReturnPct;
  final double totalR;
  final double perTradeSharpe;
  final double avgWinPct;
  final double avgLossPct;
  final double maxDrawdownPct;
  final Map<String, int> entryMix;
  final Map<ExitReason, int> exitBreakdown;
  final List<double> cumulativeEquityCurve;
  final List<ExecutionBlunder> blunders;

  const SessionTelemetry({
    required this.barsSeen,
    required this.totalWindowBars,
    required this.tradeCount,
    required this.winCount,
    required this.lossCount,
    required this.winRatePct,
    required this.cumulativeReturnPct,
    required this.totalR,
    required this.perTradeSharpe,
    required this.avgWinPct,
    required this.avgLossPct,
    required this.maxDrawdownPct,
    required this.entryMix,
    required this.exitBreakdown,
    required this.cumulativeEquityCurve,
    required this.blunders,
  });
}

class TelemetryCalculator {
  static SessionTelemetry calculate(ReplayEngine engine) {
    final List<CompletedTrade> trades = List<CompletedTrade>.from(
      engine.closedTrades,
    );

    final int barsSeen = engine.cursorIndex - engine.minCursorIndex + 1;
    final int totalWindowBars = engine.maxCursorIndex - engine.minCursorIndex + 1;
    final int tradeCount = trades.length;

    int winCount = 0;
    int lossCount = 0;
    double sumReturn = 0;
    final List<double> returns = <double>[];
    final List<double> wins = <double>[];
    final List<double> losses = <double>[];

    double cumulativeEquity = 1.0;
    double peakEquity = 1.0;
    double maxDrawdown = 0.0;
    final List<double> equityCurve = <double>[0.0];

    double totalR = 0.0;

    final Map<String, int> entryMix = <String, int>{};
    final Map<ExitReason, int> exitBreakdown = <ExitReason, int>{};
    final List<ExecutionBlunder> blunders = <ExecutionBlunder>[];

    for (final trade in trades) {
      final double r = trade.returnPct;
      returns.add(r);
      sumReturn += r;
      if (r >= 0) {
        winCount++;
        wins.add(r);
      } else {
        lossCount++;
        losses.add(r);
      }

      cumulativeEquity *= (1.0 + r / 100.0);
      if (cumulativeEquity > peakEquity) peakEquity = cumulativeEquity;
      final double dd =
          (peakEquity - cumulativeEquity) / peakEquity * 100.0;
      if (dd > maxDrawdown) maxDrawdown = dd;
      equityCurve.add((cumulativeEquity - 1.0) * 100.0);

      if (trade.initialRisk > 0) {
        totalR += trade.realizedR ?? 0.0;
      }

      final bool isPending = trade.events.isNotEmpty &&
          trade.events.first.type == OrderEventType.created;
      final String mix = isPending ? 'PENDING' : 'MARKET';
      entryMix[mix] = (entryMix[mix] ?? 0) + 1;

      exitBreakdown[trade.exitReason] =
          (exitBreakdown[trade.exitReason] ?? 0) + 1;

      _detectBlunders(trade, blunders);
    }

    final double winRatePct =
        tradeCount == 0 ? 0.0 : (winCount / tradeCount) * 100.0;
    final double cumulativeReturnPct = (cumulativeEquity - 1.0) * 100.0;

    double perTradeSharpe = 0.0;
    if (tradeCount >= 2) {
      final double mean = sumReturn / tradeCount;
      double sqSum = 0;
      for (final r in returns) {
        final double d = r - mean;
        sqSum += d * d;
      }
      final double variance = sqSum / (tradeCount - 1);
      final double stdDev = math.sqrt(variance);
      if (stdDev > 0) perTradeSharpe = mean / stdDev;
    }

    double avgWinPct = 0.0;
    if (wins.isNotEmpty) {
      double s = 0;
      for (final w in wins) {
        s += w;
      }
      avgWinPct = s / wins.length;
    }

    double avgLossPct = 0.0;
    if (losses.isNotEmpty) {
      double s = 0;
      for (final l in losses) {
        s += l;
      }
      avgLossPct = s / losses.length;
    }

    return SessionTelemetry(
      barsSeen: barsSeen,
      totalWindowBars: totalWindowBars,
      tradeCount: tradeCount,
      winCount: winCount,
      lossCount: lossCount,
      winRatePct: winRatePct,
      cumulativeReturnPct: cumulativeReturnPct,
      totalR: totalR,
      perTradeSharpe: perTradeSharpe,
      avgWinPct: avgWinPct,
      avgLossPct: avgLossPct,
      maxDrawdownPct: maxDrawdown,
      entryMix: entryMix,
      exitBreakdown: exitBreakdown,
      cumulativeEquityCurve: equityCurve,
      blunders: blunders,
    );
  }

  static void _detectBlunders(
    CompletedTrade trade,
    List<ExecutionBlunder> out,
  ) {
    if (trade.initialSl == null) {
      out.add(
        ExecutionBlunder(
          tradeId: trade.id,
          code: 'NO_INITIAL_SL',
          description: 'Entered without an initial stop-loss',
        ),
      );
    }

    bool removed = false;
    bool widened = false;
    for (final entry in trade.slHistory) {
      if (entry.newSl == null) {
        removed = true;
      }
      final double? oldSl = entry.oldSl;
      final double? newSl = entry.newSl;
      if (oldSl != null && newSl != null) {
        final bool movedAway = trade.side == OrderSide.buy
            ? newSl < oldSl
            : newSl > oldSl;
        if (movedAway) widened = true;
      }
    }

    if (removed) {
      out.add(
        ExecutionBlunder(
          tradeId: trade.id,
          code: 'SL_REMOVED',
          description: 'Stop-loss was removed mid-trade',
        ),
      );
    }
    if (widened) {
      out.add(
        ExecutionBlunder(
          tradeId: trade.id,
          code: 'SL_WIDENED',
          description: 'Stop-loss moved away from entry (widened risk)',
        ),
      );
    }
  }

  static String exportTradesCsv(List<CompletedTrade> trades) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(
      'id,side,entry_time,exit_time,entry_price,exit_price,initial_sl,'
      'final_sl,exit_reason,pnl_points,return_pct,realized_r,mfe_r,mae_r,'
      'sl_changes',
    );
    for (final t in trades) {
      buffer.writeln([
        t.id,
        t.side.name,
        t.entryTime.toIso8601String(),
        t.exitTime.toIso8601String(),
        t.entryPrice.toString(),
        t.exitPrice.toString(),
        t.initialSl?.toString() ?? '',
        t.finalSl?.toString() ?? '',
        t.exitReason.name,
        t.pnlPoints.toString(),
        t.returnPct.toString(),
        t.realizedR?.toString() ?? '',
        t.mfeR?.toString() ?? '',
        t.maeR?.toString() ?? '',
        t.slHistory.length.toString(),
      ].join(','));
    }
    return buffer.toString();
  }
}
