import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../models/indicator_models.dart';
import '../models/market_models.dart';
import 'indicator_calculator.dart';
import 'storage_service.dart';

class IndicatorCalculationResult {
  final IndicatorConfig config;
  // Overlay indicators or primary line
  final List<double?> primary;
  // Secondary lines (e.g. BB lower/upper, MACD signal, Stoch %D)
  final List<double?>? secondary;
  final List<double?>? tertiary;
  // Histogram (e.g. MACD)
  final List<double?>? histogram;

  IndicatorCalculationResult({
    required this.config,
    required this.primary,
    this.secondary,
    this.tertiary,
    this.histogram,
  });
}

class IndicatorService {
  static final IndicatorService _instance = IndicatorService._internal();
  factory IndicatorService() => _instance;
  IndicatorService._internal();

  static const String _storageKey = 'chart_active_indicators_v1';
  List<IndicatorConfig>? _cachedIndicators;

  /// Load persisted indicators, or provide defaults if first run
  Future<List<IndicatorConfig>> loadActiveIndicators() async {
    if (_cachedIndicators != null) {
      return List.from(_cachedIndicators!);
    }

    try {
      final jsonStr = await StorageService.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final list = decoded
            .map((e) => IndicatorConfig.fromJson(e as Map<String, dynamic>))
            .toList();
        _cachedIndicators = list;
        return List.from(list);
      }
    } catch (e) {
      debugPrint('Error loading active indicators: $e');
    }

