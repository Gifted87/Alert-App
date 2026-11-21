import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/indicator_models.dart';
import '../models/market_models.dart';
import '../theme/app_theme.dart';
import '../screens/create_alert_sheet.dart';

class IndicatorCatalogSheet extends StatefulWidget {
  final List<IndicatorConfig> activeIndicators;
  final ValueChanged<List<IndicatorConfig>> onIndicatorsChanged;
  final String? symbol;
  final double? currentPrice;
  final int? precision;

  const IndicatorCatalogSheet({
    super.key,
    required this.activeIndicators,
    required this.onIndicatorsChanged,
    this.symbol,
    this.currentPrice,
    this.precision,
  });

  static Future<void> show(
    BuildContext context, {
    required List<IndicatorConfig> activeIndicators,
    required ValueChanged<List<IndicatorConfig>> onIndicatorsChanged,
    String? symbol,
    double? currentPrice,
    int? precision,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IndicatorCatalogSheet(
        activeIndicators: activeIndicators,
        onIndicatorsChanged: onIndicatorsChanged,
        symbol: symbol,
        currentPrice: currentPrice,
        precision: precision,
      ),
    );
  }

  @override
  State<IndicatorCatalogSheet> createState() => _IndicatorCatalogSheetState();
}

class _IndicatorCatalogSheetState extends State<IndicatorCatalogSheet> {
  late List<IndicatorConfig> _active;
  int _selectedFilterIndex = 0; // 0: All, 1: Overlays, 2: Oscillators
  String?
  _expandedConfigId; // Chip-driven expansion (null on launch or empty state)

  // ─── FULLY EDITABLE TUNER VARIABLES FOR ALL INDICATORS ───────────────────
  // RSI Variables
  int _rsiPeriod = 14;
  String _rsiMethod = 'Wilder RMA'; // 'Wilder RMA', 'EMA', 'SMA'
  double _rsiOverbought = 70.0;
  double _rsiOversold = 30.0;
  final String _rsiSource = 'Close';
  String _rsiCondition = 'Crosses above 30';

  // Moving Averages Variables (Completely dynamic, NO predefined buttons)
  String _maType = 'EMA'; // 'EMA', 'SMA', 'WMA'
  int _maPeriod = 21;
  String _maSource = 'Close';
  final Color _maColor = const Color(0xFFFFD60A);
  final double _maLineWidth = 2.0;
  String _maCondition = 'Price crosses above MA';

  // MACD Variables
  int _macdFast = 12;
  int _macdSlow = 26;
  int _macdSignal = 9;
  final String _macdSource = 'Close';
  String _macdCondition = 'MACD crosses above Signal';

  // Bollinger Bands Variables
  int _bbPeriod = 20;
  double _bbStdDev = 2.0;
  final String _bbMaType = 'SMA';
  final String _bbSource = 'Close';
  String _bbCondition = 'Price touches Upper Band';

  // Stochastic Variables
  int _stochK = 14;
  int _stochSmooth = 3;
  int _stochD = 3;
  double _stochOverbought = 80.0;
  double _stochOversold = 20.0;
  String _stochCondition = '%K crosses above %D';

  // Supertrend Variables
  int _stAtrPeriod = 10;
  double _stMultiplier = 3.0;
  final String _stSource = 'HL2';
  String _stCondition = 'Bullish Flip (Green)';

  // Trading palette swatches
  static const List<Color> _maPalette = [
    Color(0xFFFFD60A), // Gold
    Color(0xFF0A84FF), // Electric Blue / Cyan
    Color(0xFFFF9800), // Amber / Orange
    Color(0xFF30D158), // Green
    Color(0xFFBF5AF2), // Purple
    Color(0xFFEF5350), // Coral Red
    Color(0xFF2962FF), // Royal Blue
    Color(0xFFFFFFFF), // Crisp White
  ];

  @override
  void initState() {
    super.initState();
    _active = List.from(widget.activeIndicators);

    // Initialise tuners from existing active configs if available
    for (final c in _active) {
      if (c.type == IndicatorType.rsi) {
        _rsiPeriod = c.getInt('period', 14);
        _rsiMethod = c.getBool('isWilder', true) ? 'Wilder RMA' : 'EMA';
        _rsiOverbought = c.getDouble('overbought', 70.0);
        _rsiOversold = c.getDouble('oversold', 30.0);
      } else if (c.type == IndicatorType.macd) {
        _macdFast = c.getInt('fastPeriod', 12);
        _macdSlow = c.getInt('slowPeriod', 26);
        _macdSignal = c.getInt('signalPeriod', 9);
      } else if (c.type == IndicatorType.bollingerBands) {
        _bbPeriod = c.getInt('period', 20);
        _bbStdDev = c.getDouble('stdDev', 2.0);
      } else if (c.type == IndicatorType.stochastic) {
        _stochK = c.getInt('kPeriod', 14);
        _stochSmooth = c.getInt('smooth', 3);
        _stochD = c.getInt('dPeriod', 3);
        _stochOverbought = c.getDouble('overbought', 80.0);
        _stochOversold = c.getDouble('oversold', 20.0);
      } else if (c.type == IndicatorType.supertrend) {
        _stAtrPeriod = c.getInt('period', 10);
        _stMultiplier = c.getDouble('multiplier', 3.0);
      } else if (c.type == IndicatorType.ema || c.type == IndicatorType.sma) {
        _maType = c.type == IndicatorType.ema ? 'EMA' : 'SMA';
        _maPeriod = c.getInt('period', 21);
      }
    }
  }

  void _notifyChanges() {
    widget.onIndicatorsChanged(List.from(_active));
  }

