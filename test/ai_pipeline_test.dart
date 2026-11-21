import 'package:flutter_test/flutter_test.dart';
import 'package:alert_app/models/ai_models.dart';
import 'package:alert_app/models/market_models.dart';
import 'package:alert_app/services/ai_service.dart';
import 'package:alert_app/services/candlestick_detector.dart';
import 'package:alert_app/services/indicator_calculator.dart';
import 'package:alert_app/services/realmarket_service.dart';

void main() {
  group('AI Models & Strategy Unit Tests', () {
    test('TradingStrategy serialization and defaults', () {
      final defaultAureus = TradingStrategy.aureusDefault();
      expect(defaultAureus.specialists.length, 2);
      expect(defaultAureus.isMultiAgent, true);

      final jsonMap = defaultAureus.toJson();
      final reconstituted = TradingStrategy.fromJson(jsonMap);

      expect(reconstituted.id, 'aureus_default');
      expect(reconstituted.specialists.length, 2);
      expect(reconstituted.specialists[0].name, 'SMC Structure Specialist');
      expect(reconstituted.specialists[1].name, 'Wyckoff Phase Specialist');

      final singleStrat = TradingStrategy.singleAnalystDefault();
      expect(singleStrat.specialists.length, 1);
      expect(singleStrat.isMultiAgent, false);
    });

    test('AgentSignal JSON extraction from markdown code fences', () {
      const sampleMarkdownResponse = '''
Here is the detailed market assessment:
The price has swept the sell-side liquidity at 1.1520 and formed an unmitigated order block on the 1h timeframe.

```json
{
  "direction": "buy",
  "analysis": "Liquidity sweep below equal lows followed by strong displacement candle breaking structure.",
  "theory": "Smart money accumulation phase into premium discount zone.",
  "entry_price": 1.15450,
  "stop_loss": 1.15120,
  "take_profit": 1.16200,
  "confidence": 9
}
```
Additional commentary: Maintain strict 1:2.3 risk-to-reward ratio.
''';

      final signal = AiService.extractSignalFromJson(
        sampleMarkdownResponse,
        agentName: 'SMC Structure Specialist',
      );

      expect(signal.direction, SignalDirection.buy);
      expect(signal.entryPrice, 1.15450);
      expect(signal.stopLoss, 1.15120);
      expect(signal.takeProfit, 1.16200);
      expect(signal.confidence, 9);
      expect(signal.hasValidTradeSetup, true);
      expect(signal.riskRewardRatio, greaterThan(2.0));
    });

    test('AgentSignal extraction handles direct raw JSON string', () {
      const rawJson = '''
{
  "direction": "sell",
  "analysis": "Wyckoff UTAD phase confirmed after buying climax rejection.",
  "theory": "Distribution complete; entering markdown phase.",
  "entry_price": 155.80,
  "stop_loss": 156.40,
  "take_profit": 154.20,
  "confidence": 8
}
''';

      final signal = AiService.extractSignalFromJson(
        rawJson,
        agentName: 'Wyckoff Phase Specialist',
      );

      expect(signal.direction, SignalDirection.sell);
      expect(signal.entryPrice, 155.80);
      expect(signal.stopLoss, 156.40);
      expect(signal.takeProfit, 154.20);
      expect(signal.confidence, 8);
      expect(signal.hasValidTradeSetup, true);
    });

    test('AgentSignal handles wait/neutral condition', () {
      const waitJson = '''
{
  "direction": "wait",
  "analysis": "Models in direct contradiction: SMC is bullish while Wyckoff indicates distribution.",
  "theory": "Ambiguous market regime. Preservation of capital recommended.",
  "entry_price": 1.1540,
  "stop_loss": 1.1540,
  "take_profit": 1.1540,
  "confidence": 4
}
''';

      final signal = AiService.extractSignalFromJson(
        waitJson,
        agentName: 'Metareasoning Consolidator',
      );

      expect(signal.direction, SignalDirection.wait);
      expect(signal.confidence, 4);
      expect(signal.hasValidTradeSetup, false);
    });

    test('RealMarketService symbol and timeframe resolver mappings', () {
      final rm = RealMarketService();

      expect(rm.resolveSymbolCode('EUR/USD'), 'EURUSD');
      expect(rm.resolveSymbolCode('gold'), 'XAUUSD');
      expect(rm.resolveSymbolCode('XAU/USD'), 'XAUUSD');
      expect(rm.resolveSymbolCode('BTC-USD'), 'BTCUSD');

      expect(rm.resolveTimeFrame('1H'), 'H1');
      expect(rm.resolveTimeFrame('15M'), 'M15');
      expect(rm.resolveTimeFrame('4h'), 'H4');
      expect(rm.resolveTimeFrame('1D'), 'D1');
    });

    test('AgentSignal symbol serialization and PipelineRunResult.finalSignal symbol propagation', () {
      final sig = AgentSignal(
        direction: SignalDirection.buy,
        analysis: 'Test analysis',
        theory: 'Test theory',
        entryPrice: 1.1550,
        stopLoss: 1.1500,
        takeProfit: 1.1650,
        confidence: 8,
        agentName: 'TestAgent',
        timestamp: DateTime.now(),
        symbol: 'GBPUSD',
      );

      expect(sig.symbol, 'GBPUSD');
      final json = sig.toJson();
      expect(json['symbol'], 'GBPUSD');

      final reconstituted = AgentSignal.fromJson(json);
      expect(reconstituted.symbol, 'GBPUSD');

      final sigWithoutSymbol = AgentSignal(
        direction: SignalDirection.buy,
        analysis: 'Test analysis',
        theory: 'Test theory',
        entryPrice: 1.1550,
        stopLoss: 1.1500,
        takeProfit: 1.1650,
        confidence: 8,
        agentName: 'TestAgent',
        timestamp: DateTime.now(),
      );

      final pipelineResult = PipelineRunResult(
        strategy: TradingStrategy.aureusDefault(),
        symbol: 'USDJPY',
        timeframe: '15M',
        initialSpecialistSignals: [sigWithoutSymbol],
        groundingCritique: 'Clean audit',
        refinedSpecialistSignals: [sigWithoutSymbol],
        consolidatedSignal: null,
        timestamp: DateTime.now(),
      );

      expect(pipelineResult.finalSignal.symbol, 'USDJPY');
    });
  });

  group('Technical Indicators & Candlestick Pattern Logic Tests', () {
    test('IndicatorCalculator RSI calculation produces accurate values bounded 0-100', () {
      final prices = <double>[
        44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08,
        45.89, 46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22, 45.64,
      ];

      final rsiSeries = IndicatorCalculator.calculateRsiSeriesFromPrices(prices, 14, smoothingType: 'RMA');
      expect(rsiSeries.isNotEmpty, true);
      for (final val in rsiSeries) {
        expect(val, greaterThanOrEqualTo(0.0));
        expect(val, lessThanOrEqualTo(100.0));
      }
    });

    test('CandlestickDetector correctly identifies Bullish and Bearish Engulfing patterns', () {
      final now = DateTime.now();

      // Bearish candle followed by larger Bullish engulfing candle
      final redCandle = BiquoteCandle(
        openTime: now.subtract(const Duration(minutes: 5)),
        open: 1.1550,
        high: 1.1560,
        low: 1.1530,
        close: 1.1535,
        tickVolume: 100,
      );

      final greenEngulfing = BiquoteCandle(
        openTime: now,
        open: 1.1530,
        high: 1.1580,
        low: 1.1525,
        close: 1.1575,
        tickVolume: 150,
      );

      final candles = <BiquoteCandle>[
        BiquoteCandle(
          openTime: now.subtract(const Duration(minutes: 10)),
          open: 1.1560,
          high: 1.1570,
          low: 1.1540,
          close: 1.1555,
          tickVolume: 80,
        ),
        redCandle,
        greenEngulfing,
      ];

      final isBullishEngulfing = CandlestickDetector.matches(CandlestickPattern.bullishEngulfing, candles);
      expect(isBullishEngulfing, true);

      final isBearishEngulfing = CandlestickDetector.matches(CandlestickPattern.bearishEngulfing, candles);
      expect(isBearishEngulfing, false);
    });

    test('PriceAlert correctly detects price level crossings', () {
      final alertAbove = PriceAlert(
        id: 'test_above',
        symbol: 'EURUSD',
        targetPrice: 1.1500,
        condition: AlertCondition.crossesAbove,
        initialPrice: 1.1450,
        createdAt: DateTime.now(),
      );

      expect(alertAbove.checkTrigger(1.1480), false);
      expect(alertAbove.checkTrigger(1.1501), true);

      final alertBelow = PriceAlert(
        id: 'test_below',
        symbol: 'EURUSD',
        targetPrice: 1.1400,
        condition: AlertCondition.crossesBelow,
        initialPrice: 1.1450,
        createdAt: DateTime.now(),
      );

      expect(alertBelow.checkTrigger(1.1420), false);
      expect(alertBelow.checkTrigger(1.1395), true);
    });
  });
}
