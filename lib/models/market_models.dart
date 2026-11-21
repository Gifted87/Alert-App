import 'package:intl/intl.dart';

enum AlertCondition {
  crossesAbove('Crosses Above'),
  crossesBelow('Crosses Below'),
  hits('Hits');

  final String label;
  const AlertCondition(this.label);
}

class BiquoteTick {
  final String symbol;
  final String description;
  final double bid;
  final double ask;
  final double mid;
  final double spread;
  final double high;
  final double low;
  final String direction;
  final double dayDiffPercent;
  final DateTime timestamp;
  final String source;
  final String marketState;
  final bool stale;
  final int quoteAgeSeconds;

  BiquoteTick({
    required this.symbol,
    required this.description,
    required this.bid,
    required this.ask,
    required this.mid,
    required this.spread,
    required this.high,
    required this.low,
    required this.direction,
    required this.dayDiffPercent,
    required this.timestamp,
    required this.source,
    required this.marketState,
    required this.stale,
    required this.quoteAgeSeconds,
  });

  bool get isMarketClosed => marketState == 'closed' || stale;
  bool get isBullish => dayDiffPercent >= 0;

  int get precision {
    if (symbol.contains('JPY')) return 3;
    if (symbol.contains('BTC') || symbol.contains('ETH')) return 2;
    if (symbol.contains('XAU')) return 2;
    return 5;
  }

