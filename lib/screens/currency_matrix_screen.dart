import 'dart:async';

import 'package:flutter/material.dart';

import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/market_data_api.dart';
import '../services/strategy_storage.dart';
import 'analysis_screen.dart';
import 'create_alert_sheet.dart';
import '../widgets/tenx_toast.dart';

class CurrencyMatrixScreen extends StatefulWidget {
  final ValueChanged<String>? onSelectSymbol;
  final AlertManager? alertManager;

  const CurrencyMatrixScreen({
    super.key,
    this.onSelectSymbol,
    this.alertManager,
  });

  @override
  State<CurrencyMatrixScreen> createState() => _CurrencyMatrixScreenState();
}

class _CurrencyMatrixScreenState extends State<CurrencyMatrixScreen> {
  final List<String> _currencies = [
    'GBP',
    'NZD',
    'EUR',
    'AUD',
    'CAD',
    'USD',
    'CHF',
    'JPY',
  ];

  // Timeframe selection: Today, Week, Month
  int _selectedTimeframeIndex = 0; // 0: Today, 1: Week, 2: Month
  final List<String> _timeframeLabels = ['Today', 'Week', 'Month'];

  bool _loading = true;
  String? _error;
  Map<String, TickData> _ticks = {};
  Timer? _refreshTimer;

