import 'dart:async';

import 'package:flutter/material.dart';

import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/market_data_api.dart';
import '../services/strategy_storage.dart';
import 'analysis_screen.dart';
import 'create_alert_sheet.dart';
import '../widgets/tenx_toast.dart';

class MarketMoversScreen extends StatefulWidget {
  final ValueChanged<String>? onSelectSymbol;
  final AlertManager? alertManager;

  const MarketMoversScreen({super.key, this.onSelectSymbol, this.alertManager});

  @override
  State<MarketMoversScreen> createState() => _MarketMoversScreenState();
}

class _MarketMoversScreenState extends State<MarketMoversScreen> {
  // Top Segment: Gainers (0), Losers (1), Volatility (2)
  int _selectedSegment = 0;
  final List<String> _segments = ['Gainers', 'Losers', 'Volatility'];

  // Category Filter Chips: All (0), Forex (1), Metals (2), Crypto (3), Indices (4)
  int _selectedCategoryIndex = 0;
  final List<String> _categories = [
    'All',
    'Forex',
    'Metals',
    'Crypto',
    'Indices',
  ];

  bool _loading = true;
  String? _error;

  List<MarketMover> _gainers = [];
  List<MarketMover> _losers = [];
  List<MostActive> _active = [];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _mapCategoryToApi(int index) {
    switch (index) {
      case 1:
        return 'Forex';
      case 2:
        return 'Commodity';
      case 3:
        return 'Crypto';
      case 4:
        return 'Index';
      case 0:
      default:
        return 'Forex';
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final apiType = _mapCategoryToApi(_selectedCategoryIndex);
      final results = await Future.wait([
        MarketDataApi.getGainers(type: apiType, limit: 15),
        MarketDataApi.getLosers(type: apiType, limit: 15),
        MarketDataApi.getMostActive(type: apiType, limit: 15),
      ]);

      if (mounted) {
        setState(() {
          _gainers = results[0] as List<MarketMover>;
          _losers = results[1] as List<MarketMover>;
          _active = results[2] as List<MostActive>;
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

  // Fallback items matching Movers.dc.html if API returns empty
  List<_MoverItem> _getDisplayItems() {
    final bool isGainers = _selectedSegment == 0;
    final bool isLosers = _selectedSegment == 1;

    if (isGainers && _gainers.isNotEmpty) {
      return _gainers.asMap().entries.map((e) {
        final idx = e.key + 1;
        final m = e.value;
        return _MoverItem(
          rank: idx,
          name: m.description.isNotEmpty
              ? m.description
              : _formatSymbolName(m.symbol),
          symbol: m.symbol,
          price: m.lastPrice > 100
              ? m.lastPrice.toStringAsFixed(1)
              : m.lastPrice.toStringAsFixed(5),
          change: '+${m.changePercent.abs().toStringAsFixed(2)}%',
          isPositive: true,
          seed: idx * 4 + 3,
        );
      }).toList();
    } else if (isLosers && _losers.isNotEmpty) {
      return _losers.asMap().entries.map((e) {
        final idx = e.key + 1;
        final m = e.value;
        return _MoverItem(
          rank: idx,
          name: m.description.isNotEmpty
              ? m.description
              : _formatSymbolName(m.symbol),
          symbol: m.symbol,
          price: m.lastPrice > 100
              ? m.lastPrice.toStringAsFixed(1)
              : m.lastPrice.toStringAsFixed(5),
          change: '-${m.changePercent.abs().toStringAsFixed(2)}%',
          isPositive: false,
          seed: idx * 5 + 7,
        );
      }).toList();
    } else if (_active.isNotEmpty && _selectedSegment == 2) {
      return _active.asMap().entries.map((e) {
        final idx = e.key + 1;
        final m = e.value;
        return _MoverItem(
          rank: idx,
          name: m.description.isNotEmpty
              ? m.description
              : _formatSymbolName(m.symbol),
          symbol: m.symbol,
          price: m.high > 100
              ? m.high.toStringAsFixed(1)
              : m.high.toStringAsFixed(5),
          change: '${m.rangePercent.toStringAsFixed(2)}%',
          isPositive: true,
          seed: idx * 3 + 1,
        );
      }).toList();
    }

    return [];
  }

  String _formatSymbolName(String sym) {
    if (sym == 'EURUSD') return 'EUR/USD';
    if (sym == 'GBPUSD') return 'GBP/USD';
    if (sym == 'USDJPY') return 'USD/JPY';
    if (sym == 'XAUUSD') return 'Gold';
    if (sym == 'BTCUSD') return 'Bitcoin';
    if (sym == 'ETHUSD') return 'Ethereum';
    if (sym == 'NAS100') return 'Nasdaq 100';
    if (sym == 'US500') return 'S&P 500';
    return sym;
  }

  _TileBadge _getBadge(String sym) {
    final clean = sym.replaceAll('/', '').toUpperCase();
    if (clean.contains('BTC') || clean == 'BTC') {
      return _TileBadge(
        label: 'BTC',
        bg: const Color(0x2EBF5AF2),
        fg: const Color(0xFFD58CF7),
      );
    }
    if (clean.contains('ETH') || clean == 'ETH') {
      return _TileBadge(
        label: 'ETH',
        bg: const Color(0x2EBF5AF2),
        fg: const Color(0xFFD58CF7),
      );
    }
    if (clean.contains('XAU') || clean.contains('GOLD')) {
      return _TileBadge(
        label: 'XAU',
        bg: const Color(0x2EFF9F0A),
        fg: const Color(0xFFFFB340),
      );
    }
    if (clean.contains('XAG') || clean.contains('SILVER')) {
      return _TileBadge(
        label: 'XAG',
        bg: const Color(0x2EFF9F0A),
        fg: const Color(0xFFFFB340),
      );
    }
    if (clean.contains('NAS') ||
        clean.contains('NDX') ||
        clean.contains('100')) {
      return _TileBadge(
        label: 'NDX',
        bg: const Color(0x2964D2FF),
        fg: const Color(0xFF64D2FF),
      );
    }
    if (clean.contains('500') || clean.contains('SPX')) {
      return _TileBadge(
        label: '500',
        bg: const Color(0x2964D2FF),
        fg: const Color(0xFF64D2FF),
      );
    }
    if (clean.startsWith('NZD') || clean.endsWith('NZD')) {
      return _TileBadge(
        label: 'NZ',
        bg: const Color(0x2E0A84FF),
        fg: const Color(0xFF4DA3FF),
      );
    }
    if (clean.startsWith('GBP') || clean.endsWith('GBP')) {
      return _TileBadge(
        label: 'GB',
        bg: const Color(0x2E0A84FF),
        fg: const Color(0xFF4DA3FF),
      );
    }
    if (clean.startsWith('EUR') || clean.endsWith('EUR')) {
      return _TileBadge(
        label: 'EU',
        bg: const Color(0x2E0A84FF),
        fg: const Color(0xFF4DA3FF),
      );
    }
    if (clean.startsWith('USD') || clean.endsWith('USD')) {
      return _TileBadge(
        label: 'US',
        bg: const Color(0x2E0A84FF),
        fg: const Color(0xFF4DA3FF),
      );
    }
    return _TileBadge(
      label: clean.length >= 2 ? clean.substring(0, 2) : clean,
      bg: const Color(0x2E0A84FF),
      fg: const Color(0xFF4DA3FF),
    );
  }

  void _showMoverModal(_MoverItem item) {
    final double? parsedPrice = double.tryParse(item.price.replaceAll(' ', ''));

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
                        item.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.symbol,
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
                      color: item.isPositive
                          ? const Color(0x2930D158)
                          : const Color(0x29FF453A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.change,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: item.isPositive
                            ? const Color(0xFF43E06A)
                            : const Color(0xFFFF6961),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Current: ${item.price}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (widget.onSelectSymbol != null) {
                          widget.onSelectSymbol!(item.symbol);
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
                          _openCreateAlert(item.symbol, parsedPrice ?? 1.0);
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
                    _runAIStrategy(item.symbol);
                  },
                  icon: const Icon(
                    Icons.psychology_rounded,
                    color: Color(0xFFD58CF7),
                    size: 18,
                  ),
                  label: const Text(
                    'RUN AI STRATEGY ON ASSET',
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
    final canPop = Navigator.of(context).canPop();
    final items = _getDisplayItems();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 6),
            // Header: Title "Movers" + "24h"
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
                          'Movers',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.03 * 34,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 64),
                      child: Text(
                        '24h',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0x9EEBEBF5),
                        ),
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
            if (_error != null && _gainers.isEmpty && _losers.isEmpty)
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

            // Top Segment: Gainers | Losers | Volatility
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
                  children: List.generate(_segments.length, (idx) {
                    final isSelected = _selectedSegment == idx;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSegment = idx;
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
                              _segments[idx],
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

            // Category Filter Chips: All | Forex | Metals | Crypto | Indices
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, idx) {
                    final isSelected = _selectedCategoryIndex == idx;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategoryIndex = idx;
                        });
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: Text(
                            _categories[idx],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.black
                                  : const Color(0x9EEBEBF5),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                children: [
                  // VOLATILITY BREAKOUT HERO CARD
                  Builder(
                    builder: (context) {
                      final topActive = _active.isNotEmpty
                          ? _active.first
                          : null;
                      final topGainer = _gainers.isNotEmpty
                          ? _gainers.first
                          : null;
                      final symbol =
                          topActive?.symbol ?? topGainer?.symbol ?? 'XAUUSD';
                      final title = topActive != null
                          ? '${_formatSymbolName(topActive.symbol)} · ${topActive.rangePercent.toStringAsFixed(1)}% Daily Range'
                          : (topGainer != null
                                ? '${_formatSymbolName(topGainer.symbol)} · +${topGainer.changePercent.abs().toStringAsFixed(2)}%'
                                : 'XAU/USD · Market Activity');

                      return GestureDetector(
                        onTap: () {
                          if (widget.onSelectSymbol != null) {
                            widget.onSelectSymbol!(symbol);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0x33FF9F0A), Color(0xFF1C1C1E)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x40FF9F0A)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0x33FF9F0A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.show_chart_rounded,
                                    color: Color(0xFFFFB340),
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'VOLATILITY BREAKOUT',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.99,
                                        color: Color(0xFFFFB340),
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0x57EBEBF5),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // MOVERS LIST CONTAINER
                  if (items.isEmpty && !_loading)
                    Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 20,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        'No ${_segments[_selectedSegment].toLowerCase()} found for ${_categories[_selectedCategoryIndex]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0x9EEBEBF5),
                        ),
                      ),
                    )
                  else if (items.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: List.generate(items.length, (idx) {
                          final item = items[idx];
                          final badge = _getBadge(item.symbol);
                          final isLast = idx == items.length - 1;

                          return InkWell(
                            onTap: () => _showMoverModal(item),
                            child: Container(
                              height: 62,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                border: isLast
                                    ? null
                                    : const Border(
                                        bottom: BorderSide(
                                          color: Color(0x17FFFFFF),
                                          width: 1,
                                        ),
                                      ),
                              ),
                              child: Row(
                                children: [
                                  // Rank number
                                  SizedBox(
                                    width: 18,
                                    child: Text(
                                      '${item.rank}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x57EBEBF5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Colored icon tile with prefix
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: badge.bg,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        badge.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: badge.fg,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name and price
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          item.price,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: Color(0x9EEBEBF5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Mini Sparkline
                                  SizedBox(
                                    width: 56,
                                    height: 22,
                                    child: CustomPaint(
                                      painter: _SparklinePainter(
                                        seed: item.seed,
                                        isPositive: item.isPositive,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  // Percentage Change Pill
                                  Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 68,
                                    ),
                                    height: 30,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: item.isPositive
                                          ? const Color(0x2930D158)
                                          : const Color(0x29FF453A),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Center(
                                      child: Text(
                                        item.change,
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: item.isPositive
                                              ? const Color(0xFF43E06A)
                                              : const Color(0xFFFF6961),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
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

class _MoverItem {
  final int rank;
  final String name;
  final String symbol;
  final String price;
  final String change;
  final bool isPositive;
  final int seed;

  _MoverItem({
    required this.rank,
    required this.name,
    required this.symbol,
    required this.price,
    required this.change,
    required this.isPositive,
    required this.seed,
  });
}

class _TileBadge {
  final String label;
  final Color bg;
  final Color fg;

  _TileBadge({required this.label, required this.bg, required this.fg});
}

class _SparklinePainter extends CustomPainter {
  final int seed;
  final bool isPositive;

  _SparklinePainter({required this.seed, required this.isPositive});

  @override
  void paint(Canvas canvas, Size size) {
    int s = seed;
    double random() {
      s = (s * 16807) % 2147483647;
      return s / 2147483647;
    }

    double v = 11.0;
    final List<double> pts = [];
    final double bias = isPositive ? 0.38 : 0.62;
    for (int i = 0; i < 14; i++) {
      v += (random() - bias) * 4.0;
      pts.add(v);
    }

    final mn = pts.reduce((a, b) => a < b ? a : b);
    final mx = pts.reduce((a, b) => a > b ? a : b);
    final range = (mx - mn).abs() == 0 ? 1.0 : (mx - mn);

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = 1.0 + (i * (size.width - 2) / 13.0);
      final y =
          size.height - 2.0 - ((pts[i] - mn) / range * (size.height - 4.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = isPositive ? const Color(0xFF30D158) : const Color(0xFFFF453A)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.isPositive != isPositive;
}
