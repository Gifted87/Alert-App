import 'dart:math';

import '../models/market_models.dart';

class IndicatorCalculator {
  /// Evaluates whether the given indicator alert condition is triggered on the latest candle.
  /// [candles] must be provided in chronological order (oldest to newest).
  static bool checkTrigger(PriceAlert alert, List<BiquoteCandle> candles) {
    final config = alert.indicatorConfig;
    if (config == null || candles.length < 5) return false;

    switch (config.indicatorType) {
      case AlertIndicatorType.rsi:
        return _checkRsi(config, candles);
      case AlertIndicatorType.macd:
        return _checkMacd(config, candles);
      case AlertIndicatorType.maCross:
        return _checkMaCross(config, candles);
      case AlertIndicatorType.bollingerBands:
        return _checkBollinger(config, candles);
      case AlertIndicatorType.stochastic:
        return _checkStochastic(config, candles);
      case AlertIndicatorType.supertrend:
        return _checkSupertrend(config, candles);
    }
  }

  // ==========================================
  // Helper: Price Source Extractor
  // ==========================================
  static List<double> _extractPrices(
    List<BiquoteCandle> candles,
    String source,
  ) {
    switch (source.toLowerCase()) {
      case 'open':
        return candles.map((c) => c.open).toList();
      case 'high':
        return candles.map((c) => c.high).toList();
      case 'low':
        return candles.map((c) => c.low).toList();
      case 'hl2':
        return candles.map((c) => (c.high + c.low) / 2.0).toList();
      case 'hlc3':
        return candles.map((c) => (c.high + c.low + c.close) / 3.0).toList();
      case 'ohlc4':
        return candles
            .map((c) => (c.open + c.high + c.low + c.close) / 4.0)
            .toList();
      case 'close':
      default:
        return candles.map((c) => c.close).toList();
    }
  }

  // ==========================================
  // 1. RSI (Relative Strength Index) + Signal MA of RSI
  // ==========================================
  static bool _checkRsi(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final period = (config.params['period'] as num?)?.toInt() ?? 14;
    final level = (config.params['level'] as num?)?.toDouble() ?? 30.0;
    final source = (config.params['source'] as String?) ?? 'Close';
    final smoothingType = (config.params['smoothingType'] as String?) ?? 'RMA';
    final obLevel = (config.params['overbought'] as num?)?.toDouble() ?? 70.0;
    final osLevel = (config.params['oversold'] as num?)?.toDouble() ?? 30.0;

    if (candles.length <= period + 2) return false;

    final prices = _extractPrices(candles, source);
    final rsiSeries = calculateRsiSeriesFromPrices(
      prices,
      period,
      smoothingType: smoothingType,
    );
    if (rsiSeries.length < 2) return false;

    final curr = rsiSeries[rsiSeries.length - 1];
    final prev = rsiSeries[rsiSeries.length - 2];

    // Indicator on Indicator: RSI crossing its own Signal Moving Average (MA of RSI)
    if (config.condition == 'crossesAboveSignalMa' ||
        config.condition == 'crossesBelowSignalMa') {
      final signalMaPeriod =
          (config.params['signalMaPeriod'] as num?)?.toInt() ?? 9;
      final signalMaType = (config.params['signalMaType'] as String?) ?? 'EMA';
      if (rsiSeries.length < signalMaPeriod + 2) return false;

      final maSeries = _calculateMaSeries(
        rsiSeries,
        signalMaPeriod,
        signalMaType,
      );

      if (maSeries.length < 2) return false;

      final currMa = maSeries.last;
      final prevMa = maSeries[maSeries.length - 2];
      final currRsi = rsiSeries.last;
      final prevRsi = rsiSeries[rsiSeries.length - 2];

      if (config.condition == 'crossesAboveSignalMa') {
        return prevRsi <= prevMa && currRsi > currMa;
      } else {
        return prevRsi >= prevMa && currRsi < currMa;
      }
    }

    switch (config.condition) {
      case 'crossesAbove':
      case 'crossesAboveLevel':
        return prev < level && curr >= level;
      case 'crossesBelow':
      case 'crossesBelowLevel':
        return prev > level && curr <= level;
      case 'crossesBelowOversold':
        return prev >= osLevel && curr < osLevel;
      case 'crossesAboveOversold': // exit oversold / recovery
        return prev <= osLevel && curr > osLevel;
      case 'crossesAboveOverbought':
        return prev <= obLevel && curr > obLevel;
      case 'crossesBelowOverbought': // exit overbought / pullback
        return prev >= obLevel && curr < obLevel;
      case 'overboughtEnter':
        return prev <= obLevel && curr > obLevel;
      case 'oversoldEnter':
        return prev >= osLevel && curr < osLevel;
      case 'crossesAboveCenterline':
        return prev <= 50.0 && curr > 50.0;
      case 'crossesBelowCenterline':
        return prev >= 50.0 && curr < 50.0;
      case 'centerlineCross':
        return (prev < 50.0 && curr >= 50.0) || (prev > 50.0 && curr <= 50.0);
      case 'inOversold':
        return curr < osLevel;
      case 'inOverbought':
        return curr > obLevel;
      case 'inBandRange':
        return curr >= osLevel && curr <= obLevel;
      case 'outsideBandRange':
        return curr < osLevel || curr > obLevel;
      case 'rsiTurningUp':
        if (rsiSeries.length < 3) return false;
        final pprev = rsiSeries[rsiSeries.length - 3];
        return prev <= pprev && curr > prev;
      case 'rsiTurningDown':
        if (rsiSeries.length < 3) return false;
        final pprev = rsiSeries[rsiSeries.length - 3];
        return prev >= pprev && curr < prev;
      default:
        return false;
    }
  }

