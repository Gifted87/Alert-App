import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../models/drawing_models.dart';
import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/realmarket_service.dart';
import '../theme/app_theme.dart';
import '../widgets/candlestick_chart.dart';
import '../widgets/timeframe_selector.dart';
import 'create_alert_sheet.dart';

class FullscreenChartScreen extends StatefulWidget {
  final String symbol;
  final List<BiquoteCandle> candles;
  final double currentPrice;
  final int precision;
  final String interval;
  final AlertManager alertManager;
  final BiquoteService? biquoteService;
  final bool isDark;
  final ValueChanged<String> onSelectTimeframe;
  final VoidCallback? onLoadMoreHistory;
  final bool isLoadingMoreHistory;
  final AgentSignal? signalOverlay;

  const FullscreenChartScreen({
    super.key,
    required this.symbol,
    required this.candles,
    required this.currentPrice,
    required this.precision,
    required this.interval,
    required this.alertManager,
    this.biquoteService,
    required this.isDark,
    required this.onSelectTimeframe,
    this.onLoadMoreHistory,
    this.isLoadingMoreHistory = false,
    this.signalOverlay,
  });

  @override
  State<FullscreenChartScreen> createState() => _FullscreenChartScreenState();
}

class _FullscreenChartScreenState extends State<FullscreenChartScreen> {
  late String _currentInterval;
  late List<BiquoteCandle> _candles;
  bool _isLoadingCandles = false;
  bool _isLoadingHistory = false;
  bool _hasReachedHistoryEnd = false;

  bool _isCrosshairActive = false;
  String _dataSource = 'live';
  late double _currentPrice;
  StreamSubscription<BiquoteTick>? _tickSubscription;

  @override
  void initState() {
    super.initState();
    _currentInterval = widget.interval;
    _candles = List.from(widget.candles);
    _currentPrice = widget.currentPrice;
    widget.biquoteService?.subscribe([widget.symbol]);
    _tickSubscription = widget.biquoteService?.tickStream.listen(_onTick);
  }

  void _onTick(BiquoteTick tick) {
    if (!mounted || tick.symbol != widget.symbol || tick.mid <= 0) return;
    final intervalSeconds = switch (_currentInterval.toLowerCase()) {
      '1m' => 60,
      '5m' => 300,
      '15m' => 900,
      '30m' => 1800,
      '4h' => 14400,
      '1d' => 86400,
      _ => 3600,
    };
    setState(() {
      _currentPrice = tick.mid;
      if (_candles.isEmpty) return;
      final last = _candles.last;
      final timestamp = tick.timestamp.toUtc();
      final bucketMillis = intervalSeconds * 1000;
      final bucketStart = DateTime.fromMillisecondsSinceEpoch(
        timestamp.millisecondsSinceEpoch ~/ bucketMillis * bucketMillis,
        isUtc: true,
      );
      if (bucketStart.isBefore(last.openTime)) return;
      if (bucketStart.isAfter(last.openTime)) {
        _candles[_candles.length - 1] = last.copyWith(isOpen: false);
        _candles.add(
          BiquoteCandle(
            openTime: bucketStart,
            open: tick.mid,
            high: tick.mid,
            low: tick.mid,
            close: tick.mid,
            tickVolume: 1,
            isOpen: true,
          ),
        );
      } else {
        _candles[_candles.length - 1] = last.updateWithTick(tick.mid);
      }
    });
  }