    // Default indicators matching Chart.dc.html (EMA 8 #FFD60A, EMA 21 #0A84FF, RSI 14 #BF5AF2)
    final defaults = [
      IndicatorConfig.defaultFor(IndicatorType.ema)
        ..inputs['period'] = 8
        ..colors['main'] = const Color(0xFFFFD60A).toARGB32(),
      IndicatorConfig.defaultFor(IndicatorType.ema)
        ..inputs['period'] = 21
        ..colors['main'] = const Color(0xFF0A84FF).toARGB32(),
      IndicatorConfig.defaultFor(IndicatorType.rsi)
        ..inputs['period'] = 14
        ..colors['main'] = const Color(0xFFBF5AF2).toARGB32(),
    ];
    _cachedIndicators = defaults;
    await saveActiveIndicators(defaults);
    return List.from(defaults);
  }

  /// Save indicators to disk
  Future<void> saveActiveIndicators(List<IndicatorConfig> indicators) async {
    _cachedIndicators = List.from(indicators);
    try {
      final jsonStr = jsonEncode(indicators.map((i) => i.toJson()).toList());
      await StorageService.setString(_storageKey, jsonStr);
    } catch (e) {
      debugPrint('Error saving indicators: $e');
    }
  }

  /// Calculates indicator values across the full list of candles
  IndicatorCalculationResult? calculate(
    IndicatorConfig config,
    List<BiquoteCandle> candles,
  ) {
    if (candles.isEmpty) return null;

    switch (config.type) {
      case IndicatorType.sma:
        final period = config.getInt('period', 20);
        final values = calculateSMA(candles, period);
        return IndicatorCalculationResult(config: config, primary: values);

      case IndicatorType.ema:
        final period = config.getInt('period', 20);
        final values = calculateEMA(candles, period);
        return IndicatorCalculationResult(config: config, primary: values);

      case IndicatorType.bollingerBands:
        final period = config.getInt('period', 20);
        final stdDev = config.getDouble('stdDev', 2.0);
        final bb = calculateBollingerBands(candles, period, stdDev);
        return IndicatorCalculationResult(
          config: config,
          primary: bb.basis,
          secondary: bb.upper,
          tertiary: bb.lower,
        );

      case IndicatorType.rsi:
        final period = config.getInt('period', 14);
        final rsi = calculateRSI(candles, period);
        return IndicatorCalculationResult(config: config, primary: rsi);

      case IndicatorType.macd:
        final fast = config.getInt('fastPeriod', 12);
        final slow = config.getInt('slowPeriod', 26);
        final signal = config.getInt('signalPeriod', 9);
        final macd = calculateMACD(candles, fast, slow, signal);
        return IndicatorCalculationResult(
          config: config,
          primary: macd.macd,
          secondary: macd.signal,
          histogram: macd.histogram,
        );

      case IndicatorType.stochastic:
        final kPeriod = config.getInt('kPeriod', 14);
        final dPeriod = config.getInt('dPeriod', 3);
        final smooth = config.getInt('smooth', 3);
        final stoch = calculateStochastic(candles, kPeriod, dPeriod, smooth);
        return IndicatorCalculationResult(
          config: config,
          primary: stoch.k,
          secondary: stoch.d,
        );

      case IndicatorType.supertrend:
        final period = config.getInt('period', 10);
        final mult = config.getDouble('multiplier', 3.0);
        final st = IndicatorCalculator.calculateSupertrend(
          candles,
          period,
          mult,
        );
        final stList =
            (st['supertrend'] as List<double>?)
                ?.map<double?>((e) => e)
                .toList() ??
            <double?>[];
        final dirList =
            (st['trend'] as List<int>?)
                ?.map<double?>((e) => e.toDouble())
                .toList() ??
            <double?>[];
        return IndicatorCalculationResult(
          config: config,
          primary: stList,
          secondary: dirList,
        );
    }
  }

  // --- Mathematics & Algorithms ---

  /// Simple Moving Average
  static List<double?> calculateSMA(List<BiquoteCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    if (candles.length < period || period <= 0) return result;

    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += candles[i].close;
    }
    result[period - 1] = sum / period;

    for (int i = period; i < candles.length; i++) {
      sum += candles[i].close - candles[i - period].close;
      result[i] = sum / period;
    }
    return result;
  }

  /// Exponential Moving Average
  static List<double?> calculateEMA(List<BiquoteCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    if (candles.length < period || period <= 0) return result;

    final multiplier = 2.0 / (period + 1);

    // Initial SMA for first EMA seed
    double sum = 0.0;
    for (int i = 0; i < period; i++) {
      sum += candles[i].close;
    }
    double prevEma = sum / period;
    result[period - 1] = prevEma;

    for (int i = period; i < candles.length; i++) {
      final currentEma = (candles[i].close - prevEma) * multiplier + prevEma;
      result[i] = currentEma;
      prevEma = currentEma;
    }
    return result;
  }

  /// Bollinger Bands (Basis, Upper, Lower)
  static ({List<double?> basis, List<double?> upper, List<double?> lower})
  calculateBollingerBands(
    List<BiquoteCandle> candles,
    int period,
    double stdDevMultiplier,
  ) {
    final basis = calculateSMA(candles, period);
    final upper = List<double?>.filled(candles.length, null);
    final lower = List<double?>.filled(candles.length, null);

    if (candles.length < period || period <= 0) {
      return (basis: basis, upper: upper, lower: lower);
    }

    for (int i = period - 1; i < candles.length; i++) {
      final sma = basis[i];
      if (sma == null) continue;

      double varianceSum = 0.0;
      for (int j = i - period + 1; j <= i; j++) {
        varianceSum += pow(candles[j].close - sma, 2);
      }
      final dev = sqrt(varianceSum / period);
      upper[i] = sma + (dev * stdDevMultiplier);
      lower[i] = sma - (dev * stdDevMultiplier);
    }

    return (basis: basis, upper: upper, lower: lower);
  }

  /// Wilder's Relative Strength Index (Standard TradingView RSI formula)
  static List<double?> calculateRSI(List<BiquoteCandle> candles, int period) {
    final result = List<double?>.filled(candles.length, null);
    if (candles.length <= period || period <= 0) return result;

    double gainSum = 0.0;
    double lossSum = 0.0;

    for (int i = 1; i <= period; i++) {
      final diff = candles[i].close - candles[i - 1].close;
      if (diff > 0) {
        gainSum += diff;
      } else {
        lossSum += diff.abs();
      }
    }

    double avgGain = gainSum / period;
    double avgLoss = lossSum / period;

    if (avgLoss == 0) {
      result[period] = 100.0;
    } else {
      final rs = avgGain / avgLoss;
      result[period] = 100.0 - (100.0 / (1.0 + rs));
    }

    for (int i = period + 1; i < candles.length; i++) {
      final diff = candles[i].close - candles[i - 1].close;
      final gain = diff > 0 ? diff : 0.0;
      final loss = diff < 0 ? diff.abs() : 0.0;

      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;

      if (avgLoss == 0) {
        result[i] = 100.0;
      } else {
        final rs = avgGain / avgLoss;
        result[i] = (100.0 - (100.0 / (1.0 + rs))).clamp(0.0, 100.0);
      }
    }

    return result;
  }

  /// MACD (MACD Line, Signal Line, Histogram)
  static ({List<double?> macd, List<double?> signal, List<double?> histogram})
  calculateMACD(
    List<BiquoteCandle> candles,
    int fastPeriod,
    int slowPeriod,
    int signalPeriod,
  ) {
    final macd = List<double?>.filled(candles.length, null);
    final signal = List<double?>.filled(candles.length, null);
    final histogram = List<double?>.filled(candles.length, null);

    if (candles.length < slowPeriod) {
      return (macd: macd, signal: signal, histogram: histogram);
    }

    final fastEma = calculateEMA(candles, fastPeriod);
    final slowEma = calculateEMA(candles, slowPeriod);

    for (int i = 0; i < candles.length; i++) {
      if (fastEma[i] != null && slowEma[i] != null) {
        macd[i] = fastEma[i]! - slowEma[i]!;
      }
    }

    // Now calculate EMA of the MACD series for the Signal line
    int firstMacdIndex = -1;
    for (int i = 0; i < macd.length; i++) {
      if (macd[i] != null) {
        firstMacdIndex = i;
        break;
      }
    }

    if (firstMacdIndex != -1 &&
        (macd.length - firstMacdIndex) >= signalPeriod) {
      final signalMult = 2.0 / (signalPeriod + 1);
      double sum = 0.0;
      for (int i = 0; i < signalPeriod; i++) {
        sum += macd[firstMacdIndex + i]!;
      }
      double prevSignal = sum / signalPeriod;
      final seedIdx = firstMacdIndex + signalPeriod - 1;
      signal[seedIdx] = prevSignal;
      histogram[seedIdx] = macd[seedIdx]! - prevSignal;

      for (int i = seedIdx + 1; i < macd.length; i++) {
        final val = macd[i]!;
        final curSignal = (val - prevSignal) * signalMult + prevSignal;
        signal[i] = curSignal;
        histogram[i] = val - curSignal;
        prevSignal = curSignal;
      }
    }

    return (macd: macd, signal: signal, histogram: histogram);
  }

  /// Stochastic Oscillator (%K and %D)
  static ({List<double?> k, List<double?> d}) calculateStochastic(
    List<BiquoteCandle> candles,
    int kPeriod,
    int dPeriod,
    int smooth,
  ) {
    final rawK = List<double?>.filled(candles.length, null);
    final k = List<double?>.filled(candles.length, null);
    final d = List<double?>.filled(candles.length, null);

    if (candles.length < kPeriod) {
      return (k: k, d: d);
    }

    for (int i = kPeriod - 1; i < candles.length; i++) {
      double minLow = double.infinity;
      double maxHigh = double.negativeInfinity;
      for (int j = i - kPeriod + 1; j <= i; j++) {
        if (candles[j].low < minLow) minLow = candles[j].low;
        if (candles[j].high > maxHigh) maxHigh = candles[j].high;
      }
      final range = maxHigh - minLow;
      if (range > 0) {
        rawK[i] = ((candles[i].close - minLow) / range) * 100.0;
      } else {
        rawK[i] = 50.0;
      }
    }

    // Smoothing raw %K
    for (int i = 0; i < candles.length; i++) {
      if (rawK[i] == null) continue;
      if (i < smooth - 1) continue;

      double sum = 0.0;
      int count = 0;
      for (int j = i - smooth + 1; j <= i; j++) {
        if (j >= 0 && rawK[j] != null) {
          sum += rawK[j]!;
          count++;
        }
      }
      if (count == smooth) {
        k[i] = sum / count;
      }
    }

    // %D is SMA of %K
    for (int i = 0; i < candles.length; i++) {
      if (k[i] == null) continue;
      if (i < dPeriod - 1) continue;

      double sum = 0.0;
      int count = 0;
      for (int j = i - dPeriod + 1; j <= i; j++) {
        if (j >= 0 && k[j] != null) {
          sum += k[j]!;
          count++;
        }
      }
      if (count == dPeriod) {
        d[i] = sum / count;
      }
    }

    return (k: k, d: d);
  }
}