  static List<double> calculateRsiSeries(
    List<BiquoteCandle> candles,
    int period, {
    String smoothingType = 'RMA',
  }) {
    final closes = candles.map((c) => c.close).toList();
    return calculateRsiSeriesFromPrices(
      closes,
      period,
      smoothingType: smoothingType,
    );
  }

  static List<double> calculateRsiSeriesFromPrices(
    List<double> prices,
    int period, {
    String smoothingType = 'RMA',
  }) {
    if (prices.length <= period) return [];
    final rsi = <double>[];

    double gainSum = 0.0;
    double lossSum = 0.0;

    for (int i = 1; i <= period; i++) {
      final change = prices[i] - prices[i - 1];
      if (change > 0) gainSum += change;
      if (change < 0) lossSum += change.abs();
    }

    double avgGain = gainSum / period;
    double avgLoss = lossSum / period;

    double rs = avgLoss == 0 ? 100 : avgGain / avgLoss;
    rsi.add(100 - (100 / (1 + rs)));

    final k = 2.0 / (period + 1);

    for (int i = period + 1; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      final gain = change > 0 ? change : 0.0;
      final loss = change < 0 ? change.abs() : 0.0;

      if (smoothingType == 'EMA') {
        avgGain = (gain * k) + (avgGain * (1.0 - k));
        avgLoss = (loss * k) + (avgLoss * (1.0 - k));
      } else if (smoothingType == 'SMA') {
        // Rolling sum over past period
        double gSum = 0.0;
        double lSum = 0.0;
        for (int j = i - period + 1; j <= i; j++) {
          final ch = prices[j] - prices[j - 1];
          if (ch > 0) gSum += ch;
          if (ch < 0) lSum += ch.abs();
        }
        avgGain = gSum / period;
        avgLoss = lSum / period;
      } else if (smoothingType == 'WMA') {
        // Linear weighted moving average over past period
        double gSum = 0.0;
        double lSum = 0.0;
        final denom = (period * (period + 1)) / 2.0;
        for (int j = 0; j < period; j++) {
          final idx = i - period + 1 + j;
          final ch = prices[idx] - prices[idx - 1];
          final weight = j + 1;
          if (ch > 0) gSum += ch * weight;
          if (ch < 0) lSum += ch.abs() * weight;
        }
        avgGain = gSum / denom;
        avgLoss = lSum / denom;
      } else {
        // Standard Wilder RMA
        avgGain = (avgGain * (period - 1) + gain) / period;
        avgLoss = (avgLoss * (period - 1) + loss) / period;
      }

      rs = avgLoss == 0 ? 100 : avgGain / avgLoss;
      rsi.add(100 - (100 / (1 + rs)));
    }

    return rsi;
  }

