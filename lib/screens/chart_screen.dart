import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../models/drawing_models.dart';
import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/biquote_widget_service.dart';
import '../services/indicator_service.dart';
import '../theme/app_theme.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/indicator_catalog_sheet.dart';
import 'alerts_list_sheet.dart';
import 'create_alert_sheet.dart';
import 'fullscreen_chart_screen.dart';
import 'instrument_search_sheet.dart';
import '../services/favorites_service.dart';
import '../models/ai_models.dart';
import '../services/settings_provider.dart';
import '../services/strategy_storage.dart';
import '../services/realmarket_service.dart';
import 'strategies_screen.dart';

class ChartScreen extends StatefulWidget {
  final BiquoteService biquoteService;
  final AlertManager alertManager;
  final VoidCallback onToggleTheme;
  final bool isDark;

  const ChartScreen({
    super.key,
    required this.biquoteService,
    required this.alertManager,
    required this.onToggleTheme,
    required this.isDark,
  });

  @override
  State<ChartScreen> createState() => ChartScreenState();
}

class ChartScreenState extends State<ChartScreen> {
  final FavoritesService _favService = FavoritesService();
  final StrategyStorage _storage = StrategyStorage();
  List<String> get _symbols => _favService.favorites;
  String _selectedSymbol = 'EURUSD';
  String get selectedSymbol => _selectedSymbol;
  double get selectedCurrentPrice =>
      _ticks[_selectedSymbol]?.mid ??
      (_candles.isNotEmpty ? _candles.last.close : null) ??
      widget.biquoteService.livePriceFor(_selectedSymbol) ??
      0;
  int get selectedPrecision => _ticks[_selectedSymbol]?.precision ?? 5;

  void selectSymbol(String symbol, {AgentSignal? signalOverlay}) {
    if (_selectedSymbol != symbol) {
      setState(() {
        _selectedSymbol = symbol;
        if (signalOverlay != null) {
          _activeSignalOverlay = signalOverlay;
        }
      });
      _syncSubscriptions();
      _loadCandles();
    } else if (signalOverlay != null) {
      setState(() {
        _activeSignalOverlay = signalOverlay;
      });
    }
  }

  String _selectedTimeframe = '1H';
  String _lastDefaultChartTimeframe = '';

  // Ticker ribbon auto-scroll
  final ScrollController _tickerScrollController = ScrollController();
  Timer? _tickerScrollTimer;

  Map<String, BiquoteTick> _ticks = {};
  List<BiquoteCandle> _candles = [];
  bool _isLoadingCandles = false;
  String _chartDataSource = 'live';
  StreamSubscription<BiquoteTick>? _tickSubscription;
  Timer? _slowSyncTimer;
  bool _isDndGranted = false;
  bool _isLoadingHistory = false;
  bool _hasReachedHistoryEnd = false;
  AgentSignal? _activeSignalOverlay;
  bool _isCrosshairActive = false;
  Key _chartKey = UniqueKey();

  Future<void> _openIndicatorsSheet() async {
    final activeIndicators = await IndicatorService().loadActiveIndicators();
    if (!mounted) return;
    IndicatorCatalogSheet.show(
      context,
      activeIndicators: activeIndicators,
      symbol: _selectedSymbol,
      currentPrice:
          _ticks[_selectedSymbol]?.mid ??
          (_candles.isNotEmpty ? _candles.last.close : 1.0850),
      precision: _ticks[_selectedSymbol]?.precision ?? 5,
      onIndicatorsChanged: (updated) async {
        await IndicatorService().saveActiveIndicators(updated);
        if (mounted) {
          setState(() {
            _chartKey = UniqueKey();
          });
        }
      },
    );
  }

  List<_RibbonItem> _getTickerRibbonItems() {
    final defaults = [
      _RibbonItem(symbol: 'GBPUSD', priceStr: '1.30512', isBullish: true),
      _RibbonItem(symbol: 'XAUUSD', priceStr: '2650.4', isBullish: false),
      _RibbonItem(symbol: 'BTCUSD', priceStr: '67240', isBullish: true),
      _RibbonItem(symbol: 'USDJPY', priceStr: '155.30', isBullish: true),
    ];

    if (_ticks.isEmpty) return defaults;

    final symbols = <String>{
      'GBPUSD',
      'XAUUSD',
      'BTCUSD',
      'USDJPY',
      ..._symbols,
    };
    final items = <_RibbonItem>[];
    for (final sym in symbols) {
      final tick = _ticks[sym];
      if (tick != null && tick.mid > 0) {
        items.add(
          _RibbonItem(
            symbol: sym,
            priceStr: tick.mid.toStringAsFixed(
              tick.precision == 3
                  ? 2
                  : (tick.precision == 2
                        ? 1
                        : (tick.precision > 4 ? 4 : tick.precision)),
            ),
            isBullish: tick.isBullish,
          ),
        );
      }
    }
    return items.isNotEmpty ? items : defaults;
  }