  // ─── POPUP DIALOG TO ENTER ANY CUSTOM NUMBER ──────────────────────────────
  Future<void> _showNumberInputDialog({
    required String title,
    required num currentValue,
    required bool isDecimal,
    required ValueChanged<num> onConfirm,
    num min = 1,
    num max = 1000,
  }) async {
    HapticFeedback.lightImpact();
    final controller = TextEditingController(
      text: isDecimal
          ? currentValue.toStringAsFixed(1)
          : currentValue.toInt().toString(),
    );

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          title: Text(
            title,
            style: AppTheme.sans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter any custom value ($min - $max):',
                style: AppTheme.sans(
                  fontSize: 12,
                  color: const Color.fromRGBO(235, 235, 245, 0.62),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: isDecimal,
                ),
                style: AppTheme.mono(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: AppTheme.sans(
                  color: const Color.fromRGBO(235, 235, 245, 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final val = num.tryParse(controller.text.trim());
                if (val != null && val >= min && val <= max) {
                  onConfirm(val);
                  Navigator.of(ctx).pop();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A84FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Apply',
                style: AppTheme.sans(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── INLINE COLOR & LINE WIDTH TUNER ─────────────────────────────────────
  Widget _buildColorAndWidthRow(IndicatorConfig config) {
    String primaryColorKey = 'main';
    if (config.type == IndicatorType.macd) primaryColorKey = 'macd';
    if (config.type == IndicatorType.stochastic) primaryColorKey = 'k';
    if (config.type == IndicatorType.bollingerBands) primaryColorKey = 'basis';
    if (config.type == IndicatorType.supertrend) primaryColorKey = 'bull';

    final currentColor = config.getColor(
      primaryColorKey,
      const Color(0xFF0A84FF),
    );
    final currentWidth = config.lineWidth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Color & Line Style',
              style: AppTheme.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color.fromRGBO(235, 235, 245, 0.75),
              ),
            ),
            Row(
              children: [1.0, 1.5, 2.0, 3.0].map((w) {
                final isSelected = (currentWidth - w).abs() < 0.25;
                final label = w == 1.0 || w == 2.0 || w == 3.0
                    ? '${w.toInt()}px'
                    : '${w}px';
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      config.lineWidth = w;
                    });
                    _notifyChanges();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0A84FF)
                          : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: AppTheme.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : const Color.fromRGBO(235, 235, 245, 0.62),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _maPalette.map((color) {
            final isCur = currentColor.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  config.setColor(primaryColorKey, color);
                  if (config.type == IndicatorType.supertrend) {
                    config.setColor('bull', color);
                  }
                });
                _notifyChanges();
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isCur
                      ? Border.all(color: Colors.white, width: 2.5)
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                          width: 1,
                        ),
                  boxShadow: isCur
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.60),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isCur
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.black,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── OPEN CREATE ALERT WITH INITIAL INDICATOR CONFIG ─────────────────────
  void _openCreateAlertWithConfig(IndicatorConfig config, {String? condition}) {
    final sym = widget.symbol ?? 'EURUSD';
    final price = widget.currentPrice ?? 1.0850;
    final prec = widget.precision ?? 5;

    AlertIndicatorType alertType = AlertIndicatorType.rsi;
    String cond = condition ?? 'crossesAbove';
    Map<String, dynamic> params = Map<String, dynamic>.from(config.inputs);

    switch (config.type) {
      case IndicatorType.rsi:
        alertType = AlertIndicatorType.rsi;
        cond = 'crossesBelowOversold';
        params['period'] = config.getInt('period', _rsiPeriod);
        params['overbought'] = config.getDouble('overbought', _rsiOverbought);
        params['oversold'] = config.getDouble('oversold', _rsiOversold);
        params['source'] = config.inputs['source'] ?? _rsiSource;
        if (condition == 'Crosses above 30') {
          cond = 'crossesAboveLevel';
          params['level'] = 30.0;
        } else if (condition == 'Crosses below 70') {
          cond = 'crossesBelowLevel';
          params['level'] = 70.0;
        } else if (condition == 'Centerline 50') {
          cond = 'crossesAboveLevel';
          params['level'] = 50.0;
        } else if (condition == 'Turning up') {
          cond = 'crossesAboveOversold';
        }
        break;

      case IndicatorType.macd:
        alertType = AlertIndicatorType.macd;
        cond = 'bullishSignalCross';
        params['fast'] = config.getInt('fastPeriod', _macdFast);
        params['slow'] = config.getInt('slowPeriod', _macdSlow);
        params['signal'] = config.getInt('signalPeriod', _macdSignal);
        params['source'] = config.inputs['source'] ?? _macdSource;
        if (condition == 'MACD crosses above Signal') {
          cond = 'bullishSignalCross';
        }
        if (condition == 'MACD crosses below Signal') {
          cond = 'bearishSignalCross';
        }
        if (condition == 'Histogram flips Positive') {
          cond = 'histogramFlipPositive';
        }
        if (condition == 'Histogram flips Negative') {
          cond = 'histogramFlipNegative';
        }
        if (condition == 'Zero line cross') {
          cond = 'zeroLineCross';
        }
        break;

      case IndicatorType.ema:
      case IndicatorType.sma:
        alertType = AlertIndicatorType.maCross;
        cond = 'priceCrossesAbove';
        params['fastPeriod'] = config.getInt('period', _maPeriod);
        params['slowPeriod'] = 50;
        params['maType'] =
            (config.inputs['maType'] as String?) ??
            (config.type == IndicatorType.sma ? 'SMA' : 'EMA');
        params['source'] = config.inputs['source'] ?? _maSource;
        if (condition == 'Price crosses above MA') cond = 'priceCrossesAbove';
        if (condition == 'Price crosses below MA') cond = 'priceCrossesBelow';
        if (condition == 'Price bounces off MA') cond = 'priceBounces';
        break;

      case IndicatorType.bollingerBands:
        alertType = AlertIndicatorType.bollingerBands;
        cond = 'touchesUpper';
        params['period'] = config.getInt('period', _bbPeriod);
        params['stdDev'] = config.getDouble('stdDev', _bbStdDev);
        params['maType'] = config.inputs['maType'] ?? _bbMaType;
        params['source'] = config.inputs['source'] ?? _bbSource;
        if (condition == 'Price touches Upper Band') cond = 'touchesUpper';
        if (condition == 'Price touches Lower Band') cond = 'touchesLower';
        if (condition == 'Band Squeeze') cond = 'bandSqueeze';
        if (condition == 'Band Expansion') cond = 'bandExpansion';
        break;

      case IndicatorType.stochastic:
        alertType = AlertIndicatorType.stochastic;
        cond = 'kCrossesAboveD';
        params['kPeriod'] = config.getInt('kPeriod', _stochK);
        params['kSlowing'] = config.getInt('smooth', _stochSmooth);
        params['dPeriod'] = config.getInt('dPeriod', _stochD);
        params['overbought'] = config.getDouble('overbought', _stochOverbought);
        params['oversold'] = config.getDouble('oversold', _stochOversold);
        if (condition == '%K crosses above %D') cond = 'kCrossesAboveD';
        if (condition == '%K crosses below %D') cond = 'kCrossesBelowD';
        if (condition == 'Exits Oversold (20)') cond = 'crossesAboveOversold';
        if (condition == 'Exits Overbought (80)') {
          cond = 'crossesBelowOverbought';
        }
        break;

      case IndicatorType.supertrend:
        alertType = AlertIndicatorType.supertrend;
        cond = 'bullishFlip';
        params['period'] = config.getInt('period', _stAtrPeriod);
        params['multiplier'] = config.getDouble('multiplier', _stMultiplier);
        params['source'] = config.inputs['source'] ?? _stSource;
        if (condition == 'Bullish Flip (Green)') cond = 'bullishFlip';
        if (condition == 'Bearish Flip (Red)') cond = 'bearishFlip';
        if (condition == 'Price touches Trendline') cond = 'touchesTrendline';
        break;
    }

    final alertConfig = IndicatorAlertConfig(
      indicatorType: alertType,
      condition: cond,
      params: params,
    );

    Navigator.of(context).pop();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateAlertSheet(
        symbol: sym,
        currentPrice: price,
        precision: prec,
        initialAlertType: AlertType.technicalIndicator,
        initialIndicatorConfig: alertConfig,
        onAlertCreated: ({
          required String symbol,
          AlertType alertType = AlertType.priceLevel,
          double targetPrice = 0.0,
          AlertCondition condition = AlertCondition.crossesAbove,
          CandlestickPattern? candlestickPattern,
          IndicatorAlertConfig? indicatorConfig,
          MultiStepConfig? multiStepConfig,
          String timeframe = '1H',
          String note = '',
          String ringtoneTitle = 'Trading Bell',
          String? ringtoneUri,
          String? drawingId,
          List<String>? targetSymbols,
          bool? triggerOnCandleClose,
          int? cooldownMinutes,
        }) {},
      ),
    );
  }

  // ─── ADD A NEW CONFIGURATION WITH CURRENT TUNED VARIABLES ─────────────────
  void _addConfiguration(IndicatorType type) {
    HapticFeedback.mediumImpact();
    final newId = '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    IndicatorConfig newConfig;

    switch (type) {
      case IndicatorType.rsi:
        newConfig = IndicatorConfig(
          id: newId,
          type: type,
          inputs: {
            'period': _rsiPeriod,
            'isWilder': _rsiMethod == 'Wilder RMA',
            'method': _rsiMethod,
            'source': _rsiSource,
            'overbought': _rsiOverbought,
            'oversold': _rsiOversold,
          },
          colors: {
            'main': const Color(0xFFAB47BC).toARGB32(),
            'upper': const Color(0xFFEF5350).toARGB32(),
            'lower': const Color(0xFF26A69A).toARGB32(),
            'bandFill': const Color(0x1F7E57C2).toARGB32(),
          },
          lineWidth: 2.0,
        );
        break;

      case IndicatorType.macd:
        newConfig = IndicatorConfig(
          id: newId,
          type: type,
          inputs: {
            'fastPeriod': _macdFast,
            'slowPeriod': _macdSlow,
            'signalPeriod': _macdSignal,
            'source': _macdSource,
          },
          colors: {
            'macd': const Color(0xFF2962FF).toARGB32(),
            'signal': const Color(0xFFFF6D00).toARGB32(),
            'histUp': const Color(0xFF26A69A).toARGB32(),
            'histDown': const Color(0xFFEF5350).toARGB32(),
          },
          lineWidth: 1.8,
        );
        break;

      case IndicatorType.ema:
      case IndicatorType.sma:
        final actualType = _maType == 'SMA'
            ? IndicatorType.sma
            : IndicatorType.ema;
        newConfig = IndicatorConfig(
          id: '${actualType.name}_${DateTime.now().millisecondsSinceEpoch}',
          type: actualType,
          inputs: {'period': _maPeriod, 'source': _maSource, 'maType': _maType},
          colors: {'main': _maColor.toARGB32()},
          lineWidth: _maLineWidth,
        );
        break;

      case IndicatorType.bollingerBands:
        newConfig = IndicatorConfig(
          id: newId,
          type: type,
          inputs: {
            'period': _bbPeriod,
            'stdDev': _bbStdDev,
            'maType': _bbMaType,
            'source': _bbSource,
          },
          colors: {
            'basis': const Color(0xFFFF9800).toARGB32(),
            'upper': const Color(0xFF00E5FF).toARGB32(),
            'lower': const Color(0xFF00E5FF).toARGB32(),
            'fill': const Color(0x1A00E5FF).toARGB32(),
          },
          lineWidth: 1.5,
        );
        break;

      case IndicatorType.stochastic:
        newConfig = IndicatorConfig(
          id: newId,
          type: type,
          inputs: {
            'kPeriod': _stochK,
            'dPeriod': _stochD,
            'smooth': _stochSmooth,
            'overbought': _stochOverbought,
            'oversold': _stochOversold,
          },
          colors: {
            'k': const Color(0xFF2196F3).toARGB32(),
            'd': const Color(0xFFFF9800).toARGB32(),
            'bandFill': const Color(0x152196F3).toARGB32(),
          },
          lineWidth: 1.8,
        );
        break;

      case IndicatorType.supertrend:
        newConfig = IndicatorConfig(
          id: newId,
          type: type,
          inputs: {
            'period': _stAtrPeriod,
            'multiplier': _stMultiplier,
            'source': _stSource,
          },
          colors: {
            'bull': const Color(0xFF30D158).toARGB32(),
            'bear': const Color(0xFFFF453A).toARGB32(),
          },
          lineWidth: 2.0,
        );
        break;
    }

    setState(() {
      _active.add(newConfig);
      _expandedConfigId =
          newConfig.id; // Auto-expand newly added chip for immediate tuning
    });
    _notifyChanges();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${newConfig.titleWithParams} to chart',
          style: AppTheme.sans(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _removeConfig(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      _active.removeWhere((i) => i.id == id);
      if (_expandedConfigId == id) {
        _expandedConfigId = null;
      }
    });
    _notifyChanges();
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.90;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E), // Exact background from Indicators.dc.html
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        border: Border(
          top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.10), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.60),
            blurRadius: 60,
            offset: Offset(0, -20),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle pill matching Indicators.dc.html line 39
          Center(
            child: Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3C),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Header Row matching Indicators.dc.html line 40-43
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Indicators',
                style: AppTheme.sans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Done',
                    style: AppTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Category Segmented Bar matching Indicators.dc.html line 44 (.seg)
          Container(
            height: 36,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildSegmentButton('All', 0),
                _buildSegmentButton('Overlays', 1),
                _buildSegmentButton('Oscillators', 2),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Indicator Cards List matching Indicators.dc.html lines 46-70
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                // 1. RSI (Oscillator)
                if (_shouldShowIndicator(isOverlay: false)) ...[
                  _buildRsiCard(),
                  const SizedBox(height: 8),
                ],

                // 2. MACD (Oscillator)
                if (_shouldShowIndicator(isOverlay: false)) ...[
                  _buildMacdCard(),
                  const SizedBox(height: 8),
                ],

                // 3. Moving Averages (Overlay)
                if (_shouldShowIndicator(isOverlay: true)) ...[
                  _buildMovingAveragesCard(),
                  const SizedBox(height: 8),
                ],

                // 4. Bollinger Bands (Overlay)
                if (_shouldShowIndicator(isOverlay: true)) ...[
                  _buildBollingerBandsCard(),
                  const SizedBox(height: 8),
                ],

                // 5. Stochastic (Oscillator)
                if (_shouldShowIndicator(isOverlay: false)) ...[
                  _buildStochasticCard(),
                  const SizedBox(height: 8),
                ],

                // 6. Supertrend (Overlay)
                if (_shouldShowIndicator(isOverlay: true)) ...[
                  _buildSupertrendCard(),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowIndicator({required bool isOverlay}) {
    if (_selectedFilterIndex == 0) return true; // All
    if (_selectedFilterIndex == 1) return isOverlay; // Overlays
    return !isOverlay; // Oscillators
  }

  Widget _buildSegmentButton(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilterIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3A3A3C) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.40),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected
                  ? Colors.white
                  : const Color.fromRGBO(235, 235, 245, 0.62),
            ),
          ),
        ),
      ),
    );
  }

  // ─── PLUS BUTTON COMPONENT (Supports adding multiple instances) ───────────
  Widget _buildPlusButton({
    required VoidCallback onAdd,
    required int activeCount,
  }) {
    return GestureDetector(
      onTap: onAdd,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: activeCount > 0
              ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
              : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: activeCount > 0
                ? const Color(0xFF0A84FF)
                : Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 20, color: Colors.white),
            if (activeCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A84FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount',
                  style: AppTheme.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── ACTIVE CONFIGURATION PILLS (Tappable to toggle inline tuning dropdown) ──
  Widget _buildActiveConfigurationsPillList(List<IndicatorConfig> configs) {
    if (configs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: configs.map((c) {
          final colorVal =
              c.colors['main'] ??
              c.colors['macd'] ??
              c.colors['k'] ??
              c.colors['basis'] ??
              c.colors['bull'];
          final dotColor = colorVal != null
              ? Color(colorVal)
              : const Color(0xFF0A84FF);
          final isExpanded = _expandedConfigId == c.id;

          return Container(
            decoration: BoxDecoration(
              color: isExpanded
                  ? const Color(0xFF0A84FF).withValues(alpha: 0.18)
                  : const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isExpanded
                    ? const Color(0xFF0A84FF)
                    : Colors.white.withValues(alpha: 0.12),
                width: isExpanded ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pill Body: Tap to toggle inline config dropdown
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _expandedConfigId = isExpanded ? null : c.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          c.titleWithParams,
                          style: AppTheme.mono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isExpanded
                                ? Colors.white
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: isExpanded
                              ? const Color(0xFF4DA3FF)
                              : const Color.fromRGBO(235, 235, 245, 0.45),
                        ),
                      ],
                    ),
                  ),
                ),
                // Dedicated Delete Button: Completely isolated from pill body
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _removeConfig(c.id),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Color.fromRGBO(235, 235, 245, 0.70),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── STEPPER ROW WITH DIRECT TAP-TO-TYPE NUMERIC INPUT ────────────────────
  Widget _buildEditableNumericRow({
    required String title,
    required num value,
    required bool isDecimal,
    required num step,
    required num min,
    required num max,
    required ValueChanged<num> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTheme.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Row(
          children: [
            _buildStepperBtn(
              icon: Icons.remove,
              onTap: () {
                final next = value - step;
                if (next >= min) {
                  onChanged(
                    isDecimal
                        ? double.parse(next.toStringAsFixed(1))
                        : next.round(),
                  );
                }
              },
            ),
            GestureDetector(
              onTap: () => _showNumberInputDialog(
                title: title,
                currentValue: value,
                isDecimal: isDecimal,
                min: min,
                max: max,
                onConfirm: onChanged,
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 42),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  isDecimal
                      ? value.toStringAsFixed(1)
                      : value.toInt().toString(),
                  style: AppTheme.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0A84FF),
                  ),
                ),
              ),
            ),
            _buildStepperBtn(
              icon: Icons.add,
              onTap: () {
                final next = value + step;
                if (next <= max) {
                  onChanged(
                    isDecimal
                        ? double.parse(next.toStringAsFixed(1))
                        : next.round(),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepperBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }

  // ─── 1. RSI CARD ──────────────────────────────────────────────────────────
  Widget _buildRsiCard() {
    final activeRsis = _active
        .where((c) => c.type == IndicatorType.rsi)
        .toList();
    final expandedRsi = activeRsis
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          GestureDetector(
            onTap: () {
              if (activeRsis.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedRsi != null)
                      ? null
                      : activeRsis.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Violet Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBF5AF2).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _SineWavePainter(color: const Color(0xFFD58CF7)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RSI',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeRsis.isNotEmpty
                            ? activeRsis
                                  .map((c) => c.titleWithParams)
                                  .join(' · ')
                            : 'Period $_rsiPeriod · $_rsiMethod · Sub-panel',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                // Plus button with counter
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.rsi),
                  activeCount: activeRsis.length,
                ),
              ],
            ),
          ),

          // Active Configurations Pills
          _buildActiveConfigurationsPillList(activeRsis),

          // Inline Config Dropdown (strictly hidden when no active indicator or not expanded)
          if (expandedRsi != null) ...[
            const SizedBox(height: 14),
            _buildRsiInlineConfig(expandedRsi),
          ],
        ],
      ),
    );
  }

  Widget _buildRsiInlineConfig(IndicatorConfig config) {
    final period = config.getInt('period', _rsiPeriod);
    final isWilder =
        config.inputs['isWilder'] ??
        (config.inputs['method'] == 'Wilder RMA' ||
            config.inputs['method'] == null);
    final method =
        (config.inputs['method'] as String?) ??
        (isWilder ? 'Wilder RMA' : 'EMA');
    final overbought = config.getDouble('overbought', _rsiOverbought);
    final oversold = config.getDouble('oversold', _rsiOversold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditableNumericRow(
          title: 'Period',
          value: period,
          isDecimal: false,
          step: 1,
          min: 2,
          max: 200,
          onChanged: (val) {
            setState(() {
              config.inputs['period'] = val.toInt();
              _rsiPeriod = val.toInt();
            });
            _notifyChanges();
          },
        ),
        const SizedBox(height: 12),
        Container(
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: ['Wilder RMA', 'EMA', 'SMA'].map((m) {
              final isCur = method == m;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      config.inputs['method'] = m;
                      config.inputs['isWilder'] = (m == 'Wilder RMA');
                      _rsiMethod = m;
                    });
                    _notifyChanges();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCur
                          ? const Color(0xFF3A3A3C)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      m,
                      style: AppTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isCur
                            ? Colors.white
                            : const Color.fromRGBO(235, 235, 245, 0.62),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildEditableNumericRow(
                title: 'Overbought',
                value: overbought,
                isDecimal: false,
                step: 1,
                min: 50,
                max: 95,
                onChanged: (val) {
                  setState(() {
                    config.inputs['overbought'] = val.toDouble();
                    _rsiOverbought = val.toDouble();
                  });
                  _notifyChanges();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildEditableNumericRow(
                title: 'Oversold',
                value: oversold,
                isDecimal: false,
                step: 1,
                min: 5,
                max: 50,
                onChanged: (val) {
                  setState(() {
                    config.inputs['oversold'] = val.toDouble();
                    _rsiOversold = val.toDouble();
                  });
                  _notifyChanges();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildColorAndWidthRow(config),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  'Crosses above 30',
                  'Crosses below 70',
                  'Centerline 50',
                  'Turning up',
                ].map((cond) {
                  final isChipSelected = _rsiCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _rsiCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isChipSelected
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isChipSelected
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cond,
                            style: AppTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isChipSelected
                                  ? const Color(0xFF4DA3FF)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _rsiCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from RSI',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 2. MACD CARD ──────────────────────────────────────────────────────────
  Widget _buildMacdCard() {
    final activeMacds = _active
        .where((c) => c.type == IndicatorType.macd)
        .toList();
    final expandedMacd = activeMacds
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              if (activeMacds.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedMacd != null)
                      ? null
                      : activeMacds.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Blue Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _HistogramIconPainter(
                      color: const Color(0xFF4DA3FF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MACD',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeMacds.isNotEmpty
                            ? activeMacds
                                  .map((c) => c.titleWithParams)
                                  .join(' · ')
                            : '$_macdFast · $_macdSlow · $_macdSignal · Histogram',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.macd),
                  activeCount: activeMacds.length,
                ),
              ],
            ),
          ),

          _buildActiveConfigurationsPillList(activeMacds),

          if (expandedMacd != null) ...[
            const SizedBox(height: 14),
            _buildMacdInlineConfig(expandedMacd),
          ],
        ],
      ),
    );
  }

  Widget _buildMacdInlineConfig(IndicatorConfig config) {
    final fast = config.getInt('fastPeriod', _macdFast);
    final slow = config.getInt('slowPeriod', _macdSlow);
    final signal = config.getInt('signalPeriod', _macdSignal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditableNumericRow(
          title: 'Fast Period',
          value: fast,
          isDecimal: false,
          step: 1,
          min: 2,
          max: 100,
          onChanged: (val) {
            setState(() {
              config.inputs['fastPeriod'] = val.toInt();
              _macdFast = val.toInt();
            });
            _notifyChanges();
          },
        ),
        const SizedBox(height: 10),
        _buildEditableNumericRow(
          title: 'Slow Period',
          value: slow,
          isDecimal: false,
          step: 1,
          min: 5,
          max: 200,
          onChanged: (val) {
            setState(() {
              config.inputs['slowPeriod'] = val.toInt();
              _macdSlow = val.toInt();
            });
            _notifyChanges();
          },
        ),
        const SizedBox(height: 10),
        _buildEditableNumericRow(
          title: 'Signal Period',
          value: signal,
          isDecimal: false,
          step: 1,
          min: 1,
          max: 50,
          onChanged: (val) {
            setState(() {
              config.inputs['signalPeriod'] = val.toInt();
              _macdSignal = val.toInt();
            });
            _notifyChanges();
          },
        ),
        const SizedBox(height: 14),
        _buildColorAndWidthRow(config),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  'MACD crosses above Signal',
                  'MACD crosses below Signal',
                  'Histogram flips Positive',
                  'Histogram flips Negative',
                  'Zero line cross',
                ].map((cond) {
                  final isChipSelected = _macdCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _macdCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isChipSelected
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isChipSelected
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cond,
                            style: AppTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isChipSelected
                                  ? const Color(0xFF4DA3FF)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _macdCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from MACD',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 3. MOVING AVERAGES CARD ──────────────────────────────────────────────
  Widget _buildMovingAveragesCard() {
    final activeMas = _active
        .where(
          (c) => c.type == IndicatorType.ema || c.type == IndicatorType.sma,
        )
        .toList();
    final expandedMa = activeMas
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              if (activeMas.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedMa != null)
                      ? null
                      : activeMas.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Gold Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD60A).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _MaCurveIconPainter(
                      color: const Color(0xFFFFD60A),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Moving Averages',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeMas.isNotEmpty
                            ? activeMas
                                  .map((m) => m.titleWithParams)
                                  .join(' · ')
                            : '$_maType $_maPeriod · Overlay',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.ema),
                  activeCount: activeMas.length,
                ),
              ],
            ),
          ),

          // Active MA Instances Pills
          _buildActiveConfigurationsPillList(activeMas),

          if (expandedMa != null) ...[
            const SizedBox(height: 14),
            _buildMaInlineConfig(expandedMa),
          ],
        ],
      ),
    );
  }

  Widget _buildMaInlineConfig(IndicatorConfig config) {
    final curMaType =
        (config.inputs['maType'] as String?) ??
        (config.type == IndicatorType.sma ? 'SMA' : 'EMA');
    final curPeriod = config.getInt('period', _maPeriod);
    final curSource = (config.inputs['source'] as String?) ?? _maSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // MA Type Segmented Control [EMA | SMA | WMA]
        Container(
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: ['EMA', 'SMA', 'WMA'].map((t) {
              final isCur = curMaType == t;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      config.inputs['maType'] = t;
                      _maType = t;
                    });
                    _notifyChanges();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCur
                          ? const Color(0xFF3A3A3C)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      t,
                      style: AppTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isCur
                            ? Colors.white
                            : const Color.fromRGBO(235, 235, 245, 0.62),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Period Stepper - User can type ANY number directly!
        _buildEditableNumericRow(
          title: 'Period (Length)',
          value: curPeriod,
          isDecimal: false,
          step: 1,
          min: 1,
          max: 500,
          onChanged: (val) {
            setState(() {
              config.inputs['period'] = val.toInt();
              _maPeriod = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 12),

        // Source Selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Source',
              style: AppTheme.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Container(
              height: 30,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: ['Close', 'Open', 'High', 'Low', 'HL2'].map((s) {
                  final isCur = curSource == s;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        config.inputs['source'] = s;
                        _maSource = s;
                      });
                      _notifyChanges();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isCur
                            ? const Color(0xFF3A3A3C)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s,
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCur ? Colors.white : Colors.white60,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        _buildColorAndWidthRow(config),

        const SizedBox(height: 14),

        // Condition Chips
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  'Price crosses above MA',
                  'Price crosses below MA',
                  'Price bounces off MA',
                ].map((cond) {
                  final isChipSelected = _maCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _maCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isChipSelected
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isChipSelected
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cond,
                            style: AppTheme.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isChipSelected
                                  ? const Color(0xFF4DA3FF)
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),

        const SizedBox(height: 14),

        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _maCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from MA',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 4. BOLLINGER BANDS CARD ──────────────────────────────────────────────
  Widget _buildBollingerBandsCard() {
    final activeBbs = _active
        .where((c) => c.type == IndicatorType.bollingerBands)
        .toList();
    final expandedBb = activeBbs
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              if (activeBbs.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedBb != null)
                      ? null
                      : activeBbs.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Purple Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBF5AF2).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _BandsIconPainter(color: const Color(0xFFD58CF7)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bollinger Bands',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeBbs.isNotEmpty
                            ? activeBbs
                                  .map((c) => c.titleWithParams)
                                  .join(' · ')
                            : '$_bbPeriod · ${_bbStdDev.toStringAsFixed(1)}σ · Squeeze alerts',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.bollingerBands),
                  activeCount: activeBbs.length,
                ),
              ],
            ),
          ),

          _buildActiveConfigurationsPillList(activeBbs),

          if (expandedBb != null) ...[
            const SizedBox(height: 14),
            _buildBbInlineConfig(expandedBb),
          ],
        ],
      ),
    );
  }

  Widget _buildBbInlineConfig(IndicatorConfig config) {
    final period = config.getInt('period', _bbPeriod);
    final stdDev = config.getDouble('stdDev', _bbStdDev);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Period
        _buildEditableNumericRow(
          title: 'Period',
          value: period,
          isDecimal: false,
          step: 1,
          min: 2,
          max: 200,
          onChanged: (val) {
            setState(() {
              config.inputs['period'] = val.toInt();
              _bbPeriod = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 10),

        // StdDev Multiplier
        _buildEditableNumericRow(
          title: 'StdDev Multiplier (σ)',
          value: stdDev,
          isDecimal: true,
          step: 0.1,
          min: 0.5,
          max: 5.0,
          onChanged: (val) {
            setState(() {
              config.inputs['stdDev'] = val.toDouble();
              _bbStdDev = val.toDouble();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 14),

        _buildColorAndWidthRow(config),

        const SizedBox(height: 14),

        // Conditions
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  'Price touches Upper Band',
                  'Price touches Lower Band',
                  'Band Squeeze',
                  'Band Expansion',
                ].map((cond) {
                  final isCur = _bbCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _bbCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isCur
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isCur
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cond,
                        style: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCur ? const Color(0xFF4DA3FF) : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),

        const SizedBox(height: 14),

        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _bbCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from BB',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 5. STOCHASTIC CARD ───────────────────────────────────────────────────
  Widget _buildStochasticCard() {
    final activeStochs = _active
        .where((c) => c.type == IndicatorType.stochastic)
        .toList();
    final expandedStoch = activeStochs
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              if (activeStochs.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedStoch != null)
                      ? null
                      : activeStochs.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Cyan Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF64D2FF).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _DoubleWaveIconPainter(
                      color: const Color(0xFF64D2FF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stochastic',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeStochs.isNotEmpty
                            ? activeStochs
                                  .map((c) => c.titleWithParams)
                                  .join(' · ')
                            : '%K $_stochK · Slow $_stochSmooth · %D $_stochD',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.stochastic),
                  activeCount: activeStochs.length,
                ),
              ],
            ),
          ),

          _buildActiveConfigurationsPillList(activeStochs),

          if (expandedStoch != null) ...[
            const SizedBox(height: 14),
            _buildStochInlineConfig(expandedStoch),
          ],
        ],
      ),
    );
  }

  Widget _buildStochInlineConfig(IndicatorConfig config) {
    final kPeriod = config.getInt('kPeriod', _stochK);
    final smooth = config.getInt('smooth', _stochSmooth);
    final dPeriod = config.getInt('dPeriod', _stochD);
    final overbought = config.getDouble('overbought', _stochOverbought);
    final oversold = config.getDouble('oversold', _stochOversold);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditableNumericRow(
          title: '%K Length',
          value: kPeriod,
          isDecimal: false,
          step: 1,
          min: 2,
          max: 100,
          onChanged: (val) {
            setState(() {
              config.inputs['kPeriod'] = val.toInt();
              _stochK = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 10),

        _buildEditableNumericRow(
          title: '%K Smoothing',
          value: smooth,
          isDecimal: false,
          step: 1,
          min: 1,
          max: 50,
          onChanged: (val) {
            setState(() {
              config.inputs['smooth'] = val.toInt();
              _stochSmooth = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 10),

        _buildEditableNumericRow(
          title: '%D Smoothing',
          value: dPeriod,
          isDecimal: false,
          step: 1,
          min: 1,
          max: 50,
          onChanged: (val) {
            setState(() {
              config.inputs['dPeriod'] = val.toInt();
              _stochD = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _buildEditableNumericRow(
                title: 'Overbought',
                value: overbought,
                isDecimal: false,
                step: 1,
                min: 50,
                max: 95,
                onChanged: (val) {
                  setState(() {
                    config.inputs['overbought'] = val.toDouble();
                    _stochOverbought = val.toDouble();
                  });
                  _notifyChanges();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(
              child: _buildEditableNumericRow(
                title: 'Oversold',
                value: oversold,
                isDecimal: false,
                step: 1,
                min: 5,
                max: 50,
                onChanged: (val) {
                  setState(() {
                    config.inputs['oversold'] = val.toDouble();
                    _stochOversold = val.toDouble();
                  });
                  _notifyChanges();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        _buildColorAndWidthRow(config),

        const SizedBox(height: 14),

        // Conditions
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  '%K crosses above %D',
                  '%K crosses below %D',
                  'Exits Oversold (20)',
                  'Exits Overbought (80)',
                ].map((cond) {
                  final isCur = _stochCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _stochCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isCur
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isCur
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cond,
                        style: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCur ? const Color(0xFF4DA3FF) : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),

        const SizedBox(height: 14),

        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _stochCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from Stoch',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 6. SUPERTREND CARD ───────────────────────────────────────────────────
  Widget _buildSupertrendCard() {
    final activeSts = _active
        .where((c) => c.type == IndicatorType.supertrend)
        .toList();
    final expandedSt = activeSts
        .where((c) => c.id == _expandedConfigId)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              if (activeSts.isNotEmpty) {
                setState(
                  () => _expandedConfigId = (expandedSt != null)
                      ? null
                      : activeSts.first.id,
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                // Green Tile (.tile)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _SupertrendIconPainter(
                      color: const Color(0xFF43E06A),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supertrend',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeSts.isNotEmpty
                            ? activeSts
                                  .map((c) => c.titleWithParams)
                                  .join(' · ')
                            : 'ATR $_stAtrPeriod · ×${_stMultiplier.toStringAsFixed(1)} · Flip alerts',
                        style: AppTheme.mono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromRGBO(235, 235, 245, 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPlusButton(
                  onAdd: () => _addConfiguration(IndicatorType.supertrend),
                  activeCount: activeSts.length,
                ),
              ],
            ),
          ),

          _buildActiveConfigurationsPillList(activeSts),

          if (expandedSt != null) ...[
            const SizedBox(height: 14),
            _buildStInlineConfig(expandedSt),
          ],
        ],
      ),
    );
  }

  Widget _buildStInlineConfig(IndicatorConfig config) {
    final atrPeriod = config.getInt('period', _stAtrPeriod);
    final multiplier = config.getDouble('multiplier', _stMultiplier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ATR Period
        _buildEditableNumericRow(
          title: 'ATR Length (Period)',
          value: atrPeriod,
          isDecimal: false,
          step: 1,
          min: 1,
          max: 100,
          onChanged: (val) {
            setState(() {
              config.inputs['period'] = val.toInt();
              _stAtrPeriod = val.toInt();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 10),

        // Multiplier
        _buildEditableNumericRow(
          title: 'Factor (Multiplier)',
          value: multiplier,
          isDecimal: true,
          step: 0.1,
          min: 0.5,
          max: 10.0,
          onChanged: (val) {
            setState(() {
              config.inputs['multiplier'] = val.toDouble();
              _stMultiplier = val.toDouble();
            });
            _notifyChanges();
          },
        ),

        const SizedBox(height: 14),

        _buildColorAndWidthRow(config),

        const SizedBox(height: 14),

        // Conditions
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                [
                  'Bullish Flip (Green)',
                  'Bearish Flip (Red)',
                  'Price touches Trendline',
                ].map((cond) {
                  final isCur = _stCondition == cond;
                  return GestureDetector(
                    onTap: () => setState(() => _stCondition = cond),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isCur
                            ? const Color(0xFF0A84FF).withValues(alpha: 0.20)
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(15),
                        border: isCur
                            ? Border.all(
                                color: const Color(0xFF0A84FF)
                                    .withValues(alpha: 0.40),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cond,
                        style: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isCur ? const Color(0xFF4DA3FF) : Colors.white,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),

        const SizedBox(height: 14),

        GestureDetector(
          onTap: () =>
              _openCreateAlertWithConfig(config, condition: _stCondition),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFF0A84FF).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 18,
                  color: Color(0xFF4DA3FF),
                ),
                const SizedBox(width: 8),
                Text(
                  'Create alert from Supertrend',
                  style: AppTheme.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4DA3FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── CUSTOM ICON PAINTERS (Matching exact SVGs from Indicators.dc.html) ───────

class _SineWavePainter extends CustomPainter {
  final Color color;
  _SineWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.125, size.height * 0.625)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.625,
        size.width * 0.25,
        size.height * 0.29,
        size.width * 0.5,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.625,
        size.height * 0.29,
        size.width * 0.625,
        size.height * 0.71,
        size.width * 0.75,
        size.height * 0.71,
      )
      ..cubicTo(
        size.width * 0.875,
        size.height * 0.71,
        size.width * 0.875,
        size.height * 0.46,
        size.width * 1.0,
        size.height * 0.46,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SineWavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HistogramIconPainter extends CustomPainter {
  final Color color;
  _HistogramIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.17, size.height * 0.75),
      Offset(size.width * 0.17, size.height * 0.33),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 0.75),
      Offset(size.width * 0.38, size.height * 0.50),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.75),
      Offset(size.width * 0.58, size.height * 0.25),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.79, size.height * 0.75),
      Offset(size.width * 0.79, size.height * 0.38),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HistogramIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MaCurveIconPainter extends CustomPainter {
  final Color color;
  _MaCurveIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.67)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.67,
        size.width * 0.38,
        size.height * 0.29,
        size.width * 0.55,
        size.height * 0.29,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.29,
        size.width * 0.75,
        size.height * 0.62,
        size.width * 0.90,
        size.height * 0.62,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaCurveIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BandsIconPainter extends CustomPainter {
  final Color color;
  _BandsIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pTop = Path()
      ..moveTo(size.width * 0.12, size.height * 0.33)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.33,
        size.width * 0.38,
        size.height * 0.21,
        size.width * 0.55,
        size.height * 0.21,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.21,
        size.width * 0.75,
        size.height * 0.33,
        size.width * 0.88,
        size.height * 0.33,
      );

    final pMid = Path()
      ..moveTo(size.width * 0.12, size.height * 0.50)
      ..lineTo(size.width * 0.88, size.height * 0.50);

    final pBot = Path()
      ..moveTo(size.width * 0.12, size.height * 0.67)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.67,
        size.width * 0.38,
        size.height * 0.79,
        size.width * 0.55,
        size.height * 0.79,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.79,
        size.width * 0.75,
        size.height * 0.67,
        size.width * 0.88,
        size.height * 0.67,
      );

    canvas.drawPath(pTop, paint);
    canvas.drawPath(pMid, paint);
    canvas.drawPath(pBot, paint);
  }

  @override
  bool shouldRepaint(covariant _BandsIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DoubleWaveIconPainter extends CustomPainter {
  final Color color;
  _DoubleWaveIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.38)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.38,
        size.width * 0.25,
        size.height * 0.62,
        size.width * 0.50,
        size.height * 0.62,
      )
      ..cubicTo(
        size.width * 0.62,
        size.height * 0.62,
        size.width * 0.75,
        size.height * 0.25,
        size.width * 0.88,
        size.height * 0.67,
      );

    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.83),
      Offset(size.width * 0.88, size.height * 0.83),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DoubleWaveIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SupertrendIconPainter extends CustomPainter {
  final Color color;
  _SupertrendIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.67)
      ..lineTo(size.width * 0.33, size.height * 0.50)
      ..lineTo(size.width * 0.50, size.height * 0.62)
      ..lineTo(size.width * 0.67, size.height * 0.42)
      ..lineTo(size.width * 0.88, size.height * 0.54);

    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.83),
      Offset(size.width * 0.88, size.height * 0.83),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SupertrendIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
