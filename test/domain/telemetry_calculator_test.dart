import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:trading_lab/domain/engine/replay_engine.dart';
import 'package:trading_lab/domain/engine/telemetry_calculator.dart';
import 'package:trading_lab/domain/models/candle.dart';
import 'package:trading_lab/domain/models/order.dart';
import 'package:trading_lab/domain/models/timeframe.dart';

Candle mk(int i, double o, double h, double l, double c) => Candle(
      index: i,
      time: DateTime(2026, 1, 1, 9, 0).add(Duration(minutes: i)),
      open: o,
      high: h,
      low: l,
      close: c,
    );

void main() {
  // ---------------------------------------------------------------------------
  // 1. Empty engine
  // ---------------------------------------------------------------------------
  test('empty engine produces zeroed KPIs and [0.0] curve', () {
    final e = ReplayEngine(
      base1mCandles: [mk(0, 100, 101, 99, 100), mk(1, 100, 101, 99, 100)],
      initialCursorIndex: 0,
    );
    final t = TelemetryCalculator.calculate(e);
    expect(t.tradeCount, 0);
    expect(t.winCount, 0);
    expect(t.lossCount, 0);
    expect(t.winRatePct, 0.0);
    expect(t.cumulativeReturnPct, 0.0);
    expect(t.totalR, 0.0);
    expect(t.perTradeSharpe, 0.0);
    expect(t.avgWinPct, 0.0);
    expect(t.avgLossPct, 0.0);
    expect(t.maxDrawdownPct, 0.0);
    expect(t.entryMix, isEmpty);
    expect(t.exitBreakdown, isEmpty);
    expect(t.cumulativeEquityCurve, [0.0]);
    expect(t.blunders, isEmpty);
    expect(t.barsSeen, 1);
    expect(t.totalWindowBars, 2);
  });

  // ---------------------------------------------------------------------------
  // 2. Mixed win/loss KPIs
  // ---------------------------------------------------------------------------
  group('mixed trades', () {
    // Trade A: entry 100 -> exit 120 (+20%), risk 5, R = +4
    // Trade B: entry 120 -> exit 116 (-3.3333%), risk 5, R = -0.8
    ReplayEngine build() {
      final e = ReplayEngine(
        base1mCandles: [
          mk(0, 100, 100, 100, 100),
          mk(1, 100, 120, 100, 120),
          mk(2, 120, 120, 115.5, 116),
          mk(3, 116, 116, 116, 116),
          mk(4, 116, 116, 116, 116),
        ],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      e.stepForward(Timeframe.m1);
      e.closePositionManually();

      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 115);
      e.stepForward(Timeframe.m1);
      e.closePositionManually();
      return e;
    }

    test('win rate, cumulative return, drawdown, sharpe, totalR', () {
      final t = TelemetryCalculator.calculate(build());
      expect(t.tradeCount, 2);
      expect(t.winCount, 1);
      expect(t.lossCount, 1);
      expect(t.winRatePct, closeTo(50.0, 1e-9));
      expect(t.cumulativeReturnPct, closeTo(16.0, 1e-9));
      expect(t.maxDrawdownPct, closeTo(10.0 / 3.0, 1e-9));
      expect(t.totalR, closeTo(3.2, 1e-9));
      expect(t.avgWinPct, closeTo(20.0, 1e-9));
      expect(t.avgLossPct, closeTo(-10.0 / 3.0, 1e-9));
      expect(
        t.perTradeSharpe,
        closeTo(5.0 / (7.0 * math.sqrt2), 1e-9),
      );
      expect(t.cumulativeEquityCurve, hasLength(3));
      expect(t.cumulativeEquityCurve[0], 0.0);
      expect(t.cumulativeEquityCurve[1], closeTo(20.0, 1e-9));
      expect(t.cumulativeEquityCurve[2], closeTo(16.0, 1e-9));
    });

    test('entry mix and exit breakdown', () {
      final t = TelemetryCalculator.calculate(build());
      expect(t.entryMix, {'MARKET': 2});
      expect(t.exitBreakdown, {ExitReason.manualClose: 2});
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Blunder detection
  // ---------------------------------------------------------------------------
  group('blunders', () {
    test('NO_INITIAL_SL is flagged', () {
      final e = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 105, 99, 105), mk(2, 100, 100, 100, 100)],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy);
      e.stepForward(Timeframe.m1);
      e.closePositionManually();

      final t = TelemetryCalculator.calculate(e);
      expect(t.blunders, hasLength(1));
      expect(t.blunders.single.code, 'NO_INITIAL_SL');
      expect(t.blunders.single.tradeId, e.closedTrades.single.id);
    });

    test('SL_REMOVED is flagged', () {
      final e = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 105, 99, 105), mk(2, 100, 100, 100, 100)],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      e.removeStopLoss();
      e.stepForward(Timeframe.m1);
      e.closePositionManually();

      final t = TelemetryCalculator.calculate(e);
      expect(
        t.blunders.map((b) => b.code),
        contains('SL_REMOVED'),
      );
    });

    test('SL_WIDENED is flagged for buy and sell', () {
      // buy: moving SL down widens risk
      final b = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 105, 99, 105), mk(2, 100, 100, 100, 100)],
        initialCursorIndex: 0,
      );
      b.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      b.updateStopLoss(90);
      b.stepForward(Timeframe.m1);
      b.closePositionManually();
      expect(
        TelemetryCalculator.calculate(b).blunders.map((x) => x.code),
        contains('SL_WIDENED'),
      );

      // sell: moving SL up widens risk
      final s = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 105, 99, 95), mk(2, 100, 100, 100, 100)],
        initialCursorIndex: 0,
      );
      s.executeMarketOrder(side: OrderSide.sell, stopLoss: 105);
      s.updateStopLoss(110);
      s.stepForward(Timeframe.m1);
      s.closePositionManually();
      expect(
        TelemetryCalculator.calculate(s).blunders.map((x) => x.code),
        contains('SL_WIDENED'),
      );
    });

    test('tightening the stop does not flag SL_WIDENED', () {
      final e = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 105, 99, 105), mk(2, 100, 100, 100, 100)],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      e.updateStopLoss(98); // tighter
      e.stepForward(Timeframe.m1);
      e.closePositionManually();
      expect(TelemetryCalculator.calculate(e).blunders, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. CSV export
  // ---------------------------------------------------------------------------
  group('exportTradesCsv', () {
    test('emits the exact header', () {
      final csv = TelemetryCalculator.exportTradesCsv(const []);
      expect(
        csv,
        'id,side,entry_time,exit_time,entry_price,exit_price,initial_sl,'
        'final_sl,exit_reason,pnl_points,return_pct,realized_r,mfe_r,mae_r,'
        'sl_changes\n',
      );
    });

    test('formats rows with ISO timestamps and empty nulls', () {
      final e = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 120, 100, 120), mk(2, 120, 120, 120, 120)],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      e.stepForward(Timeframe.m1);
      final trade = e.closePositionManually();

      final csv = TelemetryCalculator.exportTradesCsv([trade]);
      final lines = csv.trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines[0],
          'id,side,entry_time,exit_time,entry_price,exit_price,initial_sl,'
          'final_sl,exit_reason,pnl_points,return_pct,realized_r,mfe_r,mae_r,'
          'sl_changes');
      final cells = lines[1].split(',');
      expect(cells[0], trade.id);
      expect(cells[1], 'buy');
      expect(cells[2], trade.entryTime.toIso8601String());
      expect(cells[3], trade.exitTime.toIso8601String());
      expect(cells[4], '100.0');
      expect(cells[5], '120.0');
      expect(cells[6], '95.0');
      expect(cells[7], '95.0');
      expect(cells[8], 'manualClose');
      expect(cells[14], '0');
    });

    test('empty nulls render as empty strings', () {
      final e = ReplayEngine(
        base1mCandles: [mk(0, 100, 100, 100, 100), mk(1, 100, 120, 100, 120), mk(2, 120, 120, 120, 120)],
        initialCursorIndex: 0,
      );
      e.executeMarketOrder(side: OrderSide.buy); // no SL
      e.stepForward(Timeframe.m1);
      final trade = e.closePositionManually();

      final line = TelemetryCalculator.exportTradesCsv([trade]).trim().split('\n')[1];
      final cells = line.split(',');
      expect(cells[6], '');
      expect(cells[7], '');
      expect(cells[11], '');
    });
  });
}