  /// Returns a list of tap-able ticker widgets for use in the auto-scrolling ribbon.
  List<Widget> _buildTickerItems() {
    return _getTickerRibbonItems().map((item) {
      return GestureDetector(
        onTap: () => _onSelectSymbol(item.symbol),
        child: Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.symbol,
                style: AppTheme.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                item.priceStr,
                style: AppTheme.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: item.isBullish
                      ? const Color(0xFF43E06A)
                      : const Color(0xFFFF453A),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final provider = SettingsProvider();
    _lastDefaultChartTimeframe = provider.defaultChartTimeframe;
    final tf = _lastDefaultChartTimeframe.toUpperCase();
    if (['1M', '5M', '15M', '30M', '1H', '4H', '1D'].contains(tf)) {
      _selectedTimeframe = tf;
    }
    SettingsProvider().addListener(_onSettingsChanged);

    _storage.getLastChartSignal().then((sig) {
      if (mounted && sig != null) {
        setState(() => _activeSignalOverlay = sig);
      }
    });
    _favService.addListener(_onFavoritesChanged);
    _favService.init().then((_) {
      if (mounted) {
        _syncSubscriptions();
        _refreshQuotes();
      }
    });

    _loadInitialData();
    _checkDndStatus();

    // Listen to network connectivity & Biquote server status
    widget.biquoteService.isOnlineNotifier.addListener(_onNetworkStatusChanged);

    // Hook up alarm trigger callback if not already set globally
    widget.alertManager.onAlertTriggered ??= _showAlarmDialog;

    // Listen to alert changes so SignalR WebSocket subscribes to newly added/modified alert symbols
    widget.alertManager.addListener(_onAlertsChanged);

    // Connect to unmetered SignalR WebSocket for instant real-time ticks
    widget.biquoteService.initSignalR(_getMonitoredSymbols());
    _tickSubscription = widget.biquoteService.tickStream.listen(
      _onTickReceived,
    );

    // Infrequent slow sync (every 30s) to keep watchlist daily changes up to date
    _slowSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshQuotes(),
    );

    // Start ticker auto-scroll after frame renders
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _startTickerAutoScroll(),
    );
  }

  void _startTickerAutoScroll() {
    _tickerScrollTimer?.cancel();
    _tickerScrollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted || !_tickerScrollController.hasClients) return;
      final max = _tickerScrollController.position.maxScrollExtent;
      if (max <= 0) return;
      final current = _tickerScrollController.offset;
      const step = 1.0;
      if (current + step >= max) {
        _tickerScrollController.jumpTo(0);
      } else {
        _tickerScrollController.jumpTo(current + step);
      }
    });
  }

  List<String> _getMonitoredSymbols() {
    final activeAlertSymbols = widget.alertManager.activeAlerts.map(
      (a) => a.symbol,
    );
    final set = <String>{
      ..._favService.favorites,
      _selectedSymbol,
      ...activeAlertSymbols,
    };
    return set.toList();
  }

  void _syncSubscriptions() {
    widget.biquoteService.subscribe(_getMonitoredSymbols());
  }

  void _onAlertsChanged() {
    if (!mounted) return;
    _syncSubscriptions();
  }

  void _onFavoritesChanged() {
    if (!mounted) return;
    setState(() {});
    _syncSubscriptions();
    _refreshQuotes();
  }

  void _onNetworkStatusChanged() {
    if (mounted) setState(() {});
  }

  void _onTickReceived(BiquoteTick tick) {
    if (!mounted) return;
    setState(() {
      _ticks[tick.symbol] = tick;
      if (tick.symbol == _selectedSymbol) {
        _updateRealtimeCandle(tick.mid, timestamp: tick.timestamp);
      }
      widget.alertManager.checkTick(tick);
    });
  }

  @override
  void dispose() {
    SettingsProvider().removeListener(_onSettingsChanged);
    widget.alertManager.removeListener(_onAlertsChanged);
    _favService.removeListener(_onFavoritesChanged);
    widget.biquoteService.isOnlineNotifier.removeListener(
      _onNetworkStatusChanged,
    );
    _tickSubscription?.cancel();
    _slowSyncTimer?.cancel();
    _tickerScrollTimer?.cancel();
    _tickerScrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final savedDefault = SettingsProvider().defaultChartTimeframe;
    final defaultChanged = savedDefault != _lastDefaultChartTimeframe;
    _lastDefaultChartTimeframe = savedDefault;
    final preferred = defaultChanged ? _normalizeTimeframe(savedDefault) : null;
    if (preferred != null && preferred != _selectedTimeframe) {
      _onSelectTimeframe(preferred);
      return;
    }
    setState(() {});
  }

  String? _normalizeTimeframe(String timeframe) {
    switch (timeframe.trim().toLowerCase()) {
      case '1m':
        return '1m';
      case '5m':
        return '5m';
      case '15m':
        return '15m';
      case '30m':
        return '30m';
      case '1h':
        return '1H';
      case '4h':
        return '4H';
      case '1d':
        return '1D';
      default:
        return null;
    }
  }

  Future<void> _checkDndStatus() async {
    final granted = await widget.alertManager.alarmService
        .isDndOverrideGranted();
    if (mounted) setState(() => _isDndGranted = granted);
  }

  Future<void> _loadInitialData() async {
    await _refreshQuotes();
    await _loadCandles();
  }

  int _getTimeframeSeconds(String tf) {
    switch (tf.toLowerCase()) {
      case '1m':
        return 60;
      case '5m':
        return 300;
      case '15m':
        return 900;
      case '30m':
        return 1800;
      case '1h':
        return 3600;
      case '4h':
        return 14400;
      case '1d':
        return 86400;
      default:
        return 3600;
    }
  }

  String _getIntervalCode(String tf) {
    switch (tf.toLowerCase()) {
      case '1m':
        return '1m';
      case '5m':
        return '5m';
      case '15m':
        return '15m';
      case '30m':
        return '30m';
      case '1h':
        return '1h';
      case '4h':
        return '4h';
      case '1d':
        return '1d';
      default:
        return '1h';
    }
  }

  void _updateRealtimeCandle(double newPrice, {DateTime? timestamp}) {
    if (_candles.isEmpty) return;

    final intervalSeconds = _getTimeframeSeconds(_selectedTimeframe);
    final last = _candles.last;
    final now = (timestamp ?? DateTime.now()).toUtc();
    final bucketMillis = intervalSeconds * 1000;
    final bucketStart = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ bucketMillis * bucketMillis,
      isUtc: true,
    );
    if (bucketStart.isBefore(last.openTime)) return;

    final interval = _getIntervalCode(_selectedTimeframe);
    if (bucketStart.isAfter(last.openTime)) {
      // Period completed: close last candle and append new forming candle
      _candles[_candles.length - 1] = last.copyWith(isOpen: false);
      _candles.add(
        BiquoteCandle(
          openTime: bucketStart,
          open: newPrice,
          high: newPrice,
          low: newPrice,
          close: newPrice,
          tickVolume: 1,
          isOpen: true,
        ),
      );
      if (_candles.length > 500) {
        _candles.removeAt(0);
      }
      widget.alertManager.evaluateCandles(
        _selectedSymbol,
        interval,
        _candles,
        isIntraCandle: false,
      );
    } else {
      // Real-time update of current forming candle's wick and body
      _candles[_candles.length - 1] = last.updateWithTick(newPrice);
      // Intra-candle evaluation for indicators and multi-step logic chains
      widget.alertManager.evaluateCandles(
        _selectedSymbol,
        interval,
        _candles,
        isIntraCandle: true,
      );
    }
  }

  Future<void> _refreshQuotes() async {
    final quotes = await widget.biquoteService.getLatestQuotes(
      _getMonitoredSymbols(),
    );
    if (mounted) {
      setState(() {
        _ticks = quotes;
        // Evaluate price alerts across all actively monitored symbols
        for (final tick in quotes.values) {
          widget.alertManager.evaluatePrice(tick.symbol, tick.mid);
        }
        final currentTick = quotes[_selectedSymbol];
        if (currentTick != null) {
          _updateRealtimeCandle(
            currentTick.mid,
            timestamp: currentTick.timestamp,
          );
        }
      });
    }
    _evaluateNonActiveSymbolCandles();
  }

  Future<void> _evaluateNonActiveSymbolCandles() async {
    final nonActiveCandleAlerts = widget.alertManager.activeAlerts.where(
      (a) =>
          a.symbol != _selectedSymbol &&
          (a.isPatternAlert || a.isIndicatorAlert || a.isMultiStepAlert),
    );
    if (nonActiveCandleAlerts.isEmpty) return;

    final nonActiveSymbolsWithTf = <String, Set<String>>{};
    for (final a in nonActiveCandleAlerts) {
      nonActiveSymbolsWithTf
          .putIfAbsent(a.symbol, () => <String>{})
          .add(a.timeframe);
      if (a.isMultiStepAlert && a.multiStepConfig?.activeStage != null) {
        for (final node in a.multiStepConfig!.activeStage!.nodes) {
          if (!node.isSatisfied &&
              (node.nodeType == AlertType.candlestickPattern ||
                  node.nodeType == AlertType.technicalIndicator)) {
            nonActiveSymbolsWithTf
                .putIfAbsent(a.symbol, () => <String>{})
                .add(node.timeframe);
          }
        }
      }
    }

    for (final entry in nonActiveSymbolsWithTf.entries) {
      final sym = entry.key;
      for (final tf in entry.value) {
        try {
          final candles = await widget.biquoteService.getCandles(
            sym,
            interval: tf,
            limit: 30,
          );
          if (candles.isNotEmpty && mounted) {
            widget.alertManager.evaluateCandles(
              sym,
              tf,
              candles,
              isIntraCandle: false,
            );
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _loadCandles() async {
    _hasReachedHistoryEnd = false;
    setState(() => _isLoadingCandles = true);
    final interval = _getIntervalCode(_selectedTimeframe);
    final cacheKey = RealMarketService.getCacheKey(_selectedSymbol, interval);
    final symbol = _selectedSymbol;

    // Restore persisted pages first, so opening the chart does not discard the
    // older history the user loaded during a previous session.
    var candles =
        await RealMarketService.loadFromCache(cacheKey) ?? <BiquoteCandle>[];
    if (mounted &&
        symbol == _selectedSymbol &&
        interval == _getIntervalCode(_selectedTimeframe) &&
        candles.isNotEmpty) {
      setState(() {
        _candles = candles;
        _chartDataSource = 'cached';
        _isLoadingCandles = false;
      });
    }

    String source = candles.isEmpty ? 'live' : 'cached';
    try {
      final latestCandles = await widget.biquoteService
          .getAvailableCandleHistory(symbol, interval: interval)
          .timeout(const Duration(seconds: 30));
      if (latestCandles.isNotEmpty) {
        candles = _mergeCandles(candles, latestCandles);
        await RealMarketService.updateCache(cacheKey, candles);
        source = 'live';
      }
    } catch (_) {}

    if (candles.isEmpty) source = 'offline';

    if (mounted &&
        symbol == _selectedSymbol &&
        interval == _getIntervalCode(_selectedTimeframe)) {
      setState(() {
        _candles = candles;
        _chartDataSource = source;
        _isLoadingCandles = false;
        final currentTick = _ticks[_selectedSymbol];
        if (currentTick != null && source == 'live') {
          _updateRealtimeCandle(
            currentTick.mid,
            timestamp: currentTick.timestamp,
          );
        }
      });
      if (candles.isNotEmpty) {
        widget.alertManager.evaluateCandles(_selectedSymbol, interval, candles);
      }
    }
  }

  Future<void> _loadMoreHistoryCandles() async {
    if (_isLoadingHistory || _hasReachedHistoryEnd || _candles.isEmpty) return;
    setState(() => _isLoadingHistory = true);

    final interval = _getIntervalCode(_selectedTimeframe);
    final symbol = _selectedSymbol;
    final oldestCandle = _candles.first;
    final oldestTime = oldestCandle.openTime;

    try {
      // Ask for bars strictly before the current oldest timestamp.
      final olderBars = await widget.biquoteService.getCandles(
        symbol,
        interval: interval,
        limit: BiquoteService.maxBarsPerRequest,
        to: oldestTime.subtract(const Duration(seconds: 1)),
      );
      if (!mounted ||
          symbol != _selectedSymbol ||
          interval != _getIntervalCode(_selectedTimeframe)) {
        if (mounted) setState(() => _isLoadingHistory = false);
        return;
      }

      final previousLength = _candles.length;
      final merged = _mergeCandles(_candles, olderBars);
      final foundOlderCandles = olderBars.any(
        (candle) => candle.openTime.isBefore(oldestTime),
      );
      setState(() {
        _candles = merged;
        _isLoadingHistory = false;
        // A page can overlap candles already held in cache. Only an empty page
        // (or one with no timestamp before our cursor) means the feed has ended.
        if (olderBars.isEmpty || !foundOlderCandles) {
          _hasReachedHistoryEnd = true;
        }
      });
      if (merged.length != previousLength) {
        await RealMarketService.updateCache(
          RealMarketService.getCacheKey(symbol, interval),
          merged,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  List<BiquoteCandle> _mergeCandles(
    Iterable<BiquoteCandle> existing,
    Iterable<BiquoteCandle> incoming,
  ) {
    final byTime = <int, BiquoteCandle>{};
    for (final candle in existing) {
      byTime[candle.openTime.millisecondsSinceEpoch] = candle;
    }
    for (final candle in incoming) {
      byTime[candle.openTime.millisecondsSinceEpoch] = candle;
    }
    final merged = byTime.values.toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));
    return merged;
  }

  void _openFullscreenChart() {
    final currentTick = _ticks[_selectedSymbol];
    final currentPrice =
        currentTick?.mid ??
        widget.biquoteService.livePriceFor(_selectedSymbol) ??
        (_candles.isNotEmpty ? _candles.last.close : 0);
    final precision = currentTick?.precision ?? 5;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenChartScreen(
          symbol: _selectedSymbol,
          candles: _candles,
          currentPrice: currentPrice,
          precision: precision,
          interval: _selectedTimeframe,
          alertManager: widget.alertManager,
          biquoteService: widget.biquoteService,
          isDark: widget.isDark,
          onSelectTimeframe: _onSelectTimeframe,
          onLoadMoreHistory: _loadMoreHistoryCandles,
          isLoadingMoreHistory: _isLoadingHistory,
          signalOverlay: _activeSignalOverlay,
        ),
      ),
    );
  }

  void _onSelectSymbol(String symbol) {
    if (_selectedSymbol != symbol) {
      setState(() {
        _selectedSymbol = symbol;
      });
      _syncSubscriptions();
      _loadCandles();
    }
  }

  void _openInstrumentPicker() {
    InstrumentSearchSheet.show(
      context,
      currentSymbol: _selectedSymbol,
      ticks: _ticks,
      onSelectSymbol: (symbol) {
        _onSelectSymbol(symbol);
      },
    );
  }

  void _onSelectTimeframe(String tf) {
    final normalized = _normalizeTimeframe(tf);
    if (normalized != null && _selectedTimeframe != normalized) {
      setState(() {
        _selectedTimeframe = normalized;
      });
      _loadCandles();
    }
  }

  void _openCreateAlertSheet({double? targetPrice, ChartDrawing? fromDrawing}) {
    final currentTick = _ticks[_selectedSymbol];
    final currentPrice =
        currentTick?.mid ??
        widget.biquoteService.livePriceFor(_selectedSymbol) ??
        (_candles.isNotEmpty ? _candles.last.close : 0);
    final precision = currentTick?.precision ?? 5;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateAlertSheet(
        symbol: _selectedSymbol,
        currentPrice: currentPrice,
        biquoteService: widget.biquoteService,
        initialTargetPrice: targetPrice,
        drawingId: fromDrawing?.id,
        precision: precision,
        alarmService: widget.alertManager.alarmService,
        onAlertCreated:
            ({
              required String symbol,
              AlertType alertType = AlertType.priceLevel,
              double targetPrice = 0.0,
              AlertCondition condition = AlertCondition.crossesAbove,
              CandlestickPattern? candlestickPattern,
              IndicatorAlertConfig? indicatorConfig,
              MultiStepConfig? multiStepConfig,
              String timeframe = '15m',
              String note = '',
              String ringtoneTitle = 'Default Alarm',
              String? ringtoneUri,
              String? drawingId,
              List<String>? targetSymbols,
              bool? triggerOnCandleClose,
              int? cooldownMinutes,
            }) async {
              var resolvedCurrentPrice =
                  widget.biquoteService.livePriceFor(symbol) ?? currentPrice;
              var symbolPrices = _ticks.map((k, v) => MapEntry(k, v.mid));
              try {
                if (targetSymbols != null && targetSymbols.length > 1) {
                  final quotes = await widget.biquoteService.getLatestQuotes(
                    targetSymbols,
                  );
                  symbolPrices = quotes.map(
                    (key, value) => MapEntry(key, value.mid),
                  );
                  resolvedCurrentPrice =
                      symbolPrices[symbol] ?? resolvedCurrentPrice;
                } else {
                  final quote = await widget.biquoteService.getSingleQuote(
                    symbol,
                  );
                  if (quote != null) resolvedCurrentPrice = quote.mid;
                }
              } catch (_) {}
              if (!mounted) return;
              if (targetSymbols != null && targetSymbols.length > 1) {
                final createdAlerts = widget.alertManager
                    .createMultiSymbolAlerts(
                      symbols: targetSymbols,
                      alertType: alertType,
                      targetPrice: targetPrice,
                      condition: condition,
                      candlestickPattern: candlestickPattern,
                      indicatorConfig: indicatorConfig,
                      multiStepConfig: multiStepConfig,
                      timeframe: timeframe,
                      note: note,
                      currentPrice: resolvedCurrentPrice,
                      symbolPrices: symbolPrices,
                      ringtoneTitle: ringtoneTitle,
                      ringtoneUri: ringtoneUri,
                      drawingId: drawingId,
                      triggerOnCandleClose: triggerOnCandleClose ?? true,
                      cooldownMinutes: cooldownMinutes ?? 0,
                    );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Multi-Currency Strategy deployed to ${createdAlerts.length} pairs (${targetSymbols.join(', ')})',
                    ),
                    backgroundColor: Colors.amber.shade800,
                    duration: const Duration(seconds: 4),
                  ),
                );
              } else {
                final alert = widget.alertManager.addAlert(
                  symbol: symbol,
                  alertType: alertType,
                  targetPrice: targetPrice,
                  condition: condition,
                  candlestickPattern: candlestickPattern,
                  indicatorConfig: indicatorConfig,
                  multiStepConfig: multiStepConfig,
                  timeframe: timeframe,
                  note: note,
                  currentPrice: resolvedCurrentPrice,
                  ringtoneTitle: ringtoneTitle,
                  ringtoneUri: ringtoneUri,
                  drawingId: drawingId,
                  triggerOnCandleClose: triggerOnCandleClose ?? true,
                  cooldownMinutes: cooldownMinutes ?? 0,
                  targetSymbols: targetSymbols,
                );
                if (fromDrawing != null) {
                  fromDrawing.alertId = alert.id;
                  setState(() {});
                }
                final msg = fromDrawing != null
                    ? '🎯 Drawing Alert active at ${targetPrice.toStringAsFixed(precision)} ($ringtoneTitle)'
                    : alertType == AlertType.candlestickPattern
                    ? 'Pattern alarm active for $symbol: ${candlestickPattern?.label} ($timeframe)'
                    : alertType == AlertType.technicalIndicator
                    ? 'Indicator alarm active for $symbol: ${indicatorConfig?.summary} ($timeframe)'
                    : alertType == AlertType.multiStepChain
                    ? 'Multi-Step Logic Chain active for $symbol (${multiStepConfig?.stages.length ?? 0} levels)'
                    : 'Alert active for $symbol at ${targetPrice.toStringAsFixed(precision)} ($ringtoneTitle)';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: widget.isDark
                        ? AppTheme.darkPrimary
                        : AppTheme.lightPrimary,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
      ),
    );
  }

  void _openAlertsManagerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AlertsListSheet(
        alertManager: widget.alertManager,
        latestTicks: _ticks,
        onSelectSymbol: (symbol) {
          _onSelectSymbol(symbol);
        },
      ),
    );
  }

  void showMarketToolsSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CURATED MARKET TOOLS',
                    style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: const Color(0xFF00E5FF),
                    ),
                  ),
                  Text(
                    _chartDataSource == 'live'
                        ? 'Biquote Live Data'
                        : (_chartDataSource == 'cached'
                              ? 'Offline Cache'
                              : 'No Data · Offline'),
                    style: AppTheme.mono(
                      context: context,
                      fontSize: 11,
                      color: _chartDataSource == 'live'
                          ? const Color(0xFF43E06A)
                          : (_chartDataSource == 'cached'
                                ? Colors.amber
                                : Colors.orange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildMarketToolTile(
                icon: Icons.calendar_month_rounded,
                iconColor: const Color(0xFF00E5FF),
                title: 'Economic Calendar',
                subtitle: 'Macroeconomic releases, actual vs. forecast, and correlated currency pairs',
                onTap: () {
                  Navigator.pop(ctx);
                  BiquoteWidgetService.openEconomicCalendar(
                    context,
                    onSelectSymbol: _onSelectSymbol,
                    alertManager: widget.alertManager,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: Icons.local_fire_department_rounded,
                iconColor: Colors.amber,
                title: 'Market Movers',
                subtitle: 'Top gainers, losers, and most active assets across Forex, Crypto, Indices',
                onTap: () {
                  Navigator.pop(ctx);
                  BiquoteWidgetService.openMarketMovers(
                    context,
                    onSelectSymbol: _onSelectSymbol,
                    alertManager: widget.alertManager,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: Icons.grid_4x4_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Currency Matrix',
                subtitle: 'Cross-rate matrix & heat levels across 7 major world reserve currencies',
                onTap: () {
                  Navigator.pop(ctx);
                  BiquoteWidgetService.openCurrencyMatrix(
                    context,
                    onSelectSymbol: _onSelectSymbol,
                    alertManager: widget.alertManager,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: Icons.newspaper_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: 'Financial News',
                subtitle: 'Real-time financial headlines with automated instrument ticker linking',
                onTap: () {
                  Navigator.pop(ctx);
                  BiquoteWidgetService.openFinancialNews(
                    context,
                    onSelectSymbol: _onSelectSymbol,
                    alertManager: widget.alertManager,
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: Icons.psychology_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'AI Multi-Agent Deliberation',
                subtitle:
                    'Run multi-agent consensus pipeline on $_selectedSymbol ($_selectedTimeframe)',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StrategiesScreen(
                        isDark: widget.isDark,
                        activeSymbol: _selectedSymbol,
                        activeTimeframe: _selectedTimeframe,
                        onNavigateToChart: () => Navigator.pop(context),
                        onSelectSymbolForChart: (sym) {
                          Navigator.pop(context);
                          selectSymbol(sym);
                        },
                        onSelectSignalForChart: (sig) {
                          Navigator.pop(context);
                          selectSymbol(
                            sig.symbol ?? _selectedSymbol,
                            signalOverlay: sig,
                          );
                        },
                        biquoteService: widget.biquoteService,
                        alertManager: widget.alertManager,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: Icons.notifications_active_rounded,
                iconColor: const Color(0xFFFFB340),
                title: 'Active Alerts Manager',
                subtitle: 'Inspect and manage armed price alarms across all instruments',
                onTap: () {
                  Navigator.pop(ctx);
                  _openAlertsManagerSheet();
                },
              ),
              const SizedBox(height: 10),
              _buildMarketToolTile(
                icon: _isDndGranted
                    ? Icons.shield_rounded
                    : Icons.do_not_disturb_on_outlined,
                iconColor: _isDndGranted ? Colors.green : Colors.amber,
                title: 'DND Background Override',
                subtitle: _isDndGranted
                    ? 'DND bypass granted. Alarms will ring out loud.'
                    : 'Grant Notification Policy Access so alerts ring loudly in DND mode.',
                onTap: () {
                  Navigator.pop(ctx);
                  _showDndInfoDialog();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarketToolTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _showAlarmDialog(PriceAlert alert, double triggerPrice) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlarmRingingDialog(
        alert: alert,
        triggerPrice: triggerPrice,
        isDark: widget.isDark,
        onDismiss: () {
          widget.alertManager.alarmService.stopAlarm();
        },
        onSnooze: (minutes) {
          widget.alertManager.alarmService.stopAlarm();
          Future.delayed(Duration(minutes: minutes), () {
            widget.alertManager.rearmAlert(alert.id);
          });
        },
        onViewSymbol: (symbol) {
          widget.alertManager.alarmService.stopAlarm();
          selectSymbol(symbol);
        },
      ),
    );
  }

  void _showDndInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark
            ? AppTheme.darkSurface1
            : AppTheme.lightSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _isDndGranted
                  ? Icons.check_circle
                  : Icons.do_not_disturb_on_outlined,
              color: _isDndGranted ? Colors.green : Colors.amber,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              _isDndGranted ? 'DND Override Active' : 'DND Override Setting',
              style: AppTheme.sans(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Text(
          _isDndGranted
              ? 'Your device has granted Do Not Disturb (DND) override permission. Alarms will ring loudly even when the phone is on silent or in DND mode.'
              : 'Grant Notification Policy Access so your alerts can disrupt silent mode, wake up the locked screen, and ring at full alarm volume.',
          style: AppTheme.sans(fontSize: 13),
        ),
        actions: [
          if (!_isDndGranted)
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await widget.alertManager.alarmService.requestDndOverride();
                await _checkDndStatus();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: const Text('Grant DND Override'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastPrice = _candles.isNotEmpty ? _candles.last.close : 0.0;
    final currentTick =
        _ticks[_selectedSymbol] ??
        BiquoteTick.placeholder(symbol: _selectedSymbol, price: lastPrice);

    final isBullish = currentTick.dayDiffPercent >= 0;
    final trendColor = isBullish
        ? const Color(0xFF43E06A)
        : const Color(0xFFFF453A);

    final displayPair = _selectedSymbol.length == 6
        ? '${_selectedSymbol.substring(0, 3)}/${_selectedSymbol.substring(3)}'
        : _selectedSymbol;

    final dayDiff = currentTick.mid * (currentTick.dayDiffPercent / 100);
    final dayDiffSign = currentTick.dayDiffPercent >= 0 ? '+' : '';
    final dayDiffPercentSign = currentTick.dayDiffPercent >= 0 ? '+' : '';

    return PopScope(
      canPop: !_isCrosshairActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isCrosshairActive) {
          setState(() => _isCrosshairActive = false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 1. Dynamic Mode-Aware Top Header (Matching Design Mockup)
              if (!_isCrosshairActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Symbol Pill Button + Accurate Live/Cache Status Badge
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _openInstrumentPicker,
                                child: Container(
                                  height: 30,
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    right: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(
                                      44,
                                      44,
                                      46,
                                      0.66,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.09,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: Color.fromRGBO(
                                            10,
                                            132,
                                            255,
                                            0.25,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          _selectedSymbol
                                              .substring(
                                                0,
                                                min(2, _selectedSymbol.length),
                                              )
                                              .toUpperCase(),
                                          style: AppTheme.sans(
                                            color: const Color(0xFF4DA3FF),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        displayPair,
                                        style: AppTheme.sans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 14,
                                        color: Color.fromRGBO(
                                          235,
                                          235,
                                          245,
                                          0.62,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 24,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _chartDataSource == 'live'
                                      ? const Color(0xFF43E06A)
                                            .withValues(alpha: 0.15)
                                      : (_chartDataSource == 'cached'
                                            ? Colors.amber.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.redAccent.withValues(
                                                alpha: 0.15,
                                              )),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _chartDataSource == 'live'
                                        ? const Color(0xFF43E06A)
                                              .withValues(alpha: 0.4)
                                        : (_chartDataSource == 'cached'
                                              ? Colors.amber.withValues(
                                                  alpha: 0.4,
                                                )
                                              : Colors.redAccent.withValues(
                                                  alpha: 0.4,
                                                )),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: _chartDataSource == 'live'
                                            ? const Color(0xFF43E06A)
                                            : (_chartDataSource == 'cached'
                                                  ? Colors.amber
                                                  : Colors.redAccent),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _chartDataSource == 'live'
                                          ? 'LIVE'
                                          : (_chartDataSource == 'cached'
                                                ? 'OFFLINE CACHE'
                                                : 'OFFLINE'),
                                      style: AppTheme.mono(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: _chartDataSource == 'live'
                                            ? const Color(0xFF43E06A)
                                            : (_chartDataSource == 'cached'
                                                  ? Colors.amber
                                                  : Colors.redAccent),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Big Monospace Price + 24h Change Stats (exact match Chart.dc.html line 46)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                currentTick.mid.toStringAsFixed(
                                  currentTick.precision,
                                ),
                                style: AppTheme.mono(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.5,
                                  height: 1.0,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$dayDiffSign${dayDiff.toStringAsFixed(currentTick.precision == 3 ? 3 : (currentTick.precision == 2 ? 2 : 5))} · $dayDiffPercentSign${currentTick.dayDiffPercent.abs().toStringAsFixed(2)}%',
                                style: AppTheme.mono(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: trendColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                          if (SettingsProvider().showSpreadDisplay &&
                              currentTick.bid > 0 &&
                              currentTick.ask > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                'SPREAD ${(currentTick.spread * (currentTick.precision == 3 ? 100 : (currentTick.precision == 5 ? 10000 : 1))).toStringAsFixed(1)}p',
                                style: AppTheme.mono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF8E8E93),
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Right Header Button: ONLY Glowing Amber Bell matching Chart.dc.html line 54 (.ib)
                      GestureDetector(
                        onTap: _openCreateAlertSheet,
                        onLongPress: _openAlertsManagerSheet,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(44, 44, 46, 0.66),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09),
                              width: 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.notifications_none_rounded,
                            size: 22,
                            color: Color(0xFFFFB340),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Crosshair / Drawing Edit Mode Header (Matching Drawing Mockup)
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            displayPair,
                            style: AppTheme.sans(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            currentTick.mid.toStringAsFixed(
                              currentTick.precision,
                            ),
                            style: AppTheme.mono(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: trendColor,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _selectedTimeframe.toUpperCase(),
                            style: AppTheme.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFD1D5DB),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isCrosshairActive = false);
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
                ),

              // 2. Timeframe Strip & Indicators Row (Only shown in Normal Mode)
              if (!_isCrosshairActive)
                Container(
                  height: 44,
                  padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                [
                                  '1m',
                                  '5m',
                                  '15m',
                                  '30m',
                                  '1H',
                                  '4H',
                                  '1D',
                                ].map((tf) {
                                  final isSelected =
                                      tf.toUpperCase() ==
                                      _selectedTimeframe.toUpperCase();
                                  return GestureDetector(
                                    onTap: () => _onSelectTimeframe(tf),
                                    child: Container(
                                      height: 30,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      margin: const EdgeInsets.only(right: 2),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        tf,
                                        style: AppTheme.sans(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w700,
                                          color: isSelected
                                              ? Colors.black
                                              : const Color(0xFFD1D5DB),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _openIndicatorsSheet,
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomPaint(
                                size: const Size(16, 16),
                                painter: _SineWaveIconPainter(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Indicators',
                                style: AppTheme.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 3. Carbon Copy Interactive Candlestick Chart
              Expanded(
                child: _isLoadingCandles
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0A84FF),
                        ),
                      )
                    : _candles.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off_rounded,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No Market Data for $_selectedSymbol ($_selectedTimeframe)',
                                style: AppTheme.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'No cached candles found. Connect to internet to stream and cache live quotes.',
                                style: AppTheme.sans(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadCandles,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                ),
                                label: const Text('Retry Connection'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0A84FF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : CandlestickChart(
                        key: _chartKey,
                        symbol: _selectedSymbol,
                        candles: _candles,
                        currentPrice: currentTick.mid,
                        dataSource: _chartDataSource,
                        alerts: widget.alertManager.activeAlerts
                            .where((a) => a.symbol == _selectedSymbol)
                            .toList(),
                        precision: currentTick.precision,
                        interval: _selectedTimeframe,
                        onLoadMoreHistory: _loadMoreHistoryCandles,
                        isLoadingMoreHistory: _isLoadingHistory,
                        onToggleFullscreen: _openFullscreenChart,
                        signalOverlay: _activeSignalOverlay,
                        onDismissSignalOverlay: () {
                          setState(() => _activeSignalOverlay = null);
                          _storage.saveLastChartSignal(null);
                        },
                        onAddAlertFromDrawing: (drawing, targetPrice) {
                          _openCreateAlertSheet(
                            targetPrice: targetPrice,
                            fromDrawing: drawing,
                          );
                        },
                        onDrawingPriceUpdated: (drawingId, newPrice) {
                          final updated = widget.alertManager
                              .updateAlertForDrawing(
                                drawingId,
                                newPrice,
                                currentPrice: currentTick.mid,
                              );
                          if (updated) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🎯 Drawing Alert updated to ${newPrice.toStringAsFixed(currentTick.precision)}',
                                ),
                                backgroundColor: const Color(0xFFFF9100),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        onDrawingDeleted: (drawingId) {
                          widget.alertManager.removeAlertForDrawing(drawingId);
                        },
                        isCrosshairActive: _isCrosshairActive,
                        onCrosshairActiveChanged: (val) {
                          setState(() => _isCrosshairActive = val);
                        },
                      ),
              ),

              // 4. Live Rolling Quotes Ticker Ribbon (Auto-scrolling, only shown in Normal Mode)
              if (!_isCrosshairActive)
                Container(
                  height: 32,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(44, 44, 46, 0.50),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.09),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SingleChildScrollView(
                      controller: _tickerScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          // Duplicate items twice for a seamless looping effect
                          ..._buildTickerItems(),
                          const SizedBox(width: 60),
                          ..._buildTickerItems(),
                        ],
                      ),
                    ),
                  ),
                ),

              // Bottom safe buffer so ticker ribbon floats cleanly above the frosted pill navigation bar
              const SizedBox(height: 96),
            ],
          ),
        ),
      ),
    );
  }
}

class _RibbonItem {
  final String symbol;
  final String priceStr;
  final bool isBullish;

  const _RibbonItem({
    required this.symbol,
    required this.priceStr,
    required this.isBullish,
  });
}

class _SineWaveIconPainter extends CustomPainter {
  final Color color;
  _SineWaveIconPainter({required this.color});

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
  bool shouldRepaint(covariant _SineWaveIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class AlarmRingingDialog extends StatefulWidget {
  final PriceAlert alert;
  final double triggerPrice;
  final bool isDark;
  final VoidCallback onDismiss;
  final void Function(int minutes) onSnooze;
  final void Function(String symbol) onViewSymbol;

  const AlarmRingingDialog({
    super.key,
    required this.alert,
    required this.triggerPrice,
    required this.isDark,
    required this.onDismiss,
    required this.onSnooze,
    required this.onViewSymbol,
  });

  @override
  State<AlarmRingingDialog> createState() => _AlarmRingingDialogState();
}

class _AlarmRingingDialogState extends State<AlarmRingingDialog>
    with SingleTickerProviderStateMixin {
  late DateTime _triggerTime;
  Timer? _chronometerTimer;
  Duration _elapsed = Duration.zero;
  late AnimationController _animController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _triggerTime = widget.alert.triggeredAt ?? DateTime.now();
    _elapsed = DateTime.now().difference(_triggerTime);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(
      begin: 0.2,
      end: 0.6,
    ).animate(_animController);

    _chronometerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_triggerTime);
        });
      }
    });
  }

  @override
  void dispose() {
    _chronometerTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  String _formatElapsed() {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (_elapsed.inHours > 0) {
      final h = _elapsed.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBull = widget.alert.condition == AlertCondition.crossesAbove;
    final displayPair = widget.alert.symbol.length == 6
        ? '${widget.alert.symbol.substring(0, 3)}/${widget.alert.symbol.substring(3)}'
        : widget.alert.symbol;
    final h = _triggerTime.hour.toString().padLeft(2, '0');
    final m = _triggerTime.minute.toString().padLeft(2, '0');
    final s = _triggerTime.second.toString().padLeft(2, '0');
    final triggerTimeFormatted = '$h:$m:$s';

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, _) {
        return AlertDialog(
          backgroundColor: widget.isDark
              ? AppTheme.darkSurface1
              : AppTheme.lightSurface1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Colors.redAccent.withValues(
                alpha: _glowAnimation.value + 0.4,
              ),
              width: 2.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 22,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ringing Chronometer & Pulsing Bell Icon
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(
                        alpha: _glowAnimation.value * 0.8,
                      ),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.notifications_active,
                    size: 44,
                    color: Colors.redAccent,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'ALARM RINGING!',
                style: AppTheme.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Live Elapsed Chronometer Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 15,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ringing for: ${_formatElapsed()}',
                      style: AppTheme.mono(
                        context: context,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• Started at $triggerTimeFormatted',
                      style: AppTheme.mono(
                        context: context,
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Symbol & Condition
              Text(
                '$displayPair ${widget.alert.condition.label.toUpperCase()}',
                style: AppTheme.sans(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Target: ${widget.alert.formattedTarget()} • Triggered: ${widget.triggerPrice.toStringAsFixed(5)}',
                style: AppTheme.mono(
                  context: context,
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              // Ringtone info
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (isBull ? AppTheme.darkBullish : AppTheme.darkBearish)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.ring_volume,
                      size: 13,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Tone: ${widget.alert.ringtoneTitle}',
                      style: AppTheme.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.alert.note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '"${widget.alert.note}"',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(fontSize: 12)
                      .copyWith(fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 20),

              // Stop / Dismiss Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onDismiss();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.notifications_off, size: 22),
                  label: const Text(
                    'STOP ALARM / DISMISS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Snooze & View Chart Secondary Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        widget.onSnooze(
                          SettingsProvider().defaultSnoozeMinutes,
                        );
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.snooze, size: 16),
                      label: Text(
                        'Snooze ${SettingsProvider().defaultSnoozeMinutes}m',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        widget.onViewSymbol(widget.alert.symbol);
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(Icons.show_chart, size: 16),
                      label: Text(
                        'View ${widget.alert.symbol}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