  // ==========================================
  // 2. MACD (Moving Average Convergence Divergence)
  // ==========================================
  static bool _checkMacd(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final fast = (config.params['fast'] as num?)?.toInt() ?? 12;
    final slow = (config.params['slow'] as num?)?.toInt() ?? 26;
    final signal = (config.params['signal'] as num?)?.toInt() ?? 9;
    final source = (config.params['source'] as String?) ?? 'Close';
    final fastMaType = (config.params['fastMaType'] as String?) ?? 'EMA';
    final slowMaType = (config.params['slowMaType'] as String?) ?? 'EMA';
    final signalMaType = (config.params['signalMaType'] as String?) ?? 'EMA';

    if (candles.length < slow + signal + 2) return false;

    final macdData = calculateMacd(
      candles,
      fast,
      slow,
      signal,
      source: source,
      fastMaType: fastMaType,
      slowMaType: slowMaType,
      signalMaType: signalMaType,
    );
    final macdLine = macdData['macd']!;
    final signalLine = macdData['signal']!;
    final hist = macdData['histogram']!;

    if (macdLine.length < 2 || signalLine.length < 2) return false;

    final currM = macdLine[macdLine.length - 1];
    final prevM = macdLine[macdLine.length - 2];
    final currS = signalLine[signalLine.length - 1];
    final prevS = signalLine[signalLine.length - 2];
    final currH = hist.isNotEmpty ? hist[hist.length - 1] : 0.0;
    final prevH = hist.length >= 2 ? hist[hist.length - 2] : 0.0;

    switch (config.condition) {
      case 'bullishSignalCross':
        return prevM <= prevS && currM > currS;
      case 'bearishSignalCross':
        return prevM >= prevS && currM < currS;
      case 'zeroLineCrossAbove':
      case 'zeroCrossAbove':
        return prevM <= 0 && currM > 0;
      case 'zeroLineCrossBelow':
      case 'zeroCrossBelow':
        return prevM >= 0 && currM < 0;
      case 'zeroLineCross':
        return (prevM <= 0 && currM > 0) || (prevM >= 0 && currM < 0);
      case 'signalZeroCrossAbove':
        return prevS <= 0 && currS > 0;
      case 'signalZeroCrossBelow':
        return prevS >= 0 && currS < 0;
      case 'histogramFlipPositive':
        return prevH <= 0 && currH > 0;
      case 'histogramFlipNegative':
        return prevH >= 0 && currH < 0;
      case 'macdAboveSignal':
        return currM > currS;
      case 'macdBelowSignal':
        return currM < currS;
      case 'macdAboveZero':
        return currM > 0;
      case 'macdBelowZero':
        return currM < 0;
      case 'histogramPositive':
        return currH > 0;
      case 'histogramNegative':
        return currH < 0;
      case 'histogramTurningUp':
        if (hist.length < 3) return false;
        final pprevH = hist[hist.length - 3];
        return prevH <= pprevH && currH > prevH;
      case 'histogramTurningDown':
        if (hist.length < 3) return false;
        final pprevH = hist[hist.length - 3];
        return prevH >= pprevH && currH < prevH;
      case 'macdTurningUp':
        if (macdLine.length < 3) return false;
        final pprevM = macdLine[macdLine.length - 3];
        return prevM <= pprevM && currM > prevM;
      case 'macdTurningDown':
        if (macdLine.length < 3) return false;
        final pprevM = macdLine[macdLine.length - 3];
        return prevM >= pprevM && currM < prevM;
      default:
        return false;
    }
  }

  static Map<String, List<double>> calculateMacd(
    List<BiquoteCandle> candles,
    int fastPeriod,
    int slowPeriod,
    int signalPeriod, {
    String source = 'Close',
    String fastMaType = 'EMA',
    String slowMaType = 'EMA',
    String signalMaType = 'EMA',
  }) {
    final prices = _extractPrices(candles, source);
    final fastMa = _calculateMaSeries(prices, fastPeriod, fastMaType);
    final slowMa = _calculateMaSeries(prices, slowPeriod, slowMaType);

    if (fastMa.isEmpty || slowMa.isEmpty) {
      return {'macd': [], 'signal': [], 'histogram': []};
    }

    final offset = fastMa.length - slowMa.length;
    if (offset < 0) return {'macd': [], 'signal': [], 'histogram': []};

    final macdLine = <double>[];
    for (int i = 0; i < slowMa.length; i++) {
      macdLine.add(fastMa[i + offset] - slowMa[i]);
    }

    final signalLine = _calculateMaSeries(macdLine, signalPeriod, signalMaType);
    final sigOffset = macdLine.length - signalLine.length;
    if (sigOffset < 0) return {'macd': [], 'signal': [], 'histogram': []};

    final trimmedMacd = macdLine.sublist(sigOffset);

    final histogram = <double>[];
    for (int i = 0; i < signalLine.length; i++) {
      histogram.add(trimmedMacd[i] - signalLine[i]);
    }

    return {'macd': trimmedMacd, 'signal': signalLine, 'histogram': histogram};
  }