  factory BiquoteTick.fromJson(Map<String, dynamic> json) {
    return BiquoteTick(
      symbol: json['symbol'] as String? ?? '',
      description: json['description'] as String? ?? '',
      bid: (json['bid'] as num?)?.toDouble() ?? 0.0,
      ask: (json['ask'] as num?)?.toDouble() ?? 0.0,
      mid: (json['mid'] as num?)?.toDouble() ?? 0.0,
      spread: (json['spread'] as num?)?.toDouble() ?? 0.0,
      high: (json['high'] as num?)?.toDouble() ?? 0.0,
      low: (json['low'] as num?)?.toDouble() ?? 0.0,
      direction: json['direction'] as String? ?? 'FLAT',
      dayDiffPercent: (json['dayDiffPercent'] as num?)?.toDouble() ?? 0.0,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? '',
      marketState: json['marketState'] as String? ?? 'open',
      stale: json['stale'] as bool? ?? false,
      quoteAgeSeconds: (json['quoteAgeSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  // Safe placeholder tick when awaiting live feed subscription seed
  factory BiquoteTick.placeholder({
    required String symbol,
    double price = 0.0,
  }) {
    final defaultPrice = symbol.contains('XAU')
        ? 2650.40
        : symbol.contains('BTC')
        ? 67240.0
        : symbol.contains('JPY')
        ? 155.30
        : symbol.contains('GBP')
        ? 1.30512
        : 1.08548;
    final finalPrice = price > 0 ? price : defaultPrice;
    final defaultDayDiff = symbol.contains('XAU') ? -0.38 : 0.12;

    return BiquoteTick(
      symbol: symbol,
      description: symbol,
      bid: finalPrice,
      ask: finalPrice,
      mid: finalPrice,
      spread: 0.0001,
      high: finalPrice * 1.002,
      low: finalPrice * 0.998,
      direction: defaultDayDiff >= 0 ? 'UP' : 'DOWN',
      dayDiffPercent: defaultDayDiff,
      timestamp: DateTime.now(),
      source: 'Default Market Baseline',
      marketState: 'open',
      stale: false,
      quoteAgeSeconds: 0,
    );
  }
}

class BiquoteCandle {
  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final int tickVolume;
  final bool isOpen;

  BiquoteCandle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.tickVolume = 1,
    this.isOpen = false,
  });

  bool get isBullish => close >= open;
  double get range => high - low;
  double get bodyRange => (close - open).abs();

  BiquoteCandle copyWith({
    DateTime? openTime,
    double? open,
    double? high,
    double? low,
    double? close,
    int? tickVolume,
    bool? isOpen,
  }) {
    return BiquoteCandle(
      openTime: openTime ?? this.openTime,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      tickVolume: tickVolume ?? this.tickVolume,
      isOpen: isOpen ?? this.isOpen,
    );
  }

  BiquoteCandle updateWithTick(double newPrice) {
    return copyWith(
      close: newPrice,
      high: newPrice > high ? newPrice : high,
      low: newPrice < low ? newPrice : low,
      tickVolume: tickVolume + 1,
      isOpen: true,
    );
  }

  factory BiquoteCandle.fromJson(Map<String, dynamic> json) {
    return BiquoteCandle(
      openTime:
          DateTime.tryParse(json['openTime'] as String? ?? '') ??
          DateTime.now(),
      open: (json['open'] as num?)?.toDouble() ?? 0.0,
      high: (json['high'] as num?)?.toDouble() ?? 0.0,
      low: (json['low'] as num?)?.toDouble() ?? 0.0,
      close: (json['close'] as num?)?.toDouble() ?? 0.0,
      tickVolume: (json['tickVolume'] as num?)?.toInt() ?? 0,
      isOpen: json['isOpen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'openTime': openTime.toIso8601String(),
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'tickVolume': tickVolume,
      'isOpen': isOpen,
    };
  }
}

enum AlertType {
  priceLevel('Price Level'),
  candlestickPattern('Candlestick Pattern'),
  technicalIndicator('Indicator Alert'),
  multiStepChain('Logic Chain (Multi-Step)'),
  timeSchedule('Scheduled Event / Calendar Alarm');

  final String label;
  const AlertType(this.label);
}

enum AlertIndicatorType {
  rsi('RSI', 'Relative Strength Index'),
  macd('MACD', 'Moving Average Convergence Divergence'),
  maCross('MA Cross', 'Moving Average Cross (EMA/SMA)'),
  bollingerBands('Bollinger', 'Volatility Bands (Upper/Lower/Squeeze)'),
  stochastic('Stochastic', 'Momentum Oscillator (%K / %D)'),
  supertrend('Supertrend', 'ATR Trailing Trend Channel');

  final String label;
  final String description;
  const AlertIndicatorType(this.label, this.description);
}

class IndicatorAlertConfig {
  final AlertIndicatorType indicatorType;
  final String condition;
  final Map<String, dynamic> params;

  IndicatorAlertConfig({
    required this.indicatorType,
    required this.condition,
    this.params = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'indicatorType': indicatorType.name,
      'condition': condition,
      'params': params,
    };
  }

  factory IndicatorAlertConfig.fromJson(Map<String, dynamic> json) {
    AlertIndicatorType type = AlertIndicatorType.rsi;
    for (final it in AlertIndicatorType.values) {
      if (it.name == json['indicatorType']) {
        type = it;
        break;
      }
    }
    return IndicatorAlertConfig(
      indicatorType: type,
      condition: json['condition'] as String? ?? 'crossesAbove',
      params: (json['params'] as Map<String, dynamic>?) ?? {},
    );
  }

  String get summary {
    switch (indicatorType) {
      case AlertIndicatorType.rsi:
        final period = params['period'] ?? 14;
        final level = params['level'] ?? 30;
        final signalMaType = params['signalMaType'] ?? 'EMA';
        final signalMaPeriod = params['signalMaPeriod'] ?? 9;
        final source = params['source'] ?? 'Close';
        final smoothing = params['smoothingType'] ?? 'RMA';
        final ob = params['overbought'] ?? 70;
        final os = params['oversold'] ?? 30;
        final srcStr = source != 'Close' ? ' [$source]' : '';
        final smoothStr = smoothing != 'RMA' ? ' $smoothing' : '';
        final pStr = '$period$srcStr$smoothStr';

        if (condition == 'crossesAboveSignalMa') {
          return 'RSI($pStr) crosses above $signalMaType($signalMaPeriod) of RSI';
        } else if (condition == 'crossesBelowSignalMa') {
          return 'RSI($pStr) crosses below $signalMaType($signalMaPeriod) of RSI';
        } else if (condition == 'crossesAbove' ||
            condition == 'crossesAboveLevel') {
          return 'RSI($pStr) crosses above $level';
        } else if (condition == 'crossesBelow' ||
            condition == 'crossesBelowLevel') {
          return 'RSI($pStr) crosses below $level';
        } else if (condition == 'crossesBelowOversold') {
          return 'RSI($pStr) crosses below Oversold ($os)';
        } else if (condition == 'crossesAboveOversold') {
          return 'RSI($pStr) recovers above Oversold ($os)';
        } else if (condition == 'crossesAboveOverbought') {
          return 'RSI($pStr) crosses above Overbought ($ob)';
        } else if (condition == 'crossesBelowOverbought') {
          return 'RSI($pStr) falls below Overbought ($ob)';
        } else if (condition == 'overboughtEnter') {
          return 'RSI($pStr) enters Overbought (>$ob)';
        } else if (condition == 'oversoldEnter') {
          return 'RSI($pStr) enters Oversold (<$os)';
        } else if (condition == 'crossesAboveCenterline') {
          return 'RSI($pStr) crosses above 50 (Bullish Momentum)';
        } else if (condition == 'crossesBelowCenterline') {
          return 'RSI($pStr) crosses below 50 (Bearish Momentum)';
        } else if (condition == 'inOversold') {
          return 'RSI($pStr) is in Oversold Zone (<$os)';
        } else if (condition == 'inOverbought') {
          return 'RSI($pStr) is in Overbought Zone (>$ob)';
        } else if (condition == 'inBandRange') {
          return 'RSI($pStr) is inside Range ($os - $ob)';
        } else if (condition == 'outsideBandRange') {
          return 'RSI($pStr) is outside Range (<$os or >$ob)';
        } else if (condition == 'rsiTurningUp') {
          return 'RSI($pStr) hooks Upward (Inflection)';
        } else if (condition == 'rsiTurningDown') {
          return 'RSI($pStr) hooks Downward (Exhaustion)';
        } else {
          return 'RSI($pStr) crosses Centerline';
        }
      case AlertIndicatorType.macd:
        final fast = params['fast'] ?? 12;
        final slow = params['slow'] ?? 26;
        final signal = params['signal'] ?? 9;
        final source = params['source'] ?? 'Close';
        final fastMaType = params['fastMaType'] ?? 'EMA';
        final slowMaType = params['slowMaType'] ?? 'EMA';
        final signalMaType = params['signalMaType'] ?? 'EMA';
        final srcStr = source != 'Close' ? ' [$source]' : '';
        final typeStr =
            (fastMaType != 'EMA' ||
                slowMaType != 'EMA' ||
                signalMaType != 'EMA')
            ? ' {$fastMaType,$slowMaType,$signalMaType}'
            : '';
        final mStr = 'MACD($fast,$slow,$signal$srcStr$typeStr)';

        if (condition == 'bullishSignalCross') {
          return '$mStr Bullish Signal Cross';
        } else if (condition == 'bearishSignalCross') {
          return '$mStr Bearish Signal Cross';
        } else if (condition == 'zeroLineCrossAbove' ||
            condition == 'zeroCrossAbove') {
          return '$mStr crosses above 0';
        } else if (condition == 'zeroLineCrossBelow' ||
            condition == 'zeroCrossBelow') {
          return '$mStr crosses below 0';
        } else if (condition == 'signalZeroCrossAbove') {
          return '$mStr Signal crosses above 0';
        } else if (condition == 'signalZeroCrossBelow') {
          return '$mStr Signal crosses below 0';
        } else if (condition == 'histogramFlipPositive') {
          return '$mStr Histogram flips Positive (>0)';
        } else if (condition == 'histogramFlipNegative') {
          return '$mStr Histogram flips Negative (<0)';
        } else if (condition == 'macdAboveSignal') {
          return '$mStr Line > Signal (Bullish Momentum)';
        } else if (condition == 'macdBelowSignal') {
          return '$mStr Line < Signal (Bearish Momentum)';
        } else if (condition == 'macdAboveZero') {
          return '$mStr Line > 0 (Bullish Territory)';
        } else if (condition == 'macdBelowZero') {
          return '$mStr Line < 0 (Bearish Territory)';
        } else if (condition == 'histogramPositive') {
          return '$mStr Histogram > 0';
        } else if (condition == 'histogramNegative') {
          return '$mStr Histogram < 0';
        } else if (condition == 'histogramTurningUp') {
          return '$mStr Histogram hooks Upward (Recovery)';
        } else if (condition == 'histogramTurningDown') {
          return '$mStr Histogram hooks Downward (Exhaustion)';
        } else if (condition == 'macdTurningUp') {
          return '$mStr Line hooks Upward';
        } else if (condition == 'macdTurningDown') {
          return '$mStr Line hooks Downward';
        } else {
          return '$mStr Zero Cross';
        }
      case AlertIndicatorType.maCross:
        final fastPeriod = params['fastPeriod'] ?? 50;
        final slowPeriod = params['slowPeriod'] ?? 200;
        final maType = params['maType'] ?? 'EMA';
        final fastMaType = params['fastMaType'] ?? maType;
        final slowMaType = params['slowMaType'] ?? maType;
        final source = params['source'] != null && params['source'] != 'Close'
            ? ' (${params['source']})'
            : '';

        String condLabel;
        if (condition == 'goldenCross' || condition == 'fastCrossesAboveSlow') {
          condLabel =
              'Bullish Cross ($fastMaType $fastPeriod > $slowMaType $slowPeriod)';
        } else if (condition == 'deathCross' ||
            condition == 'fastCrossesBelowSlow') {
          condLabel =
              'Bearish Cross ($fastMaType $fastPeriod < $slowMaType $slowPeriod)';
        } else if (condition == 'maCross') {
          condLabel = 'MA Crossover';
        } else if (condition == 'priceCrossesAbove' ||
            condition == 'priceCrossesAboveFast') {
          condLabel = 'Price crosses above $fastMaType $fastPeriod';
        } else if (condition == 'priceCrossesBelow' ||
            condition == 'priceCrossesBelowFast') {
          condLabel = 'Price crosses below $fastMaType $fastPeriod';
        } else if (condition == 'priceCrossesAboveSlow') {
          condLabel = 'Price crosses above $slowMaType $slowPeriod';
        } else if (condition == 'priceCrossesBelowSlow') {
          condLabel = 'Price crosses below $slowMaType $slowPeriod';
        } else if (condition == 'fastAboveSlow') {
          condLabel =
              'State: $fastMaType $fastPeriod > $slowMaType $slowPeriod';
        } else if (condition == 'fastBelowSlow') {
          condLabel =
              'State: $fastMaType $fastPeriod < $slowMaType $slowPeriod';
        } else if (condition == 'priceAboveFast') {
          condLabel = 'State: Price > $fastMaType $fastPeriod';
        } else if (condition == 'priceBelowFast') {
          condLabel = 'State: Price < $fastMaType $fastPeriod';
        } else if (condition == 'priceAboveSlow') {
          condLabel = 'State: Price > $slowMaType $slowPeriod';
        } else if (condition == 'priceBelowSlow') {
          condLabel = 'State: Price < $slowMaType $slowPeriod';
        } else if (condition == 'priceAboveBoth') {
          condLabel = 'State: Price above Both MAs';
        } else if (condition == 'priceBelowBoth') {
          condLabel = 'State: Price below Both MAs';
        } else if (condition == 'priceBetweenMAs') {
          condLabel = 'State: Price between Fast & Slow MAs';
        } else if (condition == 'fastTurningUp') {
          condLabel = 'Momentum: $fastMaType $fastPeriod hooks Upward';
        } else if (condition == 'fastTurningDown') {
          condLabel = 'Momentum: $fastMaType $fastPeriod hooks Downward';
        } else if (condition == 'slowTurningUp') {
          condLabel = 'Momentum: $slowMaType $slowPeriod hooks Upward';
        } else if (condition == 'slowTurningDown') {
          condLabel = 'Momentum: $slowMaType $slowPeriod hooks Downward';
        } else {
          condLabel = condition;
        }
        return 'MA($fastMaType $fastPeriod / $slowMaType $slowPeriod$source) $condLabel';
      case AlertIndicatorType.bollingerBands:
        final period = params['period'] ?? 20;
        final stdDev = params['stdDev'] ?? 2.0;
        final maType = params['maType'] ?? 'SMA';
        final source = params['source'] != null && params['source'] != 'Close'
            ? ' (${params['source']})'
            : '';

        String condLabel;
        if (condition == 'upperBandTouch' ||
            condition == 'priceCrossesAboveUpper') {
          condLabel = 'Price crosses above Upper Band';
        } else if (condition == 'priceCrossesBelowUpper') {
          condLabel = 'Price falls back below Upper Band';
        } else if (condition == 'lowerBandTouch' ||
            condition == 'priceCrossesBelowLower') {
          condLabel = 'Price crosses below Lower Band';
        } else if (condition == 'priceCrossesAboveLower') {
          condLabel = 'Price bounces back above Lower Band';
        } else if (condition == 'middleBandCrossAbove') {
          condLabel = 'Price crosses above Middle Basis';
        } else if (condition == 'middleBandCrossBelow') {
          condLabel = 'Price crosses below Middle Basis';
        } else if (condition == 'middleBandCross') {
          condLabel = 'Middle Basis Cross';
        } else if (condition == 'priceAboveUpper') {
          condLabel = 'State: Price > Upper Band (Overbought)';
        } else if (condition == 'priceBelowLower') {
          condLabel = 'State: Price < Lower Band (Oversold)';
        } else if (condition == 'priceInsideBands') {
          condLabel = 'State: Price inside Bands';
        } else if (condition == 'priceInUpperHalf') {
          condLabel = 'State: Price in Upper Channel (Bullish)';
        } else if (condition == 'priceInLowerHalf') {
          condLabel = 'State: Price in Lower Channel (Bearish)';
        } else if (condition == 'squeeze') {
          final sqz = params['squeezeThreshold'] ?? 0.015;
          condLabel = 'Volatility Squeeze (BW <= $sqz)';
        } else if (condition == 'squeezeBreakout') {
          condLabel = 'Squeeze Breakout / Volatility Expansion';
        } else if (condition == 'bandwidthExpanding') {
          condLabel = 'Bandwidth Expanding';
        } else if (condition == 'bandwidthContracting') {
          condLabel = 'Bandwidth Contracting';
        } else if (condition == 'percentBCrossesAbove80') {
          condLabel = '%B crosses above 0.80';
        } else if (condition == 'percentBCrossesBelow20') {
          condLabel = '%B crosses below 0.20';
        } else if (condition == 'percentBCrossesAboveCenter') {
          condLabel = '%B crosses above 0.50 (Center)';
        } else if (condition == 'percentBCrossesBelowCenter') {
          condLabel = '%B crosses below 0.50 (Center)';
        } else {
          condLabel = condition;
        }
        return 'BB($period, $stdDev, $maType$source) $condLabel';
      case AlertIndicatorType.stochastic:
        final k = params['kPeriod'] ?? 14;
        final kSlowing = params['kSlowing'] ?? 3;
        final d = params['dPeriod'] ?? 3;
        final dMaType = params['dMaType'] ?? 'SMA';
        final osLevel = params['oversoldLevel'] ?? 20;
        final obLevel = params['overboughtLevel'] ?? 80;

        String condLabel;
        if (condition == 'bullishCross' || condition == 'kCrossesAboveD') {
          condLabel = '%K crosses above %D';
        } else if (condition == 'bearishCross' ||
            condition == 'kCrossesBelowD') {
          condLabel = '%K crosses below %D';
        } else if (condition == 'bullishOversoldCross') {
          condLabel = '%K crosses %D in Oversold (<$osLevel)';
        } else if (condition == 'bearishOverboughtCross') {
          condLabel = '%K crosses %D in Overbought (>$obLevel)';
        } else if (condition == 'kCrossesAboveOversold' ||
            condition == 'crossesAbove20') {
          condLabel = '%K crosses above $osLevel (Exit OS)';
        } else if (condition == 'kCrossesBelowOversold') {
          condLabel = '%K crosses below $osLevel (Enter OS)';
        } else if (condition == 'kCrossesAboveOverbought') {
          condLabel = '%K crosses above $obLevel (Enter OB)';
        } else if (condition == 'kCrossesBelowOverbought' ||
            condition == 'crossesBelow80') {
          condLabel = '%K crosses below $obLevel (Exit OB)';
        } else if (condition == 'kCrossesAbove50') {
          condLabel = '%K crosses above 50 (Centerline)';
        } else if (condition == 'kCrossesBelow50') {
          condLabel = '%K crosses below 50 (Centerline)';
        } else if (condition == 'centerlineCross') {
          condLabel = '%K Centerline 50 Cross';
        } else if (condition == 'kAboveD') {
          condLabel = 'State: %K > %D';
        } else if (condition == 'kBelowD') {
          condLabel = 'State: %K < %D';
        } else if (condition == 'inOversold') {
          condLabel = 'State: %K in Oversold (<$osLevel)';
        } else if (condition == 'inOverbought') {
          condLabel = 'State: %K in Overbought (>$obLevel)';
        } else if (condition == 'inNeutralBand') {
          condLabel = 'State: %K in Neutral ($osLevel-$obLevel)';
        } else if (condition == 'kTurningUp') {
          condLabel = 'Momentum: %K hooks Upward';
        } else if (condition == 'kTurningDown') {
          condLabel = 'Momentum: %K hooks Downward';
        } else if (condition == 'dTurningUp') {
          condLabel = 'Momentum: %D line hooks Upward';
        } else if (condition == 'dTurningDown') {
          condLabel = 'Momentum: %D line hooks Downward';
        } else {
          condLabel = condition;
        }
        return 'Stoch($k,$kSlowing,$d $dMaType) $condLabel';
      case AlertIndicatorType.supertrend:
        final period = params['period'] ?? 10;
        final mult = params['multiplier'] ?? 3.0;
        final source = params['source'] != null && params['source'] != 'HL2'
            ? ' [${params['source']}]'
            : '';
        final atrSmooth =
            params['atrSmoothing'] != null && params['atrSmoothing'] != 'RMA'
            ? ' ${params['atrSmoothing']}'
            : '';
        final dist = params['distanceThreshold'] ?? 1.0;

        String condLabel;
        if (condition == 'bullishFlip') {
          condLabel = 'Bullish Trend Flip (Buy Signal)';
        } else if (condition == 'bearishFlip') {
          condLabel = 'Bearish Trend Flip (Sell Signal)';
        } else if (condition == 'trendFlip') {
          condLabel = 'Trend Direction Reversal';
        } else if (condition == 'priceCrossesAboveTrail') {
          condLabel = 'Price crosses above Trailing Stop';
        } else if (condition == 'priceCrossesBelowTrail') {
          condLabel = 'Price crosses below Trailing Stop';
        } else if (condition == 'priceTouchesTrail') {
          condLabel = 'Price tests / touches Trailing Stop';
        } else if (condition == 'priceBouncesOffTrail') {
          condLabel = 'Price tests Trail & Bounces in Trend';
        } else if (condition == 'inBullishTrend') {
          condLabel = 'State: Active Bullish Trend (Green Trail)';
        } else if (condition == 'inBearishTrend') {
          condLabel = 'State: Active Bearish Trend (Red Trail)';
        } else if (condition == 'priceAboveTrail') {
          condLabel = 'State: Price > Trailing Stop';
        } else if (condition == 'priceBelowTrail') {
          condLabel = 'State: Price < Trailing Stop';
        } else if (condition == 'trailRising') {
          condLabel = 'Momentum: Trailing Stop Rising';
        } else if (condition == 'trailFalling') {
          condLabel = 'Momentum: Trailing Stop Falling';
        } else if (condition == 'trailFlat') {
          condLabel = 'State: Trailing Stop Flat';
        } else if (condition == 'priceDistanceGreaterThan') {
          condLabel = 'Overextended (Distance >= $dist%)';
        } else if (condition == 'priceDistanceLessThan') {
          condLabel = 'Near Trail / Low Risk (Distance <= $dist%)';
        } else {
          condLabel = condition;
        }
        return 'Supertrend($period,$mult$source$atrSmooth) $condLabel';
    }
  }
}

enum CandlestickPattern {
  bullishEngulfing('Bullish Engulfing', isBullish: true),
  bearishEngulfing('Bearish Engulfing', isBullish: false),
  hammer('Hammer', isBullish: true),
  hangingMan('Hanging Man', isBullish: false),
  shootingStar('Shooting Star', isBullish: false),
  invertedHammer('Inverted Hammer', isBullish: true),
  morningStar('Morning Star', isBullish: true),
  eveningStar('Evening Star', isBullish: false),
  doji('Standard Doji', isBullish: null),
  dragonflyDoji('Dragonfly Doji', isBullish: true),
  gravestoneDoji('Gravestone Doji', isBullish: false),
  piercingLine('Piercing Line', isBullish: true),
  darkCloudCover('Dark Cloud Cover', isBullish: false),
  threeWhiteSoldiers('Three White Soldiers', isBullish: true),
  threeBlackCrows('Three Black Crows', isBullish: false),
  bullishHarami('Bullish Harami', isBullish: true),
  bearishHarami('Bearish Harami', isBullish: false),
  tweezerBottom('Tweezer Bottom', isBullish: true),
  tweezerTop('Tweezer Top', isBullish: false),
  marubozu('Marubozu Full Body', isBullish: null);

  final String label;
  final bool? isBullish;
  const CandlestickPattern(this.label, {this.isBullish});
}

class ChainNode {
  final String id;
  final AlertType
  nodeType; // priceLevel, candlestickPattern, technicalIndicator
  final double targetPrice;
  final AlertCondition condition;
  final CandlestickPattern? candlestickPattern;
  final IndicatorAlertConfig? indicatorConfig;
  final String timeframe;
  final bool isNegated; // NOT modifier
  String operatorToPrevious; // 'AND' or 'OR' connecting to the previous alarm in the stage
  bool isSatisfied; // 0 or 1
  DateTime? satisfiedAt;
  double? previousPrice;

  ChainNode({
    required this.id,
    required this.nodeType,
    this.targetPrice = 0.0,
    this.condition = AlertCondition.crossesAbove,
    this.candlestickPattern,
    this.indicatorConfig,
    this.timeframe = '15m',
    this.isNegated = false,
    this.operatorToPrevious = 'AND',
    this.isSatisfied = false,
    this.satisfiedAt,
    this.previousPrice,
  });

  String get summary {
    final negPrefix = isNegated ? 'NOT ' : '';
    switch (nodeType) {
      case AlertType.priceLevel:
        return '$negPrefix Price ${condition.label.toLowerCase()} $targetPrice';
      case AlertType.candlestickPattern:
        return '$negPrefix Pattern: ${candlestickPattern?.label ?? "Pattern"} ($timeframe)';
      case AlertType.technicalIndicator:
        return '$negPrefix${indicatorConfig?.summary ?? "Indicator"} ($timeframe)';
      case AlertType.multiStepChain:
        return '$negPrefix Multi-Step';
      case AlertType.timeSchedule:
        return '$negPrefix Scheduled Event';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nodeType': nodeType.name,
    'targetPrice': targetPrice,
    'condition': condition.name,
    'candlestickPattern': candlestickPattern?.name,
    'indicatorConfig': indicatorConfig?.toJson(),
    'timeframe': timeframe,
    'isNegated': isNegated,
    'operatorToPrevious': operatorToPrevious,
    'isSatisfied': isSatisfied,
    'satisfiedAt': satisfiedAt?.toIso8601String(),
    'previousPrice': previousPrice,
  };

  factory ChainNode.fromJson(Map<String, dynamic> json) {
    AlertType type = AlertType.priceLevel;
    for (final t in AlertType.values) {
      if (t.name == json['nodeType']) {
        type = t;
        break;
      }
    }
    AlertCondition cond = AlertCondition.crossesAbove;
    for (final c in AlertCondition.values) {
      if (c.name == json['condition']) {
        cond = c;
        break;
      }
    }
    CandlestickPattern? pattern;
    if (json['candlestickPattern'] != null) {
      for (final p in CandlestickPattern.values) {
        if (p.name == json['candlestickPattern']) {
          pattern = p;
          break;
        }
      }
    }
    IndicatorAlertConfig? indConfig;
    if (json['indicatorConfig'] != null) {
      try {
        indConfig = IndicatorAlertConfig.fromJson(
          json['indicatorConfig'] as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return ChainNode(
      id:
          json['id'] as String? ??
          'node_${DateTime.now().microsecondsSinceEpoch}',
      nodeType: type,
      targetPrice: (json['targetPrice'] as num?)?.toDouble() ?? 0.0,
      condition: cond,
      candlestickPattern: pattern,
      indicatorConfig: indConfig,
      timeframe: json['timeframe'] as String? ?? '15m',
      isNegated: json['isNegated'] as bool? ?? false,
      operatorToPrevious: json['operatorToPrevious'] as String? ?? 'AND',
      isSatisfied: json['isSatisfied'] as bool? ?? false,
      satisfiedAt: json['satisfiedAt'] != null
          ? DateTime.tryParse(json['satisfiedAt'] as String)
          : null,
      previousPrice: (json['previousPrice'] as num?)?.toDouble(),
    );
  }
}

class ChainStage {
  final String id;
  String name;
  String logicOperator; // 'AND' or 'OR'
  final List<ChainNode> nodes;
  bool isCompleted;
  DateTime? completedAt;
  int timeoutMinutes; // 0 = no timeout; > 0 means next stage must complete within this time limit in minutes

  ChainStage({
    required this.id,
    required this.name,
    this.logicOperator = 'AND',
    required this.nodes,
    this.isCompleted = false,
    this.completedAt,
    this.timeoutMinutes = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logicOperator': logicOperator,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
    'timeoutMinutes': timeoutMinutes,
  };

  factory ChainStage.fromJson(Map<String, dynamic> json) {
    final nodesList = <ChainNode>[];
    if (json['nodes'] != null) {
      for (final n in (json['nodes'] as List<dynamic>)) {
        nodesList.add(ChainNode.fromJson(n as Map<String, dynamic>));
      }
    }
    return ChainStage(
      id:
          json['id'] as String? ??
          'stage_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Stage',
      logicOperator: json['logicOperator'] as String? ?? 'AND',
      nodes: nodesList,
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      timeoutMinutes: (json['timeoutMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

class MultiStepConfig {
  final List<ChainStage> stages;
  int currentStageIndex;
  int timeoutMinutes; // Global timeout in minutes after any step completes (0 = disabled)

  MultiStepConfig({
    required this.stages,
    this.currentStageIndex = 0,
    this.timeoutMinutes = 30, // Default 30 min expiration window
  });

  ChainStage? get activeStage =>
      currentStageIndex < stages.length ? stages[currentStageIndex] : null;

  ChainStage? get previousStage =>
      currentStageIndex > 0 && currentStageIndex - 1 < stages.length
      ? stages[currentStageIndex - 1]
      : null;

  bool get isAllCompleted => currentStageIndex >= stages.length;

  /// Returns true if the active stage has timed out since the previous stage completed
  bool isTimedOut(DateTime now) {
    if (currentStageIndex == 0) return false;
    final prev = previousStage;
    if (prev == null || prev.completedAt == null) return false;

    // Use stage-specific timeout if defined (> 0), otherwise fall back to global config timeout
    final limit = prev.timeoutMinutes > 0
        ? prev.timeoutMinutes
        : timeoutMinutes;
    if (limit <= 0) return false;

    final elapsedMinutes = now.difference(prev.completedAt!).inMinutes;
    return elapsedMinutes >= limit;
  }

  /// Calculates remaining time duration before the active stage expires (or null if disabled / stage 0)
  Duration? timeRemaining(DateTime now) {
    if (currentStageIndex == 0) return null;
    final prev = previousStage;
    if (prev == null || prev.completedAt == null) return null;

    final limit = prev.timeoutMinutes > 0
        ? prev.timeoutMinutes
        : timeoutMinutes;
    if (limit <= 0) return null;

    final elapsed = now.difference(prev.completedAt!);
    final totalDuration = Duration(minutes: limit);
    if (elapsed >= totalDuration) return Duration.zero;
    return totalDuration - elapsed;
  }

  void reset() {
    currentStageIndex = 0;
    for (final s in stages) {
      s.isCompleted = false;
      s.completedAt = null;
      for (final n in s.nodes) {
        n.isSatisfied = false;
        n.satisfiedAt = null;
        n.previousPrice = null;
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'stages': stages.map((s) => s.toJson()).toList(),
    'currentStageIndex': currentStageIndex,
    'timeoutMinutes': timeoutMinutes,
  };

  factory MultiStepConfig.fromJson(Map<String, dynamic> json) {
    final stagesList = <ChainStage>[];
    if (json['stages'] != null) {
      for (final s in (json['stages'] as List<dynamic>)) {
        stagesList.add(ChainStage.fromJson(s as Map<String, dynamic>));
      }
    }
    return MultiStepConfig(
      stages: stagesList,
      currentStageIndex: (json['currentStageIndex'] as num?)?.toInt() ?? 0,
      timeoutMinutes: (json['timeoutMinutes'] as num?)?.toInt() ?? 30,
    );
  }
}

class PriceAlert {
  final String id;
  final String symbol;
  final AlertType alertType;
  double targetPrice;
  AlertCondition condition;
  final CandlestickPattern? candlestickPattern;
  final IndicatorAlertConfig? indicatorConfig;
  final MultiStepConfig? multiStepConfig;
  final String timeframe;
  final String note;
  bool isActive;
  final DateTime createdAt;
  DateTime? triggeredAt;
  double initialPrice;
  double? previousPrice;
  final String ringtoneTitle;
  final String? ringtoneUri;
  String? drawingId;
  bool triggerOnCandleClose;
  int cooldownMinutes;
  DateTime? lastTriggeredAt;
  List<String>? targetSymbols;
  DateTime? scheduledTime;
  DateTime? snoozedUntil;
  String? eventId;
  String? eventName;

  PriceAlert({
    required this.id,
    required this.symbol,
    this.alertType = AlertType.priceLevel,
    this.targetPrice = 0.0,
    this.condition = AlertCondition.crossesAbove,
    this.candlestickPattern,
    this.indicatorConfig,
    this.multiStepConfig,
    this.timeframe = '15m',
    this.note = '',
    this.isActive = true,
    required this.createdAt,
    this.triggeredAt,
    required this.initialPrice,
    this.previousPrice,
    this.ringtoneTitle = 'Default Alarm',
    this.ringtoneUri,
    this.drawingId,
    this.triggerOnCandleClose = true,
    this.cooldownMinutes = 0,
    this.lastTriggeredAt,
    this.targetSymbols,
    this.scheduledTime,
    this.snoozedUntil,
    this.eventId,
    this.eventName,
  });

  bool get isPatternAlert => alertType == AlertType.candlestickPattern;
  bool get isIndicatorAlert => alertType == AlertType.technicalIndicator;
  bool get isMultiStepAlert =>
      alertType == AlertType.multiStepChain && multiStepConfig != null;
  bool get isDrawingAlert => drawingId != null && drawingId!.isNotEmpty;
  bool get isTimeScheduleAlert => alertType == AlertType.timeSchedule;
  bool isSnoozedAt(DateTime time) =>
      snoozedUntil != null && time.isBefore(snoozedUntil!);

  bool checkTrigger(double currentPrice, {DateTime? now}) {
    if (!isActive) return false;
    final currentTime = now ?? DateTime.now();
    if (isSnoozedAt(currentTime)) return false;

    if (isTimeScheduleAlert) {
      if (scheduledTime != null) {
        return currentTime.isAfter(scheduledTime!) ||
            currentTime.isAtSameMomentAs(scheduledTime!);
      }
      return false;
    }

    if (isPatternAlert || isIndicatorAlert || isMultiStepAlert) return false;
    final baseline = previousPrice ?? initialPrice;
    previousPrice = currentPrice;

    if (cooldownMinutes > 0 && lastTriggeredAt != null) {
      if (currentTime.difference(lastTriggeredAt!).inMinutes <
          cooldownMinutes) {
        return false; // Still in cooldown deadband
      }
    }
    bool isTriggered = false;
    switch (condition) {
      case AlertCondition.crossesAbove:
        isTriggered = baseline < targetPrice && currentPrice >= targetPrice;
        break;
      case AlertCondition.crossesBelow:
        isTriggered = baseline > targetPrice && currentPrice <= targetPrice;
        break;
      case AlertCondition.hits:
        isTriggered =
            (currentPrice - targetPrice).abs() <= (targetPrice * 0.0002);
        break;
    }
    return isTriggered;
  }

  double pipDistance(double currentPrice) {
    if (isPatternAlert ||
        isIndicatorAlert ||
        isMultiStepAlert ||
        isTimeScheduleAlert) {
      return 0.0;
    }
    final diff = targetPrice - currentPrice;
    final double multiplier;
    if (symbol.contains('JPY')) {
      multiplier = 100.0;
    } else if (symbol.contains('XAU')) {
      multiplier = 10.0;
    } else if (symbol.contains('BTC') || symbol.contains('ETH')) {
      multiplier = 1.0;
    } else {
      multiplier = 10000.0;
    }
    return diff * multiplier;
  }

  String formattedTarget() {
    if (isTimeScheduleAlert) {
      final name = eventName ?? 'Calendar Event';
      if (scheduledTime != null) {
        final fmt = DateFormat('MMM d, HH:mm');
        return '$name @ ${fmt.format(scheduledTime!.toLocal())}';
      }
      return name;
    }
    if (isMultiStepAlert) {
      final cfg = multiStepConfig!;
      final active = cfg.activeStage;
      final cur = cfg.currentStageIndex + 1;
      final total = cfg.stages.length;
      final limit = active?.timeoutMinutes ?? cfg.timeoutMinutes;
      final timeoutSuffix = limit > 0 ? ' (${limit}m timeout)' : '';
      return 'Stage $cur/$total: ${active?.name ?? "Complete"}$timeoutSuffix';
    }
    if (isPatternAlert) {
      return candlestickPattern?.label ?? 'Pattern';
    }
    if (isIndicatorAlert) {
      return indicatorConfig?.summary ?? 'Indicator Alert';
    }
    final format = symbol.contains('JPY')
        ? NumberFormat('#,##0.000')
        : symbol.contains('BTC') || symbol.contains('XAU')
        ? NumberFormat('#,##0.00')
        : NumberFormat('0.00000');
    return format.format(targetPrice);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'alertType': alertType.name,
      'targetPrice': targetPrice,
      'condition': condition.name,
      'candlestickPattern': candlestickPattern?.name,
      'indicatorConfig': indicatorConfig?.toJson(),
      'multiStepConfig': multiStepConfig?.toJson(),
      'timeframe': timeframe,
      'note': note,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'triggeredAt': triggeredAt?.toIso8601String(),
      'initialPrice': initialPrice,
      'previousPrice': previousPrice,
      'ringtoneTitle': ringtoneTitle,
      'ringtoneUri': ringtoneUri,
      'drawingId': drawingId,
      'triggerOnCandleClose': triggerOnCandleClose,
      'cooldownMinutes': cooldownMinutes,
      'lastTriggeredAt': lastTriggeredAt?.toIso8601String(),
      'targetSymbols': targetSymbols,
      'scheduledTime': scheduledTime?.toIso8601String(),
      'snoozedUntil': snoozedUntil?.toIso8601String(),
      'eventId': eventId,
      'eventName': eventName,
    };
  }

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    AlertType type = AlertType.priceLevel;
    if (json['alertType'] == 'candlestickPattern') {
      type = AlertType.candlestickPattern;
    } else if (json['alertType'] == 'technicalIndicator') {
      type = AlertType.technicalIndicator;
    } else if (json['alertType'] == 'multiStepChain') {
      type = AlertType.multiStepChain;
    } else if (json['alertType'] == 'timeSchedule') {
      type = AlertType.timeSchedule;
    }

    AlertCondition cond = AlertCondition.crossesAbove;
    for (final c in AlertCondition.values) {
      if (c.name == json['condition']) {
        cond = c;
        break;
      }
    }

    CandlestickPattern? pattern;
    if (json['candlestickPattern'] != null) {
      for (final p in CandlestickPattern.values) {
        if (p.name == json['candlestickPattern']) {
          pattern = p;
          break;
        }
      }
    }

    IndicatorAlertConfig? indicatorConfig;
    if (json['indicatorConfig'] != null) {
      try {
        indicatorConfig = IndicatorAlertConfig.fromJson(
          json['indicatorConfig'] as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    MultiStepConfig? multiStepConfig;
    if (json['multiStepConfig'] != null) {
      try {
        multiStepConfig = MultiStepConfig.fromJson(
          json['multiStepConfig'] as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    List<String>? targetSymbols;
    if (json['targetSymbols'] != null) {
      try {
        targetSymbols = (json['targetSymbols'] as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    return PriceAlert(
      id:
          json['id'] as String? ??
          'alert_${DateTime.now().millisecondsSinceEpoch}',
      symbol: json['symbol'] as String? ?? 'EURUSD',
      alertType: type,
      targetPrice: (json['targetPrice'] as num?)?.toDouble() ?? 0.0,
      condition: cond,
      candlestickPattern: pattern,
      indicatorConfig: indicatorConfig,
      multiStepConfig: multiStepConfig,
      timeframe: json['timeframe'] as String? ?? '15m',
      note: json['note'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.tryParse(json['triggeredAt'] as String)
          : null,
      initialPrice: (json['initialPrice'] as num?)?.toDouble() ?? 0.0,
      previousPrice: (json['previousPrice'] as num?)?.toDouble(),
      ringtoneTitle: json['ringtoneTitle'] as String? ?? 'Default Alarm',
      ringtoneUri: json['ringtoneUri'] as String?,
      drawingId: json['drawingId'] as String?,
      triggerOnCandleClose: json['triggerOnCandleClose'] as bool? ?? true,
      cooldownMinutes: (json['cooldownMinutes'] as num?)?.toInt() ?? 0,
      lastTriggeredAt: json['lastTriggeredAt'] != null
          ? DateTime.tryParse(json['lastTriggeredAt'] as String)
          : null,
      targetSymbols: targetSymbols,
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.tryParse(json['scheduledTime'] as String)
          : null,
      snoozedUntil: json['snoozedUntil'] != null
          ? DateTime.tryParse(json['snoozedUntil'] as String)
          : null,
      eventId: json['eventId'] as String?,
      eventName: json['eventName'] as String?,
    );
  }
}
