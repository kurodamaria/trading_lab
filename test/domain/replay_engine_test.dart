import 'package:flutter_test/flutter_test.dart';

import 'package:trading_lab/domain/engine/replay_engine.dart';
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

ReplayEngine engine(List<Candle> candles, {int start = 0, int? max}) =>
    ReplayEngine(
      base1mCandles: candles,
      initialCursorIndex: start,
      maxCursorIndex: max,
    );

void main() {
  // ---------------------------------------------------------------------------
  // 1. PendingOrderType auto-resolution
  // ---------------------------------------------------------------------------
  group('PendingOrderType auto-resolution', () {
    test('buy resolves limit below price and stop at/above price', () {
      final e = engine([mk(0, 100, 101, 99, 100)]);
      final below = e.placePendingOrder(side: OrderSide.buy, price: 90);
      final above = e.placePendingOrder(side: OrderSide.buy, price: 110);
      final equal = e.placePendingOrder(side: OrderSide.buy, price: 100);
      expect(below.type, PendingOrderType.limit);
      expect(above.type, PendingOrderType.stop);
      expect(equal.type, PendingOrderType.stop);
    });

    test('sell resolves limit above price and stop at/below price', () {
      final e = engine([mk(0, 100, 101, 99, 100)]);
      final above = e.placePendingOrder(side: OrderSide.sell, price: 110);
      final below = e.placePendingOrder(side: OrderSide.sell, price: 90);
      final equal = e.placePendingOrder(side: OrderSide.sell, price: 100);
      expect(above.type, PendingOrderType.limit);
      expect(below.type, PendingOrderType.stop);
      expect(equal.type, PendingOrderType.stop);
    });

    test('updatePendingOrderPrice re-resolves the type', () {
      final e = engine([mk(0, 100, 101, 99, 100)]);
      final o = e.placePendingOrder(side: OrderSide.buy, price: 90);
      expect(o.type, PendingOrderType.limit);
      e.updatePendingOrderPrice(o.id, 120);
      expect(e.pendingOrders.single.type, PendingOrderType.stop);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Market entry cancels pending orders and locks initialRisk
  // ---------------------------------------------------------------------------
  group('executeMarketOrder', () {
    test('cancels pending orders and locks initialRisk', () {
      final e = engine([mk(0, 100, 101, 99, 100)]);
      e.placePendingOrder(side: OrderSide.buy, price: 90);
      e.placePendingOrder(side: OrderSide.sell, price: 110);
      expect(e.pendingOrders.length, 2);

      final pos = e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      expect(e.pendingOrders, isEmpty);
      expect(pos.entryPrice, 100);
      expect(pos.initialSl, 95);
      expect(pos.currentSl, 95);
      expect(pos.initialRisk, 5);
      expect(
        pos.events.any((ev) => ev.type == OrderEventType.filled),
        isTrue,
      );
      expect(
        pos.events.any((ev) => ev.type == OrderEventType.slSet),
        isTrue,
      );
    });

    test('throws when a position is already open', () {
      final e = engine([mk(0, 100, 101, 99, 100)]);
      e.executeMarketOrder(side: OrderSide.buy);
      expect(() => e.executeMarketOrder(side: OrderSide.sell),
          throwsStateError);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Stop-loss trigger, MFE_R / MAE_R, slHistory trail
  // ---------------------------------------------------------------------------
  group('stop-loss and excursion metrics', () {
    test('bar-by-bar SL trigger computes realized/MFE/MAE', () {
      final e = engine([
        mk(0, 100, 100, 100, 100),
        mk(1, 100, 108, 97, 105),
        mk(2, 100, 96, 94, 95),
      ], max: 2);

      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      expect(e.stepForward(Timeframe.m1), 1); // -> bar 1
      expect(e.openPosition, isNotNull);
      expect(e.openPosition!.bestPrice, 108);
      expect(e.openPosition!.worstPrice, 97);

      e.stepForward(Timeframe.m1); // -> bar 2, SL hit
      expect(e.openPosition, isNull);
      expect(e.closedTrades, hasLength(1));

      final t = e.closedTrades.single;
      expect(t.exitReason, ExitReason.stopLoss);
      expect(t.exitPrice, 95);
      expect(t.pnlPoints, closeTo(-5, 1e-9));
      expect(t.realizedR, closeTo(-1, 1e-9));
      expect(t.mfeR, closeTo(1.6, 1e-9)); // (108-100)/5
      expect(t.maeR, closeTo(1.2, 1e-9)); // (100-94)/5
    });

    test('slHistory trails updates and removal', () {
      final e = engine([mk(0, 100, 100, 100, 100)]);
      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);

      e.updateStopLoss(96);
      var pos = e.openPosition!;
      expect(pos.currentSl, 96);
      expect(pos.slHistory, hasLength(1));
      expect(pos.slHistory.single.oldSl, 95);
      expect(pos.slHistory.single.newSl, 96);
      expect(pos.slHistory.single.reason, 'SL updated');
      expect(
        pos.events.any((ev) => ev.type == OrderEventType.slModified),
        isTrue,
      );

      e.removeStopLoss();
      pos = e.openPosition!;
      expect(pos.currentSl, isNull);
      expect(pos.slHistory, hasLength(2));
      expect(pos.slHistory.last.oldSl, 96);
      expect(pos.slHistory.last.newSl, isNull);
      expect(pos.slHistory.last.reason, 'SL removed');
      expect(
        pos.events.any((ev) => ev.type == OrderEventType.slRemoved),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Step-back guards
  // ---------------------------------------------------------------------------
  group('stepBack guards', () {
    test('blocks while a position is open', () {
      final e = engine([for (int i = 0; i < 21; i++) mk(i, 100, 101, 99, 100)],
          start: 10, max: 20);
      e.stepForward(Timeframe.m1, steps: 5); // -> 15
      expect(e.cursorIndex, 15);
      expect(e.canStepBack(Timeframe.m1, steps: 3), isTrue);

      e.executeMarketOrder(side: OrderSide.buy);
      expect(e.canStepBack(Timeframe.m1), isFalse);
      expect(e.stepBack(Timeframe.m1), isFalse);
    });

    test('blocks before the last closed trade exit bar', () {
      final e = engine([for (int i = 0; i < 21; i++) mk(i, 100, 101, 99, 100)],
          start: 10, max: 20);
      e.executeMarketOrder(side: OrderSide.buy);
      e.stepForward(Timeframe.m1, steps: 5); // -> 15
      e.closePositionManually(); // exit at 15

      expect(e.canStepBack(Timeframe.m1, steps: 1), isFalse);
      expect(e.stepBack(Timeframe.m1), isFalse);
    });

    test('allows step-back down to the minimum cursor when flat', () {
      final e = engine([for (int i = 0; i < 21; i++) mk(i, 100, 101, 99, 100)],
          start: 10, max: 20);
      e.stepForward(Timeframe.m1, steps: 5); // -> 15
      expect(e.stepBack(Timeframe.m1, steps: 3), isTrue);
      expect(e.cursorIndex, 12);
      expect(e.stepBack(Timeframe.m1, steps: 5), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Window-end auto-close
  // ---------------------------------------------------------------------------
  group('window end', () {
    test('closes open position and marks completed', () {
      final e = engine([
        mk(0, 100, 100, 100, 100),
        mk(1, 100, 102, 99, 101),
        mk(2, 101, 103, 100, 102),
        mk(3, 102, 104, 101, 103),
      ], max: 3);

      e.executeMarketOrder(side: OrderSide.buy, stopLoss: 95);
      final advanced = e.stepForward(Timeframe.m1, steps: 10);
      expect(advanced, 3);
      expect(e.cursorIndex, 3);
      expect(e.isCompleted, isTrue);
      expect(e.openPosition, isNull);
      expect(e.closedTrades, hasLength(1));
      expect(e.closedTrades.single.exitReason, ExitReason.windowEnd);
      expect(e.closedTrades.single.exitPrice, 103);
    });

    test('cancels remaining pending orders at window end', () {
      final e = engine([
        mk(0, 100, 100, 100, 100),
        mk(1, 100, 101, 99, 100),
        mk(2, 100, 101, 99, 100),
      ], max: 2);

      e.placePendingOrder(side: OrderSide.buy, price: 50);
      e.stepForward(Timeframe.m1, steps: 10);
      expect(e.isCompleted, isTrue);
      expect(e.pendingOrders, isEmpty);
      expect(e.closedTrades, isEmpty);
    });
  });
}