  // ==========================================
  // 3. Moving Average Crossover (EMA / SMA)
  // ==========================================
  static bool _checkMaCross(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final fastPeriod = (config.params['fastPeriod'] as num?)?.toInt() ?? 50;
    final slowPeriod = (config.params['slowPeriod'] as num?)?.toInt() ?? 200;
    final maType = (config.params['maType'] as String?) ?? 'EMA';
    final fastMaType = (config.params['fastMaType'] as String?) ?? maType;
    final slowMaType = (config.params['slowMaType'] as String?) ?? maType;
    final source = (config.params['source'] as String?) ?? 'Close';

    final maxPeriod = max(fastPeriod, slowPeriod);
    if (candles.length < maxPeriod + 3) return false;
    final prices = _extractPrices(candles, source);

    final fastMa = _calculateMaSeries(prices, fastPeriod, fastMaType);
    final slowMa = _calculateMaSeries(prices, slowPeriod, slowMaType);

    if (fastMa.length < 2 || slowMa.length < 2) return false;

    final currFast = fastMa.last;
    final prevFast = fastMa[fastMa.length - 2];
    final currSlow = slowMa.last;
    final prevSlow = slowMa[slowMa.length - 2];

    final currPrice = prices.last;
    final prevPrice = prices[prices.length - 2];

    switch (config.condition) {
      // 1. Crosses: Fast vs Slow
      case 'goldenCross':
      case 'fastCrossesAboveSlow':
        return prevFast <= prevSlow && currFast > currSlow;
      case 'deathCross':
      case 'fastCrossesBelowSlow':
        return prevFast >= prevSlow && currFast < currSlow;
      case 'maCross':
        return (prevFast <= prevSlow && currFast > currSlow) ||
            (prevFast >= prevSlow && currFast < currSlow);

      // 2. Crosses: Price vs Fast MA
      case 'priceCrossesAbove':
      case 'priceCrossesAboveFast':
        return prevPrice <= prevFast && currPrice > currFast;
      case 'priceCrossesBelow':
      case 'priceCrossesBelowFast':
        return prevPrice >= prevFast && currPrice < currFast;

      // 3. Crosses: Price vs Slow MA
      case 'priceCrossesAboveSlow':
        return prevPrice <= prevSlow && currPrice > currSlow;
      case 'priceCrossesBelowSlow':
        return prevPrice >= prevSlow && currPrice < currSlow;

      // 4. Continuous States: Alignment & Regime
      case 'fastAboveSlow':
        return currFast > currSlow;
      case 'fastBelowSlow':
        return currFast < currSlow;
      case 'priceAboveFast':
        return currPrice > currFast;
      case 'priceBelowFast':
        return currPrice < currFast;
      case 'priceAboveSlow':
        return currPrice > currSlow;
      case 'priceBelowSlow':
        return currPrice < currSlow;
      case 'priceAboveBoth':
        return currPrice > currFast && currPrice > currSlow;
      case 'priceBelowBoth':
        return currPrice < currFast && currPrice < currSlow;
      case 'priceBetweenMAs':
        return (currPrice > min(currFast, currSlow)) &&
            (currPrice < max(currFast, currSlow));

      // 5. Slope / Directional Turning Points
      case 'fastTurningUp':
        if (fastMa.length < 3) return false;
        final pprevFast = fastMa[fastMa.length - 3];
        return prevFast <= pprevFast && currFast > prevFast;
      case 'fastTurningDown':
        if (fastMa.length < 3) return false;
        final pprevFast = fastMa[fastMa.length - 3];
        return prevFast >= pprevFast && currFast < prevFast;
      case 'slowTurningUp':
        if (slowMa.length < 3) return false;
        final pprevSlow = slowMa[slowMa.length - 3];
        return prevSlow <= pprevSlow && currSlow > prevSlow;
      case 'slowTurningDown':
        if (slowMa.length < 3) return false;
        final pprevSlow = slowMa[slowMa.length - 3];
        return prevSlow >= pprevSlow && currSlow < prevSlow;

      default:
        return false;
    }
  }

  static List<double> calculateMovingAverageSeries(
    List<BiquoteCandle> candles,
    int period, {
    String maType = 'EMA',
    String source = 'Close',
  }) {
    final prices = _extractPrices(candles, source);
    return _calculateMaSeries(prices, period, maType);
  }