  @override
  void dispose() {
    _tickSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchCandlesForTimeframe(String tf) async {
    setState(() {
      _currentInterval = tf;
      _isLoadingCandles = true;
      _isLoadingHistory = false;
      _hasReachedHistoryEnd = false;
    });
    widget.onSelectTimeframe(tf);

    final intervalCode = tf.toLowerCase();
    final cacheKey = RealMarketService.getCacheKey(widget.symbol, intervalCode);
    var fetched =
        await RealMarketService.loadFromCache(cacheKey) ?? <BiquoteCandle>[];
    if (!mounted || intervalCode != _currentInterval.toLowerCase()) return;
    var source = fetched.isEmpty ? 'live' : 'cached';
    if (fetched.isNotEmpty) {
      setState(() {
        _candles = fetched;
        _dataSource = 'cached';
      });
    }
    if (widget.biquoteService != null) {
      try {
        final latest = await widget.biquoteService!
            .getAvailableCandleHistory(widget.symbol, interval: intervalCode)
            .timeout(const Duration(seconds: 30));
        if (!mounted || intervalCode != _currentInterval.toLowerCase()) return;
        if (latest.isNotEmpty) {
          fetched = _mergeCandles(fetched, latest);
          await RealMarketService.updateCache(cacheKey, fetched);
          source = 'live';
        }
      } catch (_) {}
    }

    if (fetched.isEmpty) {
      source = 'offline';
    }

    if (mounted) {
      setState(() {
        _candles = fetched;
        _dataSource = source;
        _isLoadingCandles = false;
      });
      if (fetched.isNotEmpty) {
        widget.alertManager.evaluateCandles(
          widget.symbol,
          intervalCode,
          fetched,
        );
      }
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isLoadingHistory ||
        _hasReachedHistoryEnd ||
        _candles.isEmpty ||
        widget.biquoteService == null) {
      return;
    }
    setState(() => _isLoadingHistory = true);
    final interval = _currentInterval.toLowerCase();
    final oldest = _candles.first.openTime;
    try {
      final older = await widget.biquoteService!.getCandles(
        widget.symbol,
        interval: interval,
        limit: BiquoteService.maxBarsPerRequest,
        to: oldest.subtract(const Duration(seconds: 1)),
      );
      if (!mounted || interval != _currentInterval.toLowerCase()) {
        if (mounted) setState(() => _isLoadingHistory = false);
        return;
      }
      final oldLength = _candles.length;
      final merged = _mergeCandles(_candles, older);
      final foundOlderCandles = older.any(
        (candle) => candle.openTime.isBefore(oldest),
      );
      setState(() {
        _candles = merged;
        _isLoadingHistory = false;
        if (older.isEmpty || !foundOlderCandles) {
          _hasReachedHistoryEnd = true;
        }
      });
      if (merged.length != oldLength) {
        await RealMarketService.updateCache(
          RealMarketService.getCacheKey(widget.symbol, interval),
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
    return byTime.values.toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));
  }

  void _openCreateAlertSheet({double? targetPrice, ChartDrawing? fromDrawing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateAlertSheet(
        symbol: widget.symbol,
        currentPrice: _currentPrice,
        biquoteService: widget.biquoteService,
        initialTargetPrice: targetPrice,
        drawingId: fromDrawing?.id,
        precision: widget.precision,
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
            }) {
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
                currentPrice: _currentPrice,
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
            },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final displayPair = widget.symbol.length == 6
        ? '${widget.symbol.substring(0, 3)}/${widget.symbol.substring(3)}'
        : widget.symbol;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isCrosshairActive) {
          setState(() => _isCrosshairActive = false);
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkCanvas : AppTheme.lightCanvas,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar: Symbol, Timeframes, and Exit Fullscreen Button
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.darkSurface1
                      : AppTheme.lightSurface1,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? AppTheme.darkBorder
                          : AppTheme.lightBorder,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      displayPair,
                      style: AppTheme.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isDark
                                    ? AppTheme.darkBullish
                                    : AppTheme.lightBullish)
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.currentPrice.toStringAsFixed(widget.precision),
                        style: AppTheme.mono(
                          context: context,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkBullish
                              : AppTheme.lightBullish,
                        ),
                      ),
                    ),
                    // Timeframe pills inside top bar (wrapped in Expanded for horizontal ListView)
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TimeframeSelector(
                          selectedTimeframe: _currentInterval,
                          onSelected: (tf) => _fetchCandlesForTimeframe(tf),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (_isCrosshairActive)
                      GestureDetector(
                        onTap: () {
                          setState(() => _isCrosshairActive = false);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A84FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Done',
                                style: AppTheme.sans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Dedicated Exit Fullscreen Button (never confusingly mixed with crosshair cancel)
                    IconButton(
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: 'Exit Fullscreen',
                      onPressed: () {
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),

              if (_isLoadingCandles)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
                ),

              // Fullscreen Candlestick Chart Area
              Expanded(
                child: _candles.isEmpty
                    ? Center(
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
                              'No Market Data for ${widget.symbol} ($_currentInterval)',
                              style: AppTheme.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No cached candles found offline.',
                              style: AppTheme.sans(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _fetchCandlesForTimeframe(_currentInterval),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
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
                      )
                    : CandlestickChart(
                        symbol: widget.symbol,
                        candles: _candles,
                        currentPrice: _currentPrice,
                        alerts: widget.alertManager.activeAlerts
                            .where((a) => a.symbol == widget.symbol)
                            .toList(),
                        precision: widget.precision,
                        interval: _currentInterval,
                        onLoadMoreHistory: _loadMoreHistory,
                        isLoadingMoreHistory: _isLoadingHistory,
                        isFullscreen: true,
                        onToggleFullscreen: () {
                          Navigator.pop(context);
                        },
                        isCrosshairActive: _isCrosshairActive,
                        onCrosshairActiveChanged: (val) {
                          setState(() => _isCrosshairActive = val);
                        },
                        dataSource: _dataSource,
                        signalOverlay: widget.signalOverlay,
                        onAddAlertFromDrawing: (drawing, targetPrice) {
                          _openCreateAlertSheet(
                            targetPrice: targetPrice,
                            fromDrawing: drawing,
                          );
                        },
                        onDrawingPriceUpdated: (drawingId, newPrice) {
                          widget.alertManager.updateAlertForDrawing(
                            drawingId,
                            newPrice,
                            currentPrice: _currentPrice,
                          );
                        },
                        onDrawingDeleted: (drawingId) {
                          widget.alertManager.removeAlertForDrawing(drawingId);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
