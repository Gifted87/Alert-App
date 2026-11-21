import 'package:flutter/material.dart';

enum IndicatorType {
  rsi('RSI', 'Relative Strength Index', IndicatorPlacement.subPane),
  macd(
    'MACD',
    'Moving Average Convergence Divergence',
    IndicatorPlacement.subPane,
  ),
  stochastic('Stoch', 'Stochastic Oscillator', IndicatorPlacement.subPane),
  ema('EMA', 'Exponential Moving Average', IndicatorPlacement.overlay),
  sma('SMA', 'Simple Moving Average', IndicatorPlacement.overlay),
  bollingerBands('BB', 'Bollinger Bands', IndicatorPlacement.overlay),
  supertrend(
    'Supertrend',
    'ATR Trailing Supertrend',
    IndicatorPlacement.overlay,
  );

  final String shortName;
  final String fullName;
  final IndicatorPlacement placement;

  const IndicatorType(this.shortName, this.fullName, this.placement);
}

enum IndicatorPlacement { overlay, subPane }

class IndicatorConfig {
  final String id;
  final IndicatorType type;
  bool isVisible;
  Map<String, dynamic> inputs;
  Map<String, int> colors;
  double lineWidth;

  IndicatorConfig({
    required this.id,
    required this.type,
    this.isVisible = true,
    required this.inputs,
    required this.colors,
    this.lineWidth = 1.8,
  });

  // Default initializers for each indicator
  factory IndicatorConfig.defaultFor(IndicatorType type) {
    final id = '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    switch (type) {
      case IndicatorType.rsi:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'period': 14, 'overbought': 70.0, 'oversold': 30.0},
          colors: {
            'main': const Color(0xFFAB47BC).toARGB32(), // Purple
            'upper': const Color(0xFFEF5350).toARGB32(), // Red dashed
            'lower': const Color(0xFF26A69A).toARGB32(), // Teal dashed
            'bandFill': const Color(0x1F7E57C2).toARGB32(), // Soft purple fill
          },
          lineWidth: 2.0,
        );

      case IndicatorType.macd:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'fastPeriod': 12, 'slowPeriod': 26, 'signalPeriod': 9},
          colors: {
            'macd': const Color(0xFF2962FF).toARGB32(), // Blue
            'signal': const Color(0xFFFF6D00).toARGB32(), // Orange
            'histUp': const Color(0xFF26A69A).toARGB32(), // Teal
            'histDown': const Color(0xFFEF5350).toARGB32(), // Red
          },
          lineWidth: 1.8,
        );

      case IndicatorType.stochastic:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {
            'kPeriod': 14,
            'dPeriod': 3,
            'smooth': 3,
            'overbought': 80.0,
            'oversold': 20.0,
          },
          colors: {
            'k': const Color(0xFF2196F3).toARGB32(), // Blue %K
            'd': const Color(0xFFFF9800).toARGB32(), // Orange %D
            'bandFill': const Color(0x152196F3).toARGB32(),
          },
          lineWidth: 1.8,
        );

      case IndicatorType.ema:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'period': 20},
          colors: {
            'main': const Color(0xFF00E5FF).toARGB32(), // Electric Cyan
          },
          lineWidth: 2.0,
        );

      case IndicatorType.sma:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'period': 50},
          colors: {
            'main': const Color(0xFFFFEB3B).toARGB32(), // Yellow
          },
          lineWidth: 2.0,
        );

      case IndicatorType.bollingerBands:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'period': 20, 'stdDev': 2.0},
          colors: {
            'basis': const Color(0xFFFF9800).toARGB32(), // Orange
            'upper': const Color(0xFF00E5FF).toARGB32(), // Cyan
            'lower': const Color(0xFF00E5FF).toARGB32(), // Cyan
            'fill': const Color(0x1A00E5FF).toARGB32(), // Semi-transparent Cyan
          },
          lineWidth: 1.5,
        );

      case IndicatorType.supertrend:
        return IndicatorConfig(
          id: id,
          type: type,
          inputs: {'period': 10, 'multiplier': 3.0},
          colors: {
            'bull': const Color(0xFF30D158).toARGB32(), // Bullish green
            'bear': const Color(0xFFFF453A).toARGB32(), // Bearish red
          },
          lineWidth: 2.0,
        );
    }
  }

  Color getColor(String key, Color fallback) {
    if (colors.containsKey(key)) {
      return Color(colors[key]!);
    }
    return fallback;
  }

  void setColor(String key, Color color) {
    colors[key] = color.toARGB32();
  }

  int getInt(String key, int fallback) {
    final v = inputs[key];
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  double getDouble(String key, double fallback) {
    final v = inputs[key];
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  bool getBool(String key, bool fallback) {
    final v = inputs[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return fallback;
  }

  String get titleWithParams {
    switch (type) {
      case IndicatorType.rsi:
        return 'RSI ${getInt('period', 14)}';
      case IndicatorType.macd:
        return 'MACD (${getInt('fastPeriod', 12)}, ${getInt('slowPeriod', 26)}, ${getInt('signalPeriod', 9)})';
      case IndicatorType.stochastic:
        return 'Stoch (${getInt('kPeriod', 14)}, ${getInt('dPeriod', 3)})';
      case IndicatorType.ema:
        return 'EMA (${getInt('period', 20)})';
      case IndicatorType.sma:
        return 'SMA (${getInt('period', 50)})';
      case IndicatorType.bollingerBands:
        return 'BB (${getInt('period', 20)}, ${getDouble('stdDev', 2.0).toStringAsFixed(1)})';
      case IndicatorType.supertrend:
        return 'Supertrend (${getInt('period', 10)}, ×${getDouble('multiplier', 3.0).toStringAsFixed(1)})';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'isVisible': isVisible,
    'inputs': inputs,
    'colors': colors,
    'lineWidth': lineWidth,
  };

  factory IndicatorConfig.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'rsi';
    final type = IndicatorType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => IndicatorType.rsi,
    );

    final defaultCfg = IndicatorConfig.defaultFor(type);

    return IndicatorConfig(
      id: json['id'] as String? ?? defaultCfg.id,
      type: type,
      isVisible: json['isVisible'] as bool? ?? true,
      inputs: json['inputs'] != null
          ? Map<String, dynamic>.from(json['inputs'] as Map)
          : defaultCfg.inputs,
      colors: json['colors'] != null
          ? Map<String, int>.from(
              (json['colors'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toInt()),
              ),
            )
          : defaultCfg.colors,
      lineWidth:
          (json['lineWidth'] as num?)?.toDouble() ?? defaultCfg.lineWidth,
    );
  }

  IndicatorConfig copyWith({
    String? id,
    IndicatorType? type,
    bool? isVisible,
    Map<String, dynamic>? inputs,
    Map<String, int>? colors,
    double? lineWidth,
  }) {
    return IndicatorConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      isVisible: isVisible ?? this.isVisible,
      inputs: inputs != null ? Map.from(inputs) : Map.from(this.inputs),
      colors: colors != null ? Map.from(colors) : Map.from(this.colors),
      lineWidth: lineWidth ?? this.lineWidth,
    );
  }
}