  // ==========================================
  // 4. Bollinger Bands
  // ==========================================
  static bool _checkBollinger(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final period = (config.params['period'] as num?)?.toInt() ?? 20;
    final stdDevMult = (config.params['stdDev'] as num?)?.toDouble() ?? 2.0;
    final source = (config.params['source'] as String?) ?? 'Close';
    final maType = (config.params['maType'] as String?) ?? 'SMA';
    final squeezeThresh =
        (config.params['squeezeThreshold'] as num?)?.toDouble() ?? 0.015;

    if (candles.length < period + 3) return false;

    final bb = calculateBollingerBands(
      candles,
      period,
      stdDevMult,
      source: source,
      maType: maType,
    );
    final upper = bb['upper']!;
    final middle = bb['middle']!;
    final lower = bb['lower']!;
    final bandwidth = bb['bandwidth']!;
    final percentB = bb['percentB']!;

    if (upper.length < 2) return false;

    final prices = _extractPrices(candles, source);
    final currPrice = prices.last;
    final prevPrice = prices[prices.length - 2];

    final currUpper = upper.last;
    final prevUpper = upper[upper.length - 2];
    final currLower = lower.last;
    final prevLower = lower[lower.length - 2];
    final currMid = middle.last;
    final prevMid = middle[middle.length - 2];

    final currBw = bandwidth.last;
    final prevBw = bandwidth[bandwidth.length - 2];

    final currPb = percentB.last;
    final prevPb = percentB[percentB.length - 2];

    switch (config.condition) {
      // 1. Band Touches / Crosses
      case 'upperBandTouch':
      case 'priceCrossesAboveUpper':
        return prevPrice <= prevUpper && currPrice > currUpper;
      case 'priceCrossesBelowUpper':
        return prevPrice >= prevUpper && currPrice < currUpper;
      case 'lowerBandTouch':
      case 'priceCrossesBelowLower':
        return prevPrice >= prevLower && currPrice < currLower;
      case 'priceCrossesAboveLower':
        return prevPrice <= prevLower && currPrice > currLower;
      case 'middleBandCrossAbove':
        return prevPrice <= prevMid && currPrice > currMid;
      case 'middleBandCrossBelow':
        return prevPrice >= prevMid && currPrice < currMid;
      case 'middleBandCross':
        return (prevPrice <= prevMid && currPrice > currMid) ||
            (prevPrice >= prevMid && currPrice < currMid);

      // 2. Continuous States / Regimes
      case 'priceAboveUpper':
        return currPrice > currUpper;
      case 'priceBelowLower':
        return currPrice < currLower;
      case 'priceInsideBands':
        return currPrice >= currLower && currPrice <= currUpper;
      case 'priceInUpperHalf':
        return currPrice > currMid && currPrice <= currUpper;
      case 'priceInLowerHalf':
        return currPrice < currMid && currPrice >= currLower;

      // 3. Volatility Squeeze & Expansion
      case 'squeeze':
        return currBw <= squeezeThresh;
      case 'squeezeBreakout':
        return prevBw <= squeezeThresh && currBw > squeezeThresh;
      case 'bandwidthExpanding':
        return currBw > prevBw;
      case 'bandwidthContracting':
        return currBw < prevBw;

      // 4. %B Conditions
      case 'percentBCrossesAbove80':
        return prevPb <= 0.8 && currPb > 0.8;
      case 'percentBCrossesBelow20':
        return prevPb >= 0.2 && currPb < 0.2;
      case 'percentBCrossesAboveCenter':
        return prevPb <= 0.5 && currPb > 0.5;
      case 'percentBCrossesBelowCenter':
        return prevPb >= 0.5 && currPb < 0.5;

      default:
        return false;
    }
  }

  static Map<String, List<double>> calculateBollingerBands(
    List<BiquoteCandle> candles,
    int period,
    double stdDevMultiplier, {
    String source = 'Close',
    String maType = 'SMA',
  }) {
    final prices = _extractPrices(candles, source);
    if (prices.length < period) {
      return {
        'upper': [],
        'middle': [],
        'lower': [],
        'bandwidth': [],
        'percentB': [],
      };
    }

    final middleMa = _calculateMaSeries(prices, period, maType);
    final upper = <double>[];
    final middle = <double>[];
    final lower = <double>[];
    final bandwidth = <double>[];
    final percentB = <double>[];

    final offset = prices.length - middleMa.length;

    for (int i = 0; i < middleMa.length; i++) {
      final priceIdx = i + offset;
      final slice = prices.sublist(priceIdx - period + 1, priceIdx + 1);
      final mean = middleMa[i];

      double varianceSum = 0.0;
      for (final p in slice) {
        varianceSum += pow(p - mean, 2);
      }
      final stdDev = sqrt(varianceSum / period);

      final up = mean + (stdDev * stdDevMultiplier);
      final low = mean - (stdDev * stdDevMultiplier);
      final bw = mean != 0 ? (up - low) / mean : 0.0;
      final bandWidthDiff = up - low;
      final pb = bandWidthDiff != 0
          ? (prices[priceIdx] - low) / bandWidthDiff
          : 0.5;

      upper.add(up);
      middle.add(mean);
      lower.add(low);
      bandwidth.add(bw);
      percentB.add(pb);
    }

    return {
      'upper': upper,
      'middle': middle,
      'lower': lower,
      'bandwidth': bandwidth,
      'percentB': percentB,
    };
  }