  // Relative currency strengths calculated from live ticks
  Map<String, double> _strengths = {
    'GBP': 0.0,
    'NZD': 0.0,
    'EUR': 0.0,
    'AUD': 0.0,
    'CAD': 0.0,
    'USD': 0.0,
    'CHF': 0.0,
    'JPY': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final symbols = [
        'EURUSD',
        'GBPUSD',
        'USDJPY',
        'AUDUSD',
        'USDCAD',
        'USDCHF',
        'NZDUSD',
        'EURGBP',
        'EURJPY',
        'GBPJPY',
        'EURAUD',
        'EURCAD',
        'EURCHF',
        'EURNZD',
        'GBPAUD',
        'GBPCAD',
        'GBPCHF',
        'GBPNZD',
        'AUDJPY',
        'CADJPY',
        'CHFJPY',
        'NZDJPY',
        'AUDCAD',
        'AUDCHF',
        'AUDNZD',
        'CADCHF',
        'NZDCAD',
        'NZDCHF',
      ];
      final res = await MarketDataApi.getBatchTicks(symbols);
      if (mounted) {
        setState(() {
          _ticks = res;
          _calculateStrengths();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _calculateStrengths() {
    if (_ticks.isEmpty) return;

    // Timeframe multiplier modifier
    final double tfMultiplier = _selectedTimeframeIndex == 0
        ? 1.0
        : (_selectedTimeframeIndex == 1 ? 2.4 : 5.8);

    final scores = <String, double>{};
    for (final cur in _currencies) {
      scores[cur] = 0.0;
    }

    int count = 0;
    for (final tick in _ticks.values) {
      if (tick.symbol.length == 6) {
        final base = tick.symbol.substring(0, 3);
        final quote = tick.symbol.substring(3, 6);
        if (scores.containsKey(base) && scores.containsKey(quote)) {
          final diff = tick.dayDiffPercent;
          scores[base] = (scores[base] ?? 0.0) + (diff * 0.1 * tfMultiplier);
          scores[quote] = (scores[quote] ?? 0.0) - (diff * 0.1 * tfMultiplier);
          count++;
        }
      }
    }

    if (count > 0) {
      _strengths = scores;
    }
  }

  double _getRelativeValue(String a, String b) {
    if (a == b) return 0.0;
    final sa = _strengths[a] ?? 0.0;
    final sb = _strengths[b] ?? 0.0;
    return sa - sb;
  }

  String _resolveSymbol(String base, String quote) {
    final direct = '$base$quote';
    if (_ticks.containsKey(direct)) return direct;
    final inverse = '$quote$base';
    if (_ticks.containsKey(inverse)) return inverse;
    return direct;
  }

  double? _getLiveRate(String base, String quote) {
    if (base == quote) return 1.0;
    final direct = '$base$quote';
    if (_ticks.containsKey(direct) && _ticks[direct]!.mid > 0) {
      return _ticks[direct]!.mid;
    }
    final inverse = '$quote$base';
    if (_ticks.containsKey(inverse) && _ticks[inverse]!.mid > 0) {
      return 1.0 / _ticks[inverse]!.mid;
    }
    return null;
  }

  void _onCellTapped(String base, String quote) {
    if (base == quote) return;
    final symbol = _resolveSymbol(base, quote);
    final rate = _getLiveRate(base, quote);
    final relVal = _getRelativeValue(base, quote);
    final isPos = relVal >= 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$base/$quote',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Resolved Pair: $symbol',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0x9EEBEBF5),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isPos
                          ? const Color(0x2930D158)
                          : const Color(0x29FF453A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${isPos ? "+" : ""}${relVal.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isPos
                            ? const Color(0xFF43E06A)
                            : const Color(0xFFFF6961),
                      ),
                    ),
                  ),
                ],
              ),
              if (rate != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Rate: ${rate.toStringAsFixed(rate > 50 ? 3 : 5)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (widget.onSelectSymbol != null) {
                          widget.onSelectSymbol!(symbol);
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.show_chart_rounded, size: 18),
                      label: const Text('VIEW CHART'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  if (widget.alertManager != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openCreateAlert(symbol, rate ?? 1.0);
                        },
                        icon: const Icon(Icons.add_alert_rounded, size: 18),
                        label: const Text('SET ALERT'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0A84FF),
                          side: const BorderSide(color: Color(0xFF0A84FF)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _runAIStrategy(symbol);
                  },
                  icon: const Icon(
                    Icons.psychology_rounded,
                    color: Color(0xFFD58CF7),
                    size: 18,
                  ),
                  label: const Text(
                    'RUN AI STRATEGY ON PAIR',
                    style: TextStyle(
                      color: Color(0xFFD58CF7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCreateAlert(String symbol, double price) {
    if (widget.alertManager == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateAlertSheet(
        symbol: symbol,
        currentPrice: price,
        precision: price > 50 ? 2 : 5,
        alarmService: widget.alertManager?.alarmService,
        onAlertCreated:
            ({
              required String symbol,
              AlertType alertType = AlertType.priceLevel,
              double targetPrice = 0.0,
              AlertCondition condition = AlertCondition.crossesAbove,
              CandlestickPattern? candlestickPattern,
              IndicatorAlertConfig? indicatorConfig,
              MultiStepConfig? multiStepConfig,
              String timeframe = '1H',
              String note = '',
              String ringtoneTitle = 'Default',
              String? ringtoneUri,
              String? drawingId,
              List<String>? targetSymbols,
              bool? triggerOnCandleClose,
              int? cooldownMinutes,
            }) {
              widget.alertManager?.addAlert(
                symbol: symbol,
                targetPrice: targetPrice,
                currentPrice: price,
                condition: condition,
                note: note,
              );
            },
      ),
    );
  }

  void _runAIStrategy(String symbol) async {
    final strategies = await StrategyStorage().getStrategies();
    if (!mounted) return;
    if (strategies.isEmpty) {
      TenXToast.show(
        context,
        title: 'No AI Strategies Found',
        subtitle: 'Configure an AI specialist in the Strategies tab to run automated analysis.',
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFFFF9F0A),
        iconBgColor: const Color(0x33FF9F0A),
      );
      return;
    }
    final strategy = strategies.first;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          strategy: strategy,
          initialSymbol: symbol,
          initialTimeframe: '1H',
          onSelectSymbolForChart: widget.onSelectSymbol,
          alertManager: widget.alertManager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Find strongest and weakest currencies
    String strongest = 'GBP';
    String weakest = 'JPY';
    double maxStrength = -999.0;
    double minStrength = 999.0;

    for (final c in _currencies) {
      final s = _strengths[c] ?? 0.0;
      if (s > maxStrength) {
        maxStrength = s;
        strongest = c;
      }
      if (s < minStrength) {
        minStrength = s;
        weakest = c;
      }
    }

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 6),
            // Header: Title "Matrix" + "• 28 pairs live"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (canPop) ...[
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        const Text(
                          'Matrix',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.03 * 34,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 64),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF30D158),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '28 pairs live',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF43E06A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
              ),
            if (_error != null && _ticks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Text(
                  'Live data status: $_error',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0x57EBEBF5),
                  ),
                ),
              ),

            // Timeframe Segmented Control: Today | Week | Month
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                height: 36,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: List.generate(_timeframeLabels.length, (idx) {
                    final isSelected = _selectedTimeframeIndex == idx;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTimeframeIndex = idx;
                            _calculateStrengths();
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF3A3A3C)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              _timeframeLabels[idx],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0x9EEBEBF5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  // CARD 1: STRENGTH RANKING
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'STRENGTH RANKING',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.99,
                            color: Color(0x9EEBEBF5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 88,
                          child: LayoutBuilder(
                            builder: (ctx, constraints) {
                              final colWidth =
                                  (constraints.maxWidth) / _currencies.length;
                              final maxAbs = [
                                maxStrength.abs(),
                                minStrength.abs(),
                                0.42,
                              ].reduce((a, b) => a > b ? a : b);

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: _currencies.map((cur) {
                                  final val = _strengths[cur] ?? 0.0;
                                  final h = (val.abs() / maxAbs * 32.0).clamp(
                                    4.0,
                                    32.0,
                                  );
                                  final top = val >= 0 ? 36.0 - h : 36.0;
                                  final color = val >= 0
                                      ? const Color(0xFF30D158)
                                      : const Color(0xFFFF453A);

                                  return SizedBox(
                                    width: colWidth,
                                    child: Stack(
                                      alignment: Alignment.topCenter,
                                      children: [
                                        // Baseline line at 36px
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 36,
                                          child: Container(
                                            height: 1,
                                            color: const Color(0x17FFFFFF),
                                          ),
                                        ),
                                        // Colored vertical rounded bar
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          top: top,
                                          height: h,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                        ),
                                        // Currency label at bottom
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Text(
                                            cur,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                              color: Color(0x9EEBEBF5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // CARD 2: 8x8 HEATMAP MATRIX
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      children: [
                        // Column Headers Row
                        Row(
                          children: [
                            const SizedBox(width: 34), // Row label offset
                            ..._currencies.map((cur) {
                              return Expanded(
                                child: Center(
                                  child: Text(
                                    cur,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: Color(0x9EEBEBF5),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Matrix Rows
                        ..._currencies.map((rowCur) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(
                              children: [
                                // Row header
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    rowCur,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: Color(0x9EEBEBF5),
                                    ),
                                  ),
                                ),
                                // Cells
                                ..._currencies.map((colCur) {
                                  final isDiag = rowCur == colCur;
                                  final val = _getRelativeValue(rowCur, colCur);
                                  final isPos = val >= 0;
                                  final alpha = (0.14 + val.abs() * 1.3).clamp(
                                    0.14,
                                    0.85,
                                  );

                                  final bg = isDiag
                                      ? const Color(0x0AFFFFFF)
                                      : (isPos
                                            ? const Color(0xFF30D158)
                                                  .withValues(alpha: alpha)
                                            : const Color(0xFFFF453A)
                                                  .withValues(alpha: alpha));
                                  final fg = isDiag
                                      ? const Color(0x4DEBEBF5)
                                      : Colors.white;

                                  final text = isDiag
                                      ? '–'
                                      : '${isPos ? "+" : "−"}${val.abs().toStringAsFixed(2)}';

                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: isDiag
                                          ? null
                                          : () => _onCellTapped(rowCur, colCur),
                                      child: Container(
                                        height: 34,
                                        margin: const EdgeInsets.all(1),
                                        decoration: BoxDecoration(
                                          color: bg,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: isDiag ? 12 : 9.5,
                                              fontWeight: isDiag
                                                  ? FontWeight.w400
                                                  : FontWeight.w600,
                                              color: fg,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // CARD 3: DIVERGENCE HERO CARD
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1F0A84FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DIVERGENCE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.99,
                                  color: Color(0xFF7CBCFF),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$strongest strongest · $weakest weakest',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            final sym = _resolveSymbol(strongest, weakest);
                            if (widget.onSelectSymbol != null) {
                              widget.onSelectSymbol!(sym);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A84FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 0,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text(
                            '$strongest/$weakest',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
