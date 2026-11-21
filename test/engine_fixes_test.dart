import 'package:flutter_test/flutter_test.dart';
import 'package:alert_app/models/market_models.dart';
import 'package:alert_app/services/candlestick_detector.dart';
import 'package:alert_app/services/alert_manager.dart';
import 'package:alert_app/services/alarm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 5: Candlestick Pattern Detection Timing', () {
    test('strictly filters out open forming candle and evaluates closed candles', () {
      final now = DateTime.now();
      // Setup: 3 closed candles where candle[-2] engulfs candle[-3]
      // plus an active open candle at index 3 that is forming
      final candles = [
        BiquoteCandle(
          openTime: now.subtract(const Duration(minutes: 60)),
          open: 1.1000,
          high: 1.1050,
          low: 1.0980,
          close: 1.1020,
          isOpen: false,
        ),
        BiquoteCandle(
          openTime: now.subtract(const Duration(minutes: 45)),
          open: 1.1020,
          high: 1.1030,
          low: 1.0950,
          close: 1.0960, // Bearish candle
          isOpen: false,
        ),
        BiquoteCandle(
          openTime: now.subtract(const Duration(minutes: 30)),
          open: 1.0950,
          high: 1.1060,
          low: 1.0940,
          close: 1.1050, // Bullish engulfing (closed bar)
          isOpen: false,
        ),
        BiquoteCandle(
          openTime: now.subtract(const Duration(minutes: 15)),
          open: 1.1050,
          high: 1.1055,
          low: 1.1010,
          close: 1.1015, // Forming bar (not closed yet!)
          isOpen: true,
        ),
      ];

      // When requireClosedCandle is true, it should ignore the open forming bar
      // and match the bullish engulfing from the confirmed closed candle!
      final matched = CandlestickDetector.matches(
        CandlestickPattern.bullishEngulfing,
        candles,
        requireClosedCandle: true,
      );
      expect(matched, isTrue);
    });
  });

  group('Issue 4: Step Timeout / Expiry Window Enforcement', () {
    test('isTimedOut correctly identifies expired step and auto-resets', () {
      final stage1 = ChainStage(
        id: 's1',
        name: 'Stage 1',
        timeoutMinutes: 15,
        isCompleted: true,
        completedAt: DateTime.now().subtract(const Duration(minutes: 20)),
        nodes: [
          ChainNode(
            id: 'n1',
            nodeType: AlertType.priceLevel,
            targetPrice: 1.1500,
            isSatisfied: true,
          ),
        ],
      );

      final stage2 = ChainStage(
        id: 's2',
        name: 'Stage 2',
        timeoutMinutes: 30,
        isCompleted: false,
        nodes: [
          ChainNode(
            id: 'n2',
            nodeType: AlertType.priceLevel,
            targetPrice: 1.1550,
            isSatisfied: false,
          ),
        ],
      );

      final config = MultiStepConfig(
        stages: [stage1, stage2],
        currentStageIndex: 1,
      );

      // Now is 20 minutes after stage 1 completed, which exceeds the 15-minute timeout!
      expect(config.isTimedOut(DateTime.now()), isTrue);

      // Resetting invalidates the sequence back to Stage 1
      config.reset();
      expect(config.currentStageIndex, equals(0));
      expect(stage1.isCompleted, isFalse);
      expect(stage1.nodes.first.isSatisfied, isFalse);
      expect(config.isTimedOut(DateTime.now()), isFalse);
    });

    test('isTimedOut returns false when within timeout window', () {
      final stage1 = ChainStage(
        id: 's1',
        name: 'Stage 1',
        timeoutMinutes: 30,
        isCompleted: true,
        completedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        nodes: [
          ChainNode(id: 'n1', nodeType: AlertType.priceLevel, isSatisfied: true),
        ],
      );
      final stage2 = ChainStage(
        id: 's2',
        name: 'Stage 2',
        nodes: [
          ChainNode(id: 'n2', nodeType: AlertType.priceLevel),
        ],
      );

      final config = MultiStepConfig(
        stages: [stage1, stage2],
        currentStageIndex: 1,
      );

      expect(config.isTimedOut(DateTime.now()), isFalse);
    });

    test('timeRemaining calculates remaining active stage duration accurately', () {
      final now = DateTime.now();
      final stage1 = ChainStage(
        id: 's1',
        name: 'Stage 1',
        timeoutMinutes: 30,
        isCompleted: true,
        completedAt: now.subtract(const Duration(minutes: 10)),
        nodes: [ChainNode(id: 'n1', nodeType: AlertType.priceLevel, isSatisfied: true)],
      );
      final stage2 = ChainStage(
        id: 's2',
        name: 'Stage 2',
        nodes: [ChainNode(id: 'n2', nodeType: AlertType.priceLevel)],
      );
      final config = MultiStepConfig(
        stages: [stage1, stage2],
        currentStageIndex: 1,
      );

      final rem = config.timeRemaining(now);
      expect(rem, isNotNull);
      expect(rem!.inMinutes, equals(20));

      // Expired stage returns Duration.zero
      final futureNow = now.add(const Duration(minutes: 25));
      expect(config.timeRemaining(futureNow), equals(Duration.zero));
    });
  });

  group('Issue 7 & Issue 1: Stateful Boundary Crossing & Hysteresis Cooldown', () {
    test('checkTrigger prevents false-positive instant triggers when baseline is already above target', () {
      // Alert created when price is ALREADY above target (1.1550 > 1.1500)
      final alert = PriceAlert(
        id: 'false_positive_guard',
        symbol: 'EURUSD',
        targetPrice: 1.1500,
        condition: AlertCondition.crossesAbove,
        createdAt: DateTime.now(),
        initialPrice: 1.1550,
      );

      // Tick 1: Price still above target (1.1560) -> MUST NOT trigger!
      expect(alert.checkTrigger(1.1560), isFalse);

      // Tick 2: Price dips below target (1.1490) -> does not trigger
      expect(alert.checkTrigger(1.1490), isFalse);

      // Tick 3: Price crosses from below (1.1490) to at/above (1.1505) -> TRUE!
      expect(alert.checkTrigger(1.1505), isTrue);

      // Tick 4: Price remains above (1.1510) -> does not re-trigger
      expect(alert.checkTrigger(1.1510), isFalse);
    });

    test('checkTrigger enforces cooldown deadband with true re-crossing', () {
      final now = DateTime.now();
      final alert = PriceAlert(
        id: 'alert_cooldown_test',
        symbol: 'EURUSD',
        targetPrice: 1.1500,
        condition: AlertCondition.crossesAbove,
        createdAt: now,
        initialPrice: 1.1480,
        cooldownMinutes: 5,
      );

      // 1. Initial price crosses above target: should trigger
      expect(alert.checkTrigger(1.1510, now: now), isTrue);

      // Mark as triggered at T=0
      alert.lastTriggeredAt = now;

      // 2. Price dips below target at T+1m
      final oneMinLater = now.add(const Duration(minutes: 1));
      expect(alert.checkTrigger(1.1490, now: oneMinLater), isFalse);

      // 3. Price crosses back above target at T+2m: within 5-min cooldown, MUST be suppressed
      final twoMinLater = now.add(const Duration(minutes: 2));
      expect(alert.checkTrigger(1.1520, now: twoMinLater), isFalse);

      // 4. Price dips below target again at T+5m30s
      final fiveMinLater = now.add(const Duration(minutes: 5, seconds: 30));
      expect(alert.checkTrigger(1.1490, now: fiveMinLater), isFalse);

      // 5. Price crosses back above target at T+6m: cooldown expired, MUST trigger!
      final sixMinLater = now.add(const Duration(minutes: 6));
      expect(alert.checkTrigger(1.1520, now: sixMinLater), isTrue);
    });
  });

  group('Issue 3: Multi-Currency Strategy Deployment', () {
    test('createMultiSymbolAlerts clones independent stages with genuine per-symbol prices', () {
      final alertManager = AlertManager(alarmService: AlarmService());

      final stages = [
        ChainStage(
          id: 'stg_1',
          name: 'Stage 1 Breakout',
          timeoutMinutes: 30,
          nodes: [
            ChainNode(
              id: 'nd_1',
              nodeType: AlertType.priceLevel,
              targetPrice: 1.2000,
              condition: AlertCondition.crossesAbove,
            ),
          ],
        ),
      ];

      final symbolPrices = {
        'EURUSD': 1.0850,
        'USDJPY': 155.30,
        'XAUUSD': 2650.00,
      };

      final created = alertManager.createMultiSymbolAlerts(
        symbols: ['EURUSD', 'USDJPY', 'XAUUSD'],
        alertType: AlertType.multiStepChain,
        multiStepConfig: MultiStepConfig(stages: stages),
        currentPrice: 1.0850,
        symbolPrices: symbolPrices,
        cooldownMinutes: 5,
        triggerOnCandleClose: true,
      );

      expect(created.length, equals(3));
      expect(created.map((a) => a.symbol).toList(), equals(['EURUSD', 'USDJPY', 'XAUUSD']));

      // Each symbol must receive its genuine current market price
      expect(created[0].initialPrice, equals(1.0850));
      expect(created[1].initialPrice, equals(155.30));
      expect(created[2].initialPrice, equals(2650.00));

      // Each symbol must have its own independent MultiStepConfig instance
      expect(created[0].multiStepConfig, isNot(same(created[1].multiStepConfig)));
      expect(created[0].multiStepConfig!.stages.first.id, contains('EURUSD'));
      expect(created[1].multiStepConfig!.stages.first.id, contains('USDJPY'));
      expect(created[2].multiStepConfig!.stages.first.id, contains('XAUUSD'));

      // Modifying stage on EURUSD must NOT affect USDJPY
      created[0].multiStepConfig!.stages.first.isCompleted = true;
      expect(created[1].multiStepConfig!.stages.first.isCompleted, isFalse);
    });
  });

  group('Issue 10 & 11: Mixed Node Types & Persistence Serialization', () {
    test('JSON serialization preserves all advanced engine parameters', () {
      final alert = PriceAlert(
        id: 'full_test_1',
        symbol: 'EURUSD',
        alertType: AlertType.multiStepChain,
        createdAt: DateTime.now(),
        initialPrice: 1.1500,
        triggerOnCandleClose: true,
        cooldownMinutes: 15,
        lastTriggeredAt: DateTime.parse('2026-10-13T05:00:00Z'),
        targetSymbols: ['EURUSD', 'GBPUSD'],
        multiStepConfig: MultiStepConfig(
          stages: [
            ChainStage(
              id: 's1',
              name: 'Level 1 Mixed',
              timeoutMinutes: 45,
              isCompleted: true,
              completedAt: DateTime.parse('2026-10-13T05:30:00Z'),
              nodes: [
                ChainNode(
                  id: 'n1',
                  nodeType: AlertType.priceLevel,
                  targetPrice: 1.1550,
                  isSatisfied: true,
                  satisfiedAt: DateTime.parse('2026-10-13T05:25:00Z'),
                ),
                ChainNode(
                  id: 'n2',
                  nodeType: AlertType.candlestickPattern,
                  candlestickPattern: CandlestickPattern.hammer,
                  operatorToPrevious: 'OR',
                  isSatisfied: false,
                ),
              ],
            ),
          ],
        ),
      );

      final json = alert.toJson();
      final recovered = PriceAlert.fromJson(json);

      expect(recovered.triggerOnCandleClose, isTrue);
      expect(recovered.cooldownMinutes, equals(15));
      expect(recovered.lastTriggeredAt, equals(DateTime.parse('2026-10-13T05:00:00Z')));
      expect(recovered.targetSymbols, equals(['EURUSD', 'GBPUSD']));

      final recConfig = recovered.multiStepConfig!;
      expect(recConfig.stages.first.timeoutMinutes, equals(45));
      expect(recConfig.stages.first.isCompleted, isTrue);
      expect(recConfig.stages.first.completedAt, equals(DateTime.parse('2026-10-13T05:30:00Z')));
      expect(recConfig.stages.first.nodes[0].isSatisfied, isTrue);
      expect(recConfig.stages.first.nodes[1].operatorToPrevious, equals('OR'));
    });
  });
}