  // ==========================================
  // 5. Stochastic Oscillator
  // ==========================================
  static bool _checkStochastic(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final kPeriod = (config.params['kPeriod'] as num?)?.toInt() ?? 14;
    final kSlowing = (config.params['kSlowing'] as num?)?.toInt() ?? 3;
    final dPeriod = (config.params['dPeriod'] as num?)?.toInt() ?? 3;
    final dMaType = (config.params['dMaType'] as String?) ?? 'SMA';

    if (candles.length < kPeriod + kSlowing + dPeriod + 2) return false;

    final stoch = calculateStochastic(
      candles,
      kPeriod,
      dPeriod,
      kSlowing: kSlowing,
      dMaType: dMaType,
    );
    final kSeries = stoch['k']!;
    final dSeries = stoch['d']!;

    if (kSeries.length < 2 || dSeries.length < 2) return false;

    final currK = kSeries.last;
    final prevK = kSeries[kSeries.length - 2];
    final currD = dSeries.last;
    final prevD = dSeries[dSeries.length - 2];

    final osLevel =
        (config.params['oversoldLevel'] as num?)?.toDouble() ?? 20.0;
    final obLevel =
        (config.params['overboughtLevel'] as num?)?.toDouble() ?? 80.0;

    switch (config.condition) {
      // 1. %K / %D Crossovers
      case 'bullishCross':
      case 'kCrossesAboveD':
        return prevK <= prevD && currK > currD;
      case 'bearishCross':
      case 'kCrossesBelowD':
        return prevK >= prevD && currK < currD;
      case 'bullishOversoldCross':
        return prevK <= prevD && currK > currD && currK <= osLevel;
      case 'bearishOverboughtCross':
        return prevK >= prevD && currK < currD && currK >= obLevel;

      // 2. Threshold / Level Crossings
      case 'kCrossesAboveOversold':
      case 'crossesAbove20':
        return prevK <= osLevel && currK > osLevel;
      case 'kCrossesBelowOversold':
        return prevK >= osLevel && currK < osLevel;
      case 'kCrossesAboveOverbought':
        return prevK <= obLevel && currK > obLevel;
      case 'kCrossesBelowOverbought':
      case 'crossesBelow80':
        return prevK >= obLevel && currK < obLevel;
      case 'kCrossesAbove50':
        return prevK <= 50.0 && currK > 50.0;
      case 'kCrossesBelow50':
        return prevK >= 50.0 && currK < 50.0;
      case 'centerlineCross':
        return (prevK <= 50.0 && currK > 50.0) ||
            (prevK >= 50.0 && currK < 50.0);

      // 3. Continuous States
      case 'kAboveD':
        return currK > currD;
      case 'kBelowD':
        return currK < currD;
      case 'inOversold':
        return currK < osLevel;
      case 'inOverbought':
        return currK > obLevel;
      case 'inNeutralBand':
        return currK >= osLevel && currK <= obLevel;

      // 4. Slope / Turning Points
      case 'kTurningUp':
        if (kSeries.length < 3) return false;
        final pprevK = kSeries[kSeries.length - 3];
        return prevK <= pprevK && currK > prevK;
      case 'kTurningDown':
        if (kSeries.length < 3) return false;
        final pprevK = kSeries[kSeries.length - 3];
        return prevK >= pprevK && currK < prevK;
      case 'dTurningUp':
        if (dSeries.length < 3) return false;
        final pprevD = dSeries[dSeries.length - 3];
        return prevD <= pprevD && currD > prevD;
      case 'dTurningDown':
        if (dSeries.length < 3) return false;
        final pprevD = dSeries[dSeries.length - 3];
        return prevD >= pprevD && currD < prevD;

      default:
        return false;
    }
  }

  static Map<String, List<double>> calculateStochastic(
    List<BiquoteCandle> candles,
    int kPeriod,
    int dPeriod, {
    int kSlowing = 3,
    String dMaType = 'SMA',
  }) {
    if (candles.length < kPeriod) {
      return {'k': [], 'd': []};
    }
    final rawK = <double>[];

    for (int i = kPeriod - 1; i < candles.length; i++) {
      final slice = candles.sublist(i - kPeriod + 1, i + 1);
      final highest = slice.map((c) => c.high).reduce(max);
      final lowest = slice.map((c) => c.low).reduce(min);
      final currentClose = candles[i].close;

      final range = highest - lowest;
      final k = range == 0 ? 50.0 : ((currentClose - lowest) / range) * 100.0;
      rawK.add(k);
    }

    final smoothedK = kSlowing > 1
        ? _calculateMaSeries(rawK, kSlowing, 'SMA')
        : rawK;
    if (smoothedK.isEmpty) return {'k': [], 'd': []};

    final dSeries = _calculateMaSeries(smoothedK, dPeriod, dMaType);
    final offset = smoothedK.length - dSeries.length;
    if (offset < 0) return {'k': [], 'd': []};

    final trimmedK = smoothedK.sublist(offset);

    return {'k': trimmedK, 'd': dSeries};
  }

  // ==========================================
  // 6. Supertrend
  // ==========================================
  static bool _checkSupertrend(
    IndicatorAlertConfig config,
    List<BiquoteCandle> candles,
  ) {
    final period = (config.params['period'] as num?)?.toInt() ?? 10;
    final multiplier = (config.params['multiplier'] as num?)?.toDouble() ?? 3.0;
    final source = (config.params['source'] as String?) ?? 'HL2';
    final atrSmoothing = (config.params['atrSmoothing'] as String?) ?? 'RMA';
    final distThreshold =
        ((config.params['distanceThreshold'] as num?)?.toDouble() ?? 1.0) /
        100.0;

    if (candles.length < period + 5) return false;

    final result = calculateSupertrend(
      candles,
      period,
      multiplier,
      source: source,
      atrSmoothing: atrSmoothing,
    );
    final trends = (result['trend'] as List<int>?) ?? [];
    final trails = (result['supertrend'] as List<double>?) ?? [];
    if (trends.length < 2 || trails.length < 2) return false;

    final currTrend = trends.last; // 1 = Bullish, -1 = Bearish
    final prevTrend = trends[trends.length - 2];
    final currTrail = trails.last;
    final prevTrail = trails[trails.length - 2];

    final currCandle = candles.last;
    final prevCandle = candles[candles.length - 2];

    final currClose = currCandle.close;
    final prevClose = prevCandle.close;

    final currDistanceRatio =
        (currClose - currTrail).abs() / (currClose == 0 ? 1.0 : currClose);

    switch (config.condition) {
      // 1. Trend Reversals / Flips
      case 'bullishFlip':
        return prevTrend == -1 && currTrend == 1;
      case 'bearishFlip':
        return prevTrend == 1 && currTrend == -1;
      case 'trendFlip':
        return prevTrend != currTrend;

      // 2. Trailing Stop Crosses
      case 'priceCrossesAboveTrail':
        return (prevClose <= prevTrail && currClose > currTrail) ||
            (prevTrend == -1 && currTrend == 1);
      case 'priceCrossesBelowTrail':
        return (prevClose >= prevTrail && currClose < currTrail) ||
            (prevTrend == 1 && currTrend == -1);

      // 3. Support / Resistance Touches & Bounces
      case 'priceTouchesTrail':
        return currCandle.low <= currTrail && currCandle.high >= currTrail;
      case 'priceBouncesOffTrail':
        if (currTrend == 1) {
          return (currCandle.low <= currTrail || prevCandle.low <= prevTrail) &&
              currClose > currTrail &&
              currClose >= currCandle.open;
        } else {
          return (currCandle.high >= currTrail ||
                  prevCandle.high >= prevTrail) &&
              currClose < currTrail &&
              currClose <= currCandle.open;
        }

      // 4. Continuous Trend Regimes
      case 'inBullishTrend':
        return currTrend == 1;
      case 'inBearishTrend':
        return currTrend == -1;
      case 'priceAboveTrail':
        return currClose > currTrail;
      case 'priceBelowTrail':
        return currClose < currTrail;

      // 5. Trailing Stop Momentum
      case 'trailRising':
        return currTrail > prevTrail;
      case 'trailFalling':
        return currTrail < prevTrail;
      case 'trailFlat':
        return currTrail == prevTrail;

      // 6. Distance / Proximity to Trail
      case 'priceDistanceGreaterThan':
        return currDistanceRatio >= distThreshold;
      case 'priceDistanceLessThan':
        return currDistanceRatio <= distThreshold;

      default:
        return false;
    }
  }

  static Map<String, dynamic> calculateSupertrend(
    List<BiquoteCandle> candles,
    int period,
    double multiplier, {
    String source = 'HL2',
    String atrSmoothing = 'RMA',
  }) {
    final n = candles.length;
    final atr = _calculateAtr(candles, period, smoothing: atrSmoothing);
    if (atr.length < n) {
      return {
        'trend': <int>[],
        'supertrend': <double>[],
        'upperBand': <double>[],
        'lowerBand': <double>[],
      };
    }

    final trends = <int>[];
    final supertrendSeries = <double>[];
    final upperBands = <double>[];
    final lowerBands = <double>[];
    double upperBand = 0.0;
    double lowerBand = 0.0;
    int trend = 1;

    for (int i = 0; i < n; i++) {
      final c = candles[i];
      double basePrice;
      switch (source.toLowerCase()) {
        case 'close':
          basePrice = c.close;
          break;
        case 'open':
          basePrice = c.open;
          break;
        case 'high':
          basePrice = c.high;
          break;
        case 'low':
          basePrice = c.low;
          break;
        case 'hlc3':
          basePrice = (c.high + c.low + c.close) / 3.0;
          break;
        case 'ohlc4':
          basePrice = (c.open + c.high + c.low + c.close) / 4.0;
          break;
        case 'hl2':
        default:
          basePrice = (c.high + c.low) / 2.0;
          break;
      }
      final curAtr = atr[i];

      final basicUpper = basePrice + (multiplier * curAtr);
      final basicLower = basePrice - (multiplier * curAtr);

      if (i == 0) {
        upperBand = basicUpper;
        lowerBand = basicLower;
        trend = 1;
      } else {
        final prevClose = candles[i - 1].close;
        lowerBand = (basicLower > lowerBand || prevClose < lowerBand)
            ? basicLower
            : lowerBand;
        upperBand = (basicUpper < upperBand || prevClose > upperBand)
            ? basicUpper
            : upperBand;

        if (trend == 1 && c.close < lowerBand) {
          trend = -1;
        } else if (trend == -1 && c.close > upperBand) {
          trend = 1;
        }
      }
      trends.add(trend);
      upperBands.add(upperBand);
      lowerBands.add(lowerBand);
      supertrendSeries.add(trend == 1 ? lowerBand : upperBand);
    }

    return {
      'trend': trends,
      'supertrend': supertrendSeries,
      'upperBand': upperBands,
      'lowerBand': lowerBands,
    };
  }

  // ==========================================
  // Helper Math: EMA, SMA, ATR
  // ==========================================
  static List<double> _calculateSmaSeries(List<double> values, int period) {
    if (values.length < period) return [];
    final sma = <double>[];
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += values[i];
    }
    sma.add(sum / period);

    for (int i = period; i < values.length; i++) {
      sum += values[i] - values[i - period];
      sma.add(sum / period);
    }
    return sma;
  }

  static List<double> _calculateEmaSeries(List<double> values, int period) {
    if (values.length < period) return [];
    final ema = <double>[];
    final k = 2.0 / (period + 1);

    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += values[i];
    }
    double currentEma = sum / period;
    ema.add(currentEma);

    for (int i = period; i < values.length; i++) {
      currentEma = (values[i] * k) + (currentEma * (1 - k));
      ema.add(currentEma);
    }
    return ema;
  }

  static List<double> _calculateWmaSeries(List<double> values, int period) {
    if (values.length < period) return [];
    final wma = <double>[];
    final denominator = (period * (period + 1)) / 2.0;

    for (int i = period - 1; i < values.length; i++) {
      double sum = 0.0;
      for (int j = 0; j < period; j++) {
        sum += values[i - period + 1 + j] * (j + 1);
      }
      wma.add(sum / denominator);
    }
    return wma;
  }

  static List<double> _calculateMaSeries(
    List<double> values,
    int period,
    String maType,
  ) {
    if (maType == 'SMA') return _calculateSmaSeries(values, period);
    if (maType == 'WMA') return _calculateWmaSeries(values, period);
    return _calculateEmaSeries(values, period);
  }

  static List<double> _calculateAtr(
    List<BiquoteCandle> candles,
    int period, {
    String smoothing = 'RMA',
  }) {
    final tr = <double>[];
    for (int i = 0; i < candles.length; i++) {
      if (i == 0) {
        tr.add(candles[i].high - candles[i].low);
      } else {
        final hl = candles[i].high - candles[i].low;
        final hc = (candles[i].high - candles[i - 1].close).abs();
        final lc = (candles[i].low - candles[i - 1].close).abs();
        tr.add(max(hl, max(hc, lc)));
      }
    }

    if (smoothing == 'SMA') {
      final sma = _calculateSmaSeries(tr, period);
      final pad = List.filled(
        candles.length - sma.length,
        sma.isNotEmpty ? sma.first : 0.0,
      );
      return [...pad, ...sma];
    } else if (smoothing == 'EMA') {
      final ema = _calculateEmaSeries(tr, period);
      final pad = List.filled(
        candles.length - ema.length,
        ema.isNotEmpty ? ema.first : 0.0,
      );
      return [...pad, ...ema];
    } else if (smoothing == 'WMA') {
      final wma = _calculateWmaSeries(tr, period);
      final pad = List.filled(
        candles.length - wma.length,
        wma.isNotEmpty ? wma.first : 0.0,
      );
      return [...pad, ...wma];
    }

    // Default RMA (Wilder's smoothing)
    final atr = <double>[];
    double sum = 0.0;
    for (int i = 0; i < candles.length; i++) {
      if (i < period) {
        sum += tr[i];
        atr.add(sum / (i + 1));
      } else {
        final cur = (atr[i - 1] * (period - 1) + tr[i]) / period;
        atr.add(cur);
      }
    }
    return atr;
  }
}
