import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../models/ai_models.dart';
import '../models/drawing_models.dart';
import '../models/indicator_models.dart';
import '../models/market_models.dart';
import '../services/drawing_storage_service.dart';
import '../services/indicator_service.dart';
import '../services/settings_provider.dart';
import '../theme/app_theme.dart';

class CandlestickChart extends StatefulWidget {
  final String symbol;
  final List<BiquoteCandle> candles;
  final double currentPrice;
  final List<PriceAlert> alerts;
  final int precision;
  final String interval;
  final VoidCallback? onLoadMoreHistory;
  final bool isLoadingMoreHistory;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;
  final AgentSignal? signalOverlay;
  final VoidCallback? onDismissSignalOverlay;
  final void Function(ChartDrawing drawing, double targetPrice)?
  onAddAlertFromDrawing;
  final void Function(String drawingId, double newPrice)? onDrawingPriceUpdated;
  final void Function(String drawingId)? onDrawingDeleted;
  final bool? isCrosshairActive;
  final ValueChanged<bool>? onCrosshairActiveChanged;
  final String dataSource;

  const CandlestickChart({
    super.key,
    required this.symbol,
    required this.candles,
    required this.currentPrice,
    this.alerts = const [],
    this.precision = 5,
    this.interval = '1H',
    this.onLoadMoreHistory,
    this.isLoadingMoreHistory = false,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.signalOverlay,
    this.onDismissSignalOverlay,
    this.onAddAlertFromDrawing,
    this.onDrawingPriceUpdated,
    this.onDrawingDeleted,
    this.isCrosshairActive,
    this.onCrosshairActiveChanged,
    this.dataSource = 'live',
  });

  @override
  State<CandlestickChart> createState() => _CandlestickChartState();
}

class _CandlestickChartState extends State<CandlestickChart>
    with SingleTickerProviderStateMixin {
  // Viewport & Transform State
  double _candleWidth = 9.0;
  final double _minCandleWidth = 3.0;
  final double _maxCandleWidth = 42.0;
  double _scrollOffset = 0.0; // Index of the rightmost edge visible
  bool _isPinnedToRight = true;

  // Manual Price Scale (Vertical stretch/compress)
  double _manualPriceScale = 1.0;
  double _pricePanOffset = 0.0;

  // Interactive Crosshair & Inspection (TradingView Data Coordinate Locking)
  Offset? _crosshairPosition;
  DateTime? _crosshairTime;
  double? _crosshairPrice;
  int? _crosshairCandleIndex;
  BiquoteCandle? _hoverCandle;
  double? _hoverPrice;
  bool _isCrosshairActive = false;
  bool _isDraggingCrosshair = false;
  bool _justFinishedCrosshairTouch = false;
  Timer? _longPressCrosshairTimer;
  Timer? _countdownRepaintTimer;
  Offset _touchStartPos = Offset.zero;
  Offset _lastTouchPos = Offset.zero;

  // Touch Gesture tracking
  double _baseCandleWidth = 9.0;
  double _basePriceScale = 1.0;
  double _baseScrollOffset = 0.0;
  double _basePricePanOffset = 0.0;
  double _dragStartX = 0.0;
  double _dragStartY = 0.0;
  bool _isDraggingPriceScale = false;
  bool _didDragHaptic = false;

  // Drawing move & resize state
  bool _isDraggingDrawing = false;
  double _drawingDragStartPrice = 0.0;
  double _drawingDragStartIndex = 0.0;
  int _drawingDragHandleIndex =
      -1; // -1: move whole drawing, 0: handle 0, 1: handle 1
  List<ChartPoint>? _drawingDragOriginalPoints;

  // Drawing Tools Engine
  DrawingTool _activeTool = DrawingTool.none;
  List<ChartDrawing> _drawings = [];
  ChartDrawing? _inProgressDrawing;
  ChartDrawing? _selectedDrawing;
  Color _activeDrawingColor = const Color(0xFF64D2FF);

  // Technical Indicators Engine
  List<IndicatorConfig> _indicators = [];
  Map<String, IndicatorCalculationResult> _calculatedIndicators = {};

  // Drawing panel visibility — hidden by default so chart panning works immediately
  bool _isDrawingPanelVisible = false;

  // Animation controller for live candle pulse beacon
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // History Lazy Load Sentinel Guard
  bool _hasRequestedHistoryForThisScroll = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scrollOffset = widget.candles.length.toDouble();
    if (widget.isCrosshairActive != null) {
      _isCrosshairActive = widget.isCrosshairActive!;
      _isDrawingPanelVisible = widget.isCrosshairActive!;
    }
    _loadDrawings();
    _loadIndicators();
    if (SettingsProvider().showCandleCountdown) {
      _countdownRepaintTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant CandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (SettingsProvider().showCandleCountdown &&
        _countdownRepaintTimer == null) {
      _countdownRepaintTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!SettingsProvider().showCandleCountdown) {
      _countdownRepaintTimer?.cancel();
      _countdownRepaintTimer = null;
    }
    if (widget.isCrosshairActive != null &&
        widget.isCrosshairActive != oldWidget.isCrosshairActive) {
      setState(() {
        _isCrosshairActive = widget.isCrosshairActive!;
        _isDrawingPanelVisible = widget.isCrosshairActive!;
        if (!_isCrosshairActive) {
          _crosshairPosition = null;
          _crosshairPrice = null;
          _crosshairTime = null;
          _selectedDrawing = null;
          _activeTool = DrawingTool.none;
        }
      });
    }
    if (widget.symbol != oldWidget.symbol) {
      _loadDrawings();
      _hasRequestedHistoryForThisScroll = false;
      _scrollOffset = widget.candles.length.toDouble();
      _isPinnedToRight = true;
    }
    // If candles updated, recalculate indicators
    if (widget.candles != oldWidget.candles ||
        widget.candles.length != oldWidget.candles.length) {
      _recalculateIndicators();
    }
    // If candles count changed: anchor historical offset so chart never jumps
    if (widget.candles.length > oldWidget.candles.length) {
      final diff = widget.candles.length - oldWidget.candles.length;
      if (oldWidget.candles.isNotEmpty &&
          widget.candles.first.openTime.isBefore(
            oldWidget.candles.first.openTime,
          )) {
        // Historical candles prepended: shift scrollOffset
        _scrollOffset += diff;
        _hasRequestedHistoryForThisScroll = false;
      } else if (_isPinnedToRight) {
        // Pinned to live market edge: keep latest visible
        _scrollOffset = widget.candles.length.toDouble();
      } else {
        // User is inspecting historical candles and a new bar was appended at the right:
        // Increment _scrollOffset so historical candles DO NOT jump or jerk!
        _scrollOffset += diff;
      }
    } else if (_isPinnedToRight) {
      _scrollOffset = widget.candles.length.toDouble();
    }

    // When background history loading completes, clear guard for subsequent scrolls
    if (oldWidget.isLoadingMoreHistory && !widget.isLoadingMoreHistory) {
      _hasRequestedHistoryForThisScroll = false;
    }
  }

  Future<void> _loadIndicators() async {
    final list = await IndicatorService().loadActiveIndicators();
    if (mounted) {
      setState(() {
        _indicators = list;
        _recalculateIndicators();
      });
    }
  }

  void _recalculateIndicators() {
    final map = <String, IndicatorCalculationResult>{};
    for (final ind in _indicators) {
      if (ind.isVisible) {
        final res = IndicatorService().calculate(ind, widget.candles);
        if (res != null) {
          map[ind.id] = res;
        }
      }
    }
    _calculatedIndicators = map;
  }

  void _requestHistoryIfNearStart(double scrollOffset, double chartWidth) {
    final firstVisibleIndex = scrollOffset - chartWidth / _candleStep;
    if (firstVisibleIndex >= 20 ||
        _hasRequestedHistoryForThisScroll ||
        widget.isLoadingMoreHistory ||
        widget.onLoadMoreHistory == null) {
      if (firstVisibleIndex >= 30) {
        _hasRequestedHistoryForThisScroll = false;
      }
      return;
    }

    _hasRequestedHistoryForThisScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoadMoreHistory?.call();
    });
  }

  @override
  void dispose() {
    _longPressCrosshairTimer?.cancel();
    _countdownRepaintTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadDrawings() async {
    final list = await DrawingStorageService().loadDrawings(widget.symbol);
    if (mounted) {
      setState(() {
        _drawings = list;
        _selectedDrawing = null;
        _inProgressDrawing = null;
      });
    }
  }

  Future<void> _saveDrawings() async {
    await DrawingStorageService().saveDrawings(widget.symbol, _drawings);
  }

  void _setCrosshairActive(bool active) {
    setState(() {
      _isCrosshairActive = active;
      if (!active) {
        _isDraggingCrosshair = false;
        _crosshairPosition = null;
        _crosshairTime = null;
        _crosshairPrice = null;
        _crosshairCandleIndex = null;
        _hoverCandle = null;
        _hoverPrice = null;
      }
    });
    widget.onCrosshairActiveChanged?.call(active);
  }

  void _resetPriceScale() {
    setState(() {
      _manualPriceScale = 1.0;
      _pricePanOffset = 0.0;
    });
    HapticFeedback.mediumImpact();
  }

  void _jumpToLatest() {
    setState(() {
      _scrollOffset = widget.candles.length.toDouble();
      _pricePanOffset = 0.0;
      _isPinnedToRight = true;
      _crosshairPosition = null;
      _hoverCandle = null;
      _hoverPrice = null;
    });
    HapticFeedback.lightImpact();
  }

  // Projection math
  double get _candleSpacing => _candleWidth * 0.22;
  double get _candleStep => _candleWidth + _candleSpacing;

  double _indexToX(double index, double chartWidth) {
    return chartWidth - (_scrollOffset - index) * _candleStep;
  }

  double _xToIndex(double x, double chartWidth) {
    return _scrollOffset - (chartWidth - x) / _candleStep;
  }

  int _findNearestCandleIndex(DateTime time) {
    if (widget.candles.isEmpty) return 0;
    int closestIdx = 0;
    int minDiff = 9007199254740992; // Number.MAX_SAFE_INTEGER — web-safe
    for (int i = 0; i < widget.candles.length; i++) {
      final diff =
          (widget.candles[i].openTime.millisecondsSinceEpoch -
                  time.millisecondsSinceEpoch)
              .abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const double priceScaleWidth = 65.0;
    const double timeScaleHeight = 24.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Guard against unbounded/infinite constraints (e.g. when inside scrollable)
        final totalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 400.0;
        final totalHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 300.0;
        final chartWidth = max(50.0, totalWidth - priceScaleWidth);

        // Dynamic stacked sub-panes: visible in normal mode, hidden in drawing mode to give full height
        final visibleSubPaneIndicators = _indicators
            .where(
              (ind) =>
                  ind.isVisible &&
                  ind.type.placement == IndicatorPlacement.subPane,
            )
            .toList();
        final int subPaneCount = visibleSubPaneIndicators.length;
        final bool hasSubPane = !_isCrosshairActive && subPaneCount > 0;

        const double subPaneSeparatorHeight = 1.0;
        final double totalMainHeight = max(60.0, totalHeight - timeScaleHeight);

        // TradingView-style progressive vertical allocation
        double totalSubPanesRatio = 0.0;
        if (subPaneCount == 1) {
          totalSubPanesRatio = 0.28;
        } else if (subPaneCount == 2) {
          totalSubPanesRatio = 0.40;
        } else if (subPaneCount >= 3) {
          totalSubPanesRatio = (0.16 * subPaneCount).clamp(0.40, 0.52);
        }

        final double totalSeparators = subPaneCount * subPaneSeparatorHeight;
        final double availableHeight = max(
          50.0,
          totalMainHeight - totalSeparators,
        );

        final double mainChartHeight = hasSubPane
            ? max(80.0, availableHeight * (1.0 - totalSubPanesRatio))
            : totalMainHeight;
        final double totalSubPanesHeight = hasSubPane
            ? max(35.0 * subPaneCount, availableHeight - mainChartHeight)
            : 0.0;
        final double subPaneHeight = hasSubPane
            ? totalSubPanesHeight / subPaneCount
            : 0.0;
        final double chartHeight = mainChartHeight;
        final chartArea = Rect.fromLTWH(0, 0, chartWidth, chartHeight);

        // Clamp scrollOffset
        if (_scrollOffset < 5.0) _scrollOffset = 5.0;
        if (_scrollOffset > widget.candles.length + 10.0) {
          _scrollOffset = widget.candles.length + 10.0;
        }

        // Calculate visible candle slice bounds
        final double visibleCount = chartWidth / _candleStep;
        final int startIndex = max(
          0,
          (_scrollOffset - visibleCount - 2).floor(),
        );
        final int endIndex = min(
          widget.candles.length,
          (_scrollOffset + 2).ceil(),
        );

        // Keep the render-time sentinel as a fallback for viewport/zoom changes.
        _requestHistoryIfNearStart(_scrollOffset, chartWidth);

        // Calculate min & max price in visible window
        double minPrice = double.infinity;
        double maxPrice = double.negativeInfinity;

        for (
          int i = max(0, startIndex);
          i < min(widget.candles.length, endIndex);
          i++
        ) {
          final c = widget.candles[i];
          if (c.low < minPrice) minPrice = c.low;
          if (c.high > maxPrice) maxPrice = c.high;
        }

        if (widget.currentPrice > 0 && _isPinnedToRight) {
          minPrice = min(minPrice, widget.currentPrice);
          maxPrice = max(maxPrice, widget.currentPrice);
        }

        // Auto-scale purely to visible candles and live price so bars are beautifully proportioned

        if (minPrice == double.infinity ||
            maxPrice == double.negativeInfinity) {
          minPrice = widget.currentPrice * 0.99;
          maxPrice = widget.currentPrice * 1.01;
        }

        final double rawRange = (maxPrice - minPrice > 0)
            ? maxPrice - minPrice
            : 1.0;
        final double padding = rawRange * 0.08;
        double baseMin = minPrice - padding;
        double baseMax = maxPrice + padding;
        final double baseCenter = (baseMin + baseMax) / 2.0;
        final double scaledSpan = (baseMax - baseMin) / _manualPriceScale;

        final double finalMinPrice =
            (baseCenter - scaledSpan / 2.0) + _pricePanOffset;
        final double finalMaxPrice =
            (baseCenter + scaledSpan / 2.0) + _pricePanOffset;
        final double effectiveRange = max(
          0.000001,
          finalMaxPrice - finalMinPrice,
        );

        return Stack(
          children: [
            // Gesture Arena with 1-Second Long Press Crosshair & Chart Lock
            Listener(
              onPointerDown: (event) {
                _touchStartPos = event.localPosition;
                _lastTouchPos = event.localPosition;

                // Priority 0: If drawing tool is active or a drawing is selected, never trigger crosshair timer!
                if (_activeTool != DrawingTool.none ||
                    _selectedDrawing != null) {
                  _longPressCrosshairTimer?.cancel();
                  return;
                }

                // Priority 1: If touch hits an existing drawing, select drawing and prevent crosshairs
                final drawingHit = _hitTestDrawing(
                  event.localPosition,
                  chartArea,
                  finalMinPrice,
                  effectiveRange,
                );
                if (drawingHit != null) {
                  _longPressCrosshairTimer?.cancel();
                  setState(() {
                    _selectedDrawing = drawingHit;
                  });
                  _setCrosshairActive(false);
                  HapticFeedback.selectionClick();
                  return;
                }

                if (_isCrosshairActive) {
                  // TradingView ergonomics: If touch is near reticle, drag the reticle; otherwise allow panning chart
                  final isNearReticle =
                      _crosshairPosition != null &&
                      (event.localPosition - _crosshairPosition!).distance <
                          52.0;
                  if (isNearReticle) {
                    _isDraggingCrosshair = true;
                    setState(() {
                      _updateCrosshair(
                        event.localPosition,
                        chartArea,
                        chartWidth,
                        finalMinPrice,
                        effectiveRange,
                      );
                    });
                    HapticFeedback.selectionClick();
                    return;
                  } else {
                    _isDraggingCrosshair = false;
                  }
                }

                _longPressCrosshairTimer?.cancel();
                // 500ms standard long-press hold to activate crosshair on empty chart canvas
                _longPressCrosshairTimer = Timer(
                  const Duration(milliseconds: 500),
                  () {
                    HapticFeedback.heavyImpact();
                    setState(() {
                      _selectedDrawing = null;
                      _isDraggingCrosshair = true;
                      _updateCrosshair(
                        _lastTouchPos,
                        chartArea,
                        chartWidth,
                        finalMinPrice,
                        effectiveRange,
                      );
                    });
                    _setCrosshairActive(true);
                  },
                );
              },
              onPointerMove: (event) {
                _lastTouchPos = event.localPosition;
                if (_isDraggingCrosshair) {
                  // Dragging reticle across chart bars & prices smoothly
                  setState(() {
                    _updateCrosshair(
                      event.localPosition,
                      chartArea,
                      chartWidth,
                      finalMinPrice,
                      effectiveRange,
                    );
                  });
                } else {
                  if ((event.localPosition - _touchStartPos).distance > 8.0) {
                    _longPressCrosshairTimer?.cancel();
                  }
                }
              },
              onPointerUp: (event) {
                _longPressCrosshairTimer?.cancel();
                if (_isDraggingCrosshair) {
                  // Finger lifted: Crosshair remains active and pinned to data coordinates!
                  _justFinishedCrosshairTouch = true;
                  setState(() {
                    _isDraggingCrosshair = false;
                  });
                }
              },
              onPointerCancel: (event) {
                _longPressCrosshairTimer?.cancel();
                _isDraggingCrosshair = false;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) {
                  if (_isCrosshairActive) {
                    _setCrosshairActive(false);
                    HapticFeedback.lightImpact();
                  } else {
                    _resetPriceScale();
                  }
                },
                onScaleStart: (details) {
                  _longPressCrosshairTimer?.cancel();
                  if (_isDraggingCrosshair) return;

                  _baseCandleWidth = _candleWidth;
                  _basePriceScale = _manualPriceScale;
                  _baseScrollOffset = _scrollOffset;
                  _basePricePanOffset = _pricePanOffset;
                  _dragStartX = details.localFocalPoint.dx;
                  _dragStartY = details.localFocalPoint.dy;
                  _isDraggingPriceScale =
                      details.localFocalPoint.dx >= chartWidth;
                  _isDraggingDrawing = false;
                  _didDragHaptic = false;
                  _drawingDragHandleIndex = -1;

                  // Check if dragging a drawing or its handles (cursor mode)
                  if (!_isDraggingPriceScale &&
                      _activeTool == DrawingTool.none) {
                    final hit = _hitTestDrawing(
                      details.localFocalPoint,
                      chartArea,
                      finalMinPrice,
                      effectiveRange,
                    );
                    if (hit != null) {
                      setState(() => _selectedDrawing = hit);
                      if (hit.isLocked) {
                        _isDraggingDrawing = false;
                      } else {
                        _isDraggingDrawing = true;
                        _drawingDragStartPrice =
                            finalMinPrice +
                            ((chartArea.bottom -
                                        details.localFocalPoint.dy.clamp(
                                          0.0,
                                          chartHeight,
                                        )) /
                                    chartHeight) *
                                effectiveRange;
                        _drawingDragStartIndex = _xToIndex(
                          details.localFocalPoint.dx.clamp(0.0, chartWidth),
                          chartWidth,
                        );
                        _drawingDragOriginalPoints = List.from(hit.points);

                        // Check if touched near endpoint 0 or endpoint 1 handles
                        if (hit.points.length >= 2) {
                          double pToY(double price) =>
                              chartArea.bottom -
                              ((price - finalMinPrice) / effectiveRange) *
                                  chartHeight;
                          final idx0 = _findNearestCandleIndex(
                            hit.points[0].time,
                          );
                          final x0 = _indexToX(idx0.toDouble(), chartWidth);
                          final y0 = pToY(hit.points[0].price);

                          final idx1 = _findNearestCandleIndex(
                            hit.points[1].time,
                          );
                          final x1 = _indexToX(idx1.toDouble(), chartWidth);
                          final y1 = pToY(hit.points[1].price);

                          if ((details.localFocalPoint - Offset(x0, y0))
                                  .distance <
                              36.0) {
                            _drawingDragHandleIndex = 0;
                          } else if ((details.localFocalPoint - Offset(x1, y1))
                                  .distance <
                              36.0) {
                            _drawingDragHandleIndex = 1;
                          }
                        }
                      }
                    } else {
                      // Touched blank space: deselect so user can pan normally
                      setState(() => _selectedDrawing = null);
                    }
                  } else if (!_isDraggingPriceScale &&
                      _activeTool != DrawingTool.none) {
                    _handleDrawingStart(
                      details.localFocalPoint,
                      chartArea,
                      finalMinPrice,
                      effectiveRange,
                    );
                  }
                },
                onScaleUpdate: (details) {
                  // When crosshair is active & dragging, chart panning is locked!
                  if (_isDraggingCrosshair) {
                    return;
                  }

                  // Pinch to Zoom: horizontal scale → candle width, vertical scale → price scale
                  if (details.pointerCount >= 2) {
                    final newWidth =
                        (_baseCandleWidth * details.horizontalScale).clamp(
                          _minCandleWidth,
                          _maxCandleWidth,
                        );
                    final focalX = details.localFocalPoint.dx.clamp(
                      0.0,
                      chartWidth,
                    );
                    final candleUnderFocal =
                        _scrollOffset -
                        (chartWidth - focalX) / (_candleWidth + _candleSpacing);

                    // Vertical pinch scale adjusts price scale (relative to gesture start)
                    final newPriceScale =
                        (_basePriceScale * details.verticalScale).clamp(
                          0.1,
                          30.0,
                        );

                    setState(() {
                      _candleWidth = newWidth;
                      _manualPriceScale = newPriceScale;
                      _scrollOffset =
                          candleUnderFocal +
                          (chartWidth - focalX) /
                              (_candleWidth + _candleSpacing);
                      if (_scrollOffset >= widget.candles.length) {
                        _isPinnedToRight = true;
                      } else {
                        _isPinnedToRight = false;
                      }
                    });
                    _requestHistoryIfNearStart(_scrollOffset, chartWidth);
                    return;
                  }

                  // 1-Finger vertical drag on price scale area → stretch/compress price scale vertically
                  if (_isDraggingPriceScale) {
                    final dy = details.localFocalPoint.dy - _dragStartY;
                    _dragStartY = details.localFocalPoint.dy;
                    final factor = 1.0 - (dy / 100.0);
                    setState(() {
                      _manualPriceScale = (_manualPriceScale * factor).clamp(
                        0.1,
                        30.0,
                      );
                    });
                    return;
                  }

                  // Active Drawing Drag (in-progress drawing creation)
                  if (_activeTool != DrawingTool.none &&
                      _inProgressDrawing != null) {
                    _handleDrawingUpdate(
                      details.localFocalPoint,
                      chartArea,
                      finalMinPrice,
                      effectiveRange,
                    );
                    return;
                  }

                  // Move or Resize Selected Drawing (only if not locked)
                  if (_isDraggingDrawing &&
                      _selectedDrawing != null &&
                      !_selectedDrawing!.isLocked &&
                      _drawingDragOriginalPoints != null) {
                    final rawCurrentPrice =
                        finalMinPrice +
                        ((chartArea.bottom -
                                    details.localFocalPoint.dy.clamp(
                                      0.0,
                                      chartHeight,
                                    )) /
                                chartHeight) *
                            effectiveRange;
                    final currentIndex = _xToIndex(
                      details.localFocalPoint.dx.clamp(0.0, chartWidth),
                      chartWidth,
                    );
                    final snapIndex = currentIndex.round().clamp(
                      0,
                      widget.candles.length - 1,
                    );
                    final currentPrice = SettingsProvider().magneticSnapping
                        ? _snapPriceToMarket(
                            rawCurrentPrice,
                            snapIndex,
                            finalMinPrice,
                            effectiveRange,
                            chartHeight,
                          )
                        : rawCurrentPrice;
                    final priceDelta = currentPrice - _drawingDragStartPrice;
                    if (SettingsProvider().vibrateOnDrag && !_didDragHaptic) {
                      _didDragHaptic = true;
                      HapticFeedback.selectionClick();
                    }
                    final indexDelta = currentIndex - _drawingDragStartIndex;
                    final intervalMs = widget.candles.length > 1
                        ? widget.candles[1].openTime.millisecondsSinceEpoch -
                              widget.candles[0].openTime.millisecondsSinceEpoch
                        : 3600000;

                    setState(() {
                      if (_drawingDragHandleIndex == 0 &&
                          _selectedDrawing!.points.isNotEmpty) {
                        // Resize endpoint 0
                        final originalPt0 = _drawingDragOriginalPoints![0];
                        final newTime = originalPt0.time.add(
                          Duration(
                            milliseconds: (indexDelta * intervalMs).round(),
                          ),
                        );
                        final newPts = List<ChartPoint>.from(
                          _selectedDrawing!.points,
                        );
                        newPts[0] = ChartPoint(
                          time: newTime,
                          price: originalPt0.price + priceDelta,
                        );
                        final idx = _drawings.indexOf(_selectedDrawing!);
                        if (idx != -1) {
                          _drawings[idx] = _selectedDrawing!.copyWith(
                            points: newPts,
                          );
                          _selectedDrawing = _drawings[idx];
                        }
                      } else if (_drawingDragHandleIndex == 1 &&
                          _selectedDrawing!.points.length >= 2) {
                        // Resize endpoint 1
                        final originalPt1 = _drawingDragOriginalPoints![1];
                        final newTime = originalPt1.time.add(
                          Duration(
                            milliseconds: (indexDelta * intervalMs).round(),
                          ),
                        );
                        final newPts = List<ChartPoint>.from(
                          _selectedDrawing!.points,
                        );
                        newPts[1] = ChartPoint(
                          time: newTime,
                          price: originalPt1.price + priceDelta,
                        );
                        final idx = _drawings.indexOf(_selectedDrawing!);
                        if (idx != -1) {
                          _drawings[idx] = _selectedDrawing!.copyWith(
                            points: newPts,
                          );
                          _selectedDrawing = _drawings[idx];
                        }
                      } else {
                        // Move entire drawing
                        final movedPoints = _drawingDragOriginalPoints!.map((
                          pt,
                        ) {
                          final newTime = pt.time.add(
                            Duration(
                              milliseconds: (indexDelta * intervalMs).round(),
                            ),
                          );
                          return ChartPoint(
                            time: newTime,
                            price: pt.price + priceDelta,
                          );
                        }).toList();
                        final idx = _drawings.indexOf(_selectedDrawing!);
                        if (idx != -1) {
                          _drawings[idx] = _selectedDrawing!.copyWith(
                            points: movedPoints,
                          );
                          _selectedDrawing = _drawings[idx];
                        }
                      }
                    });
                    return;
                  }

                  // Normal Chart Panning (2D: any direction!)
                  final dx = details.localFocalPoint.dx - _dragStartX;
                  final dy = details.localFocalPoint.dy - _dragStartY;
                  final indexDelta = dx / _candleStep;
                  final newOffset = _baseScrollOffset - indexDelta;

                  // Vertical pan: dragging down (dy > 0) pulls chart content down (showing higher prices above)
                  final priceDelta = (dy / chartHeight) * effectiveRange;
                  final newPricePanOffset = _basePricePanOffset + priceDelta;

                  setState(() {
                    _scrollOffset = newOffset;
                    _pricePanOffset = newPricePanOffset;
                    if (_scrollOffset >= widget.candles.length - 0.5) {
                      _isPinnedToRight = true;
                    } else {
                      _isPinnedToRight = false;
                    }

                    // Keep active crosshair pinned to data coordinates during pan
                    if (_isCrosshairActive &&
                        _crosshairTime != null &&
                        _crosshairPrice != null) {
                      final idx = _findNearestCandleIndex(_crosshairTime!);
                      if (idx >= 0) {
                        final x = _indexToX(idx.toDouble(), chartWidth);
                        final currentMinPrice = finalMinPrice + priceDelta;
                        final y =
                            chartArea.bottom -
                            ((_crosshairPrice! - currentMinPrice) /
                                    effectiveRange) *
                                chartHeight;
                        _crosshairPosition = Offset(
                          x,
                          y.clamp(chartArea.top, chartArea.bottom),
                        );
                      }
                    }
                  });
                  _requestHistoryIfNearStart(_scrollOffset, chartWidth);
                },
                onScaleEnd: (details) {
                  _longPressCrosshairTimer?.cancel();
                  _isDraggingCrosshair = false;
                  _isDraggingPriceScale = false;
                  if (_isDraggingDrawing && _selectedDrawing != null) {
                    final d = _selectedDrawing!;
                    final handleIdx = _drawingDragHandleIndex;
                    _isDraggingDrawing = false;
                    _drawingDragOriginalPoints = null;
                    _drawingDragHandleIndex = -1;
                    _saveDrawings();

                    final hasAlert =
                        d.hasAlert ||
                        widget.alerts.any(
                          (a) => a.drawingId == d.id && a.isActive,
                        );
                    if (hasAlert && d.points.isNotEmpty) {
                      final updatedPrice =
                          (handleIdx == 1 && d.points.length > 1)
                          ? d.points[1].price
                          : d.points.first.price;
                      widget.onDrawingPriceUpdated?.call(d.id, updatedPrice);
                    }
                  }
                  if (_activeTool != DrawingTool.none &&
                      _inProgressDrawing != null) {
                    _handleDrawingEnd();
                  }
                },
                onTapUp: (details) {
                  if (_justFinishedCrosshairTouch) {
                    _justFinishedCrosshairTouch = false;
                    return;
                  }

                  // 1. If an active drawing tool is selected, draw immediately
                  if (_activeTool == DrawingTool.horizontalLine) {
                    _handleDrawingStart(
                      details.localPosition,
                      chartArea,
                      finalMinPrice,
                      effectiveRange,
                    );
                    return;
                  } else if (_activeTool != DrawingTool.none) {
                    _handleTapToDraw(
                      details.localPosition,
                      chartArea,
                      finalMinPrice,
                      effectiveRange,
                    );
                    return;
                  }

                  // 2. Hit-test existing drawings FIRST! Selecting a drawing dismisses crosshair
                  final hit = _hitTestDrawing(
                    details.localPosition,
                    chartArea,
                    finalMinPrice,
                    effectiveRange,
                  );
                  if (hit != null) {
                    setState(() {
                      _selectedDrawing = hit;
                    });
                    _setCrosshairActive(false);
                    HapticFeedback.selectionClick();
                    return;
                  }

                  // 3. If crosshair active and tapped empty canvas, reposition reticle
                  if (_isCrosshairActive) {
                    setState(() {
                      _selectedDrawing = null;
                      _updateCrosshair(
                        details.localPosition,
                        chartArea,
                        chartWidth,
                        finalMinPrice,
                        effectiveRange,
                      );
                    });
                    HapticFeedback.selectionClick();
                    return;
                  }

                  // 4. Tapped empty space without crosshair: deselect any selected drawing
                  setState(() {
                    _selectedDrawing = null;
                  });
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(totalWidth, totalHeight),
                      painter: _FullblownChartPainter(
                        candles: widget.candles,
                        currentPrice: widget.currentPrice,
                        alerts: widget.alerts,
                        precision: widget.precision,
                        isDark: isDark,
                        scrollOffset: _scrollOffset,
                        candleWidth: _candleWidth,
                        candleSpacing: _candleSpacing,
                        minPrice: finalMinPrice,
                        maxPrice: finalMaxPrice,
                        priceRange: effectiveRange,
                        chartArea: chartArea,
                        drawings: _drawings,
                        inProgressDrawing: _inProgressDrawing,
                        selectedDrawing: _selectedDrawing,
                        crosshairPosition: _crosshairPosition,
                        crosshairTime: _crosshairTime,
                        crosshairPrice: _crosshairPrice,
                        crosshairCandleIndex: _crosshairCandleIndex,
                        hoverCandle: _hoverCandle,
                        hoverPrice: _hoverPrice,
                        isCrosshairActive: _isCrosshairActive,
                        pulseValue: _pulseAnimation.value,
                        isPinnedToRight: _isPinnedToRight,
                        interval: widget.interval,
                        signalOverlay: widget.signalOverlay,
                        indicatorResults: _calculatedIndicators,
                        hasSubPane: hasSubPane,
                        subPaneHeight: subPaneHeight,
                        subPaneIndicators: hasSubPane
                            ? _indicators
                                  .where(
                                    (ind) =>
                                        ind.isVisible &&
                                        ind.type.placement ==
                                            IndicatorPlacement.subPane,
                                  )
                                  .toList()
                            : [],
                        candleType: SettingsProvider().chartCandleType,
                        showCountdown: SettingsProvider().showCandleCountdown,
                        sessionShading: SettingsProvider().sessionShading,
                        colorblindMode: SettingsProvider().colorblindChartMode,
                        tradingTimezone: SettingsProvider().tradingTimezone,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Top Chart HUD (Matching Chart.dc.html lines 84-87 when crosshair is inactive)
            if (!_isCrosshairActive && widget.candles.isNotEmpty)
              Positioned(top: 6, left: 14, child: _buildTopChartHud()),

            if (widget.isLoadingMoreHistory)
              Positioned(
                top: 34,
                left: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xE61C1C1E)
                        : const Color(0xEFFFFFFF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3A3A3C)
                          : const Color(0xFFE5E5EA),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Loading older candles',
                          style: AppTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating OHLC Inspection Box (Matching ChartTools.dc.html lines 70-72 when crosshair is active)
            if (_isCrosshairActive && _selectedDrawing == null)
              Positioned(top: 6, left: 72, child: _buildOhlcInspectionBox()),

            // Left Drawing Palette (Matching ChartTools.dc.html lines 76-84)
            if (_isCrosshairActive || _isDrawingPanelVisible)
              Positioned(
                left: 14,
                top: 70,
                child: _buildDrawingToolsPalette(isDark, theme),
              ),

            // Selected Drawing Floating Context Menu (Matching ChartTools.dc.html lines 60-64)
            if (_selectedDrawing != null)
              Positioned(
                top: 8,
                left: 72,
                child: _buildDrawingContextMenu(isDark, theme),
              ),

            // Bottom Style Strip — only when a drawing is selected
            if (_selectedDrawing != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 8,
                child: _buildStyleStrip(isDark, theme),
              ),

            // Crosshair Dismiss Button — shown bottom-right when crosshair active & no drawing selected
            if (_isCrosshairActive && _selectedDrawing == null)
              Positioned(
                right: priceScaleWidth + 8,
                top: mainChartHeight - 44,
                child: _buildDismissCrosshairButton(),
              ),

            // Floating Crosshair Reticle Button in Bottom Right of Candlestick Chart (Matching Image 3)
            // Situated directly on the candlestick chart canvas above the time scale
            if (!_isCrosshairActive)
              Positioned(
                right: priceScaleWidth + 8,
                top: mainChartHeight - 44,
                child: _buildFloatingCrosshairButton(),
              ),

            // Floating "Jump to Latest" live price chip when user is scrolled into history
            if (!_isPinnedToRight && _scrollOffset < widget.candles.length - 4)
              Positioned(
                bottom: timeScaleHeight + 52,
                right: priceScaleWidth + 8,
                child: _buildJumpToLatestButton(isDark, theme),
              ),

            // History Loading Indicator Badge
            if (widget.isLoadingMoreHistory)
              Positioned(
                top: 10,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (isDark
                                ? AppTheme.darkSurface2
                                : AppTheme.lightSurface2)
                            .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.darkPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Loading history...',
                        style: AppTheme.mono(context: context, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),

            // AI Signal Floating Banner
            if (widget.signalOverlay != null &&
                widget.signalOverlay!.hasValidTradeSetup)
              Positioned(
                top: 48,
                left: 12,
                child: _buildSignalBanner(isDark, theme),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSignalBanner(bool isDark, ThemeData theme) {
    final sig = widget.signalOverlay!;
    final isBuy = sig.direction == SignalDirection.buy;
    final isSell = sig.direction == SignalDirection.sell;
    final color = isBuy
        ? const Color(0xFF00E676)
        : (isSell ? const Color(0xFFFF5252) : Colors.amber);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1)
            .withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sig.direction.label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'E: ${sig.entryPrice.toStringAsFixed(widget.precision)} | SL: ${sig.stopLoss.toStringAsFixed(widget.precision)} | TP: ${sig.takeProfit.toStringAsFixed(widget.precision)}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          if (widget.onDismissSignalOverlay != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.onDismissSignalOverlay!();
                HapticFeedback.lightImpact();
              },
              child: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  // Crosshair calculation
  void _updateCrosshair(
    Offset pos,
    Rect chartArea,
    double chartWidth,
    double minPrice,
    double priceRange,
  ) {
    if (widget.candles.isEmpty) return;
    final clampedX = pos.dx.clamp(0.0, chartWidth);
    var clampedY = pos.dy.clamp(0.0, chartArea.height);

    final rawIndex = _xToIndex(clampedX, chartWidth);
    final candleIndex = rawIndex.round().clamp(0, widget.candles.length - 1);
    final candle = widget.candles[candleIndex];

    final snappedX = _indexToX(candleIndex.toDouble(), chartWidth);
    var price =
        minPrice +
        ((chartArea.bottom - clampedY) / chartArea.height) * priceRange;

    final settings = SettingsProvider();
    if (settings.magneticSnapping) {
      price = _snapPriceToMarket(
        price,
        candleIndex,
        minPrice,
        priceRange,
        chartArea.height,
      );
      clampedY =
          (chartArea.bottom -
                  ((price - minPrice) / priceRange) * chartArea.height)
              .clamp(0.0, chartArea.height);
    }

    if (settings.vibrateOnDrag) {
      HapticFeedback.selectionClick();
    }

    _crosshairPosition = Offset(snappedX, clampedY);
    _crosshairTime = candle.openTime;
    _crosshairPrice = price;
    _crosshairCandleIndex = candleIndex;
    _hoverCandle = candle;
    _hoverPrice = price;
  }

  double _snapPriceToMarket(
    double price,
    int candleIndex,
    double minPrice,
    double priceRange,
    double chartHeight,
  ) {
    if (candleIndex < 0 ||
        candleIndex >= widget.candles.length ||
        priceRange <= 0 ||
        chartHeight <= 0) {
      return price;
    }
    final candle = widget.candles[candleIndex];
    final roundStep = pow(10, -(widget.precision - 2)).toDouble();
    final candidates = <double>[
      candle.open,
      candle.high,
      candle.low,
      candle.close,
      (price / roundStep).round() * roundStep,
    ];
    final threshold = priceRange * (10 / chartHeight);
    candidates.sort((a, b) => (a - price).abs().compareTo((b - price).abs()));
    return (candidates.first - price).abs() <= threshold
        ? candidates.first
        : price;
  }

  // Drawing Handlers
  void _handleDrawingStart(
    Offset localPos,
    Rect chartArea,
    double minPrice,
    double priceRange,
  ) {
    final chartWidth = chartArea.width;
    final rawIndex = _xToIndex(localPos.dx.clamp(0.0, chartWidth), chartWidth);
    final candleIndex = rawIndex.round().clamp(0, widget.candles.length - 1);
    final time = widget.candles[candleIndex].openTime;
    final price =
        minPrice +
        ((chartArea.bottom - localPos.dy) / chartArea.height) * priceRange;

    final pt = ChartPoint(time: time, price: price);

    if (_activeTool == DrawingTool.horizontalLine ||
        _activeTool == DrawingTool.verticalLine) {
      final drawing = ChartDrawing(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tool: _activeTool,
        points: [pt],
        color: _activeDrawingColor,
      );
      setState(() {
        _drawings.add(drawing);
        _selectedDrawing = drawing;
        _activeTool = DrawingTool.none;
      });
      _saveDrawings();
      HapticFeedback.lightImpact();
      return;
    }

    setState(() {
      _inProgressDrawing = ChartDrawing(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        tool: _activeTool,
        points: [pt, pt], // initial start and end point
        color: _activeDrawingColor,
      );
    });
  }

  void _handleDrawingUpdate(
    Offset localPos,
    Rect chartArea,
    double minPrice,
    double priceRange,
  ) {
    if (_inProgressDrawing == null) return;
    final chartWidth = chartArea.width;
    final rawIndex = _xToIndex(localPos.dx.clamp(0.0, chartWidth), chartWidth);
    final candleIndex = rawIndex.round().clamp(0, widget.candles.length - 1);
    final time = widget.candles[candleIndex].openTime;
    final price =
        minPrice +
        ((chartArea.bottom - localPos.dy) / chartArea.height) * priceRange;

    setState(() {
      final pts = List<ChartPoint>.from(_inProgressDrawing!.points);
      if (pts.length >= 2) {
        pts[1] = ChartPoint(time: time, price: price);
      }
      _inProgressDrawing = _inProgressDrawing!.copyWith(points: pts);
    });
  }

  void _handleDrawingEnd() {
    if (_inProgressDrawing != null) {
      setState(() {
        _drawings.add(_inProgressDrawing!);
        _selectedDrawing = _inProgressDrawing;
        _inProgressDrawing = null;
        _activeTool = DrawingTool.none;
      });
      _saveDrawings();
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapToDraw(
    Offset localPos,
    Rect chartArea,
    double minPrice,
    double priceRange,
  ) {
    final chartWidth = chartArea.width;
    final rawIndex = _xToIndex(localPos.dx.clamp(0.0, chartWidth), chartWidth);
    final candleIndex = rawIndex.round().clamp(0, widget.candles.length - 1);
    final time1 = widget.candles[candleIndex].openTime;
    final price1 =
        minPrice +
        ((chartArea.bottom - localPos.dy) / chartArea.height) * priceRange;
    final pt1 = ChartPoint(time: time1, price: price1);

    final secondIndex = min(widget.candles.length - 1, candleIndex + 8);
    final time2 = widget.candles[secondIndex].openTime;
    final price2 =
        price1 +
        (_activeTool == DrawingTool.rectangle ||
                _activeTool == DrawingTool.fibonacci
            ? (priceRange * 0.15)
            : (priceRange * 0.05));
    final pt2 = ChartPoint(time: time2, price: price2);

    final drawing = ChartDrawing(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      tool: _activeTool,
      points: [pt1, pt2],
      color: _activeDrawingColor,
    );

    setState(() {
      _drawings.add(drawing);
      _selectedDrawing = drawing;
      _activeTool = DrawingTool.none;
    });
    _saveDrawings();
    HapticFeedback.lightImpact();
  }

  ChartDrawing? _hitTestDrawing(
    Offset localPos,
    Rect chartArea,
    double minPrice,
    double priceRange,
  ) {
    final chartWidth = chartArea.width;
    double priceToY(double price) {
      return chartArea.bottom -
          ((price - minPrice) / priceRange) * chartArea.height;
    }

    const tolerance = 40.0;
    for (final d in _drawings.reversed) {
      if (d.points.isEmpty) continue;
      if (d.tool == DrawingTool.horizontalLine) {
        final lineY = priceToY(d.points.first.price);
        if ((localPos.dy - lineY).abs() < tolerance) return d;
      } else if (d.tool == DrawingTool.verticalLine) {
        final idx = _findNearestCandleIndex(d.points.first.time);
        final lineX = _indexToX(idx.toDouble(), chartWidth);
        if ((localPos.dx - lineX).abs() < tolerance) return d;
      } else if (d.points.length >= 2) {
        final idx1 = _findNearestCandleIndex(d.points[0].time);
        final idx2 = _findNearestCandleIndex(d.points[1].time);
        final x1 = _indexToX(idx1.toDouble(), chartWidth);
        final y1 = priceToY(d.points[0].price);
        final x2 = _indexToX(idx2.toDouble(), chartWidth);
        final y2 = priceToY(d.points[1].price);

        // If this drawing is selected, prioritize touching its endpoint handles
        if (_selectedDrawing?.id == d.id) {
          if ((localPos - Offset(x1, y1)).distance < 44.0) return d;
          if ((localPos - Offset(x2, y2)).distance < 44.0) return d;
        }

        if (d.tool == DrawingTool.rectangle) {
          final rect = Rect.fromPoints(Offset(x1, y1), Offset(x2, y2));
          // Hit test inside or within tolerance margin of rectangle
          if (rect.inflate(tolerance).contains(localPos)) return d;
        } else if (d.tool == DrawingTool.fibonacci) {
          final minY = min(y1, y2);
          final maxY = max(y1, y2);
          final minX = min(x1, x2) - tolerance;
          final maxX = max(x1, x2) + 60.0;
          if (localPos.dx >= minX &&
              localPos.dx <= maxX &&
              localPos.dy >= minY - tolerance &&
              localPos.dy <= maxY + tolerance) {
            return d;
          }
        } else if (d.tool == DrawingTool.ray) {
          final dist = _distanceToRay(localPos, Offset(x1, y1), Offset(x2, y2));
          if (dist < tolerance) return d;
        } else {
          // Trendline or Ruler: distance to line segment
          final dist = _distanceToSegment(
            localPos,
            Offset(x1, y1),
            Offset(x2, y2),
          );
          if (dist < tolerance) return d;
        }
      }
    }
    return null;
  }

  double _distanceToRay(Offset p, Offset a, Offset b) {
    final l2 = (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
    if (l2 == 0) return (p - a).distance;
    final t = max(
      0.0,
      ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2,
    );
    final projection = Offset(
      a.dx + t * (b.dx - a.dx),
      a.dy + t * (b.dy - a.dy),
    );
    return (p - projection).distance;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final l2 = (b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy);
    if (l2 == 0) return (p - a).distance;
    final t = max(
      0.0,
      min(
        1.0,
        ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2,
      ),
    );
    final projection = Offset(
      a.dx + t * (b.dx - a.dx),
      a.dy + t * (b.dy - a.dy),
    );
    return (p - projection).distance;
  }

  // Compact Floating "Jump to Latest" LIVE Chip
  Widget _buildJumpToLatestButton(bool isDark, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _jumpToLatest,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: (isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2)
                .withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.7),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF00E676),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'LIVE',
                style: AppTheme.mono(
                  context: context,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF00E5FF),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_forward_ios,
                size: 8,
                color: Color(0xFF00E5FF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Drawing Tools Vertical Dock Palette (Matching ChartTools.dc.html)
  Widget _buildDrawingToolsPalette(bool isDark, ThemeData theme) {
    final tools = [
      DrawingTool.none,
      DrawingTool.horizontalLine,
      DrawingTool.trendline,
      DrawingTool.ray,
      DrawingTool.fibonacci,
      DrawingTool.rectangle,
      DrawingTool.verticalLine,
    ];

    return Container(
      width: 54,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(44, 44, 46, 0.72),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: tools.map((t) {
              final isSelected = _activeTool == t;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeTool = isSelected ? DrawingTool.none : t;
                      _selectedDrawing = null;
                    });
                    HapticFeedback.selectionClick();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0A84FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: CustomPaint(
                      size: const Size(20, 20),
                      painter: _DrawingIconPainter(
                        tool: t,
                        color: isSelected
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
      ),
    );
  }

  // Selected Drawing Floating Context Menu (Matching ChartTools.dc.html)
  Widget _buildDrawingContextMenu(bool isDark, ThemeData theme) {
    if (_selectedDrawing == null) return const SizedBox.shrink();
    final d = _selectedDrawing!;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(44, 44, 46, 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Attach Alert button (Amber #FFB340)
              IconButton(
                icon: const Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                  color: Color(0xFFFFB340),
                ),
                tooltip: 'Attach Alert',
                style: IconButton.styleFrom(
                  minimumSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {
                  double targetPrice = d.points.first.price;
                  if (d.tool == DrawingTool.rectangle && d.points.length >= 2) {
                    targetPrice = max(d.points[0].price, d.points[1].price);
                  }
                  widget.onAddAlertFromDrawing?.call(d, targetPrice);
                  HapticFeedback.selectionClick();
                },
              ),
              // 2. Lock button
              IconButton(
                icon: Icon(
                  d.isLocked ? Icons.lock : Icons.lock_open_rounded,
                  size: 20,
                  color: d.isLocked ? const Color(0xFF0A84FF) : Colors.white,
                ),
                tooltip: d.isLocked ? 'Unlock' : 'Lock',
                style: IconButton.styleFrom(
                  minimumSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {
                  setState(() {
                    d.isLocked = !d.isLocked;
                  });
                  _saveDrawings();
                  HapticFeedback.selectionClick();
                },
              ),
              // 3. Delete button (Coral Red #FF6961)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFFFF6961),
                ),
                tooltip: 'Delete',
                style: IconButton.styleFrom(
                  minimumSize: const Size(38, 38),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () {
                  final drawingId = d.id;
                  setState(() {
                    _drawings.remove(d);
                    _selectedDrawing = null;
                  });
                  _saveDrawings();
                  widget.onDrawingDeleted?.call(drawingId);
                  HapticFeedback.lightImpact();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Bottom Style Strip in Drawing Mode (Matching Image 2)
  Widget _buildStyleStrip(bool isDark, ThemeData theme) {
    final d = _selectedDrawing;
    final colors = [
      const Color(0xFF64D2FF), // Cyan
      const Color(0xFFFFD60A), // Gold
      const Color(0xFFBF5AF2), // Purple
      const Color(0xFFFF453A), // Red
    ];

    final currentColor = d?.color ?? _activeDrawingColor;

    return Container(
      height: 62,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(44, 44, 46, 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 4 Color Swatches with Concentric Active Ring
              Row(
                children: colors.map((c) {
                  final isCurrent = currentColor.toARGB32() == c.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (d != null) {
                          d.color = c;
                        }
                        _activeDrawingColor = c;
                      });
                      _saveDrawings();
                      HapticFeedback.selectionClick();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: isCurrent
                            ? Border.all(color: c, width: 2.0)
                            : null,
                      ),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Drawing tool label (name only, no alert status text)
              Flexible(
                child: Text(
                  d?.tool.label ??
                      (_activeTool != DrawingTool.none
                          ? _activeTool.label
                          : ''),
                  style: AppTheme.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color.fromRGBO(235, 235, 245, 0.70),
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              // Deselect / dismiss drawing button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDrawing = null;
                    _activeTool = DrawingTool.none;
                  });
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Floating OHLC Inspection Box (Matching ChartTools.dc.html)
  Widget _buildOhlcInspectionBox() {
    final c =
        (_crosshairCandleIndex != null &&
            _crosshairCandleIndex! >= 0 &&
            _crosshairCandleIndex! < widget.candles.length)
        ? widget.candles[_crosshairCandleIndex!]
        : _hoverCandle ??
              (widget.candles.isNotEmpty ? widget.candles.last : null);
    if (c == null) return const SizedBox.shrink();

    final pctChange = c.open > 0 ? ((c.close - c.open) / c.open) * 100 : 0.0;
    final isBull = c.close >= c.open;
    final dateStr = DateFormat('dd MMM HH:mm').format(c.openTime);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(44, 44, 46, 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateStr,
                    style: AppTheme.sans(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${isBull ? '▲' : '▼'} ${pctChange.abs().toStringAsFixed(2)}%',
                    style: AppTheme.mono(
                      color: isBull
                          ? const Color(0xFF43E06A)
                          : const Color(0xFFFF453A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'O ${c.open.toStringAsFixed(widget.precision)}   H ${c.high.toStringAsFixed(widget.precision)}\nL ${c.low.toStringAsFixed(widget.precision)}   C ${c.close.toStringAsFixed(widget.precision)}',
                style: AppTheme.mono(
                  color: const Color(0xFFE5E7EB),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Top Chart HUD (Matching Chart.dc.html lines 84-87)
  Widget _buildTopChartHud() {
    final c =
        _hoverCandle ??
        (widget.candles.isNotEmpty ? widget.candles.last : null);
    if (c == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'O ${c.open.toStringAsFixed(widget.precision)}  H ${c.high.toStringAsFixed(widget.precision)}  L ${c.low.toStringAsFixed(widget.precision)}  C ${c.close.toStringAsFixed(widget.precision)}',
          style: AppTheme.mono(
            color: const Color(0xFFE5E7EB),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'EMA 8',
              style: AppTheme.mono(
                color: const Color(0xFFFFD60A),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'EMA 21',
              style: AppTheme.mono(
                color: const Color(0xFF0A84FF),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(width: 8),
            Container(
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: widget.dataSource == 'live'
                    ? const Color(0xFF30D158).withValues(alpha: 0.16)
                    : (widget.dataSource == 'cached'
                          ? Colors.amber.withValues(alpha: 0.16)
                          : Colors.orange.withValues(alpha: 0.16)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: widget.dataSource == 'live'
                          ? const Color(0xFF30D158)
                          : (widget.dataSource == 'cached'
                                ? Colors.amber
                                : Colors.orange),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.dataSource == 'live'
                        ? 'LIVE'
                        : (widget.dataSource == 'cached'
                              ? 'OFFLINE CACHE'
                              : 'SIMULATED'),
                    style: TextStyle(
                      color: widget.dataSource == 'live'
                          ? const Color(0xFF43E06A)
                          : (widget.dataSource == 'cached'
                                ? Colors.amber
                                : Colors.orange),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Floating Crosshair Reticle Button in Bottom Right of Candlestick Chart (Matching Image 3)
  Widget _buildFloatingCrosshairButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _isDrawingPanelVisible = true;
          _activeTool = DrawingTool.none;
          _selectedDrawing = null;
        });
        _setCrosshairActive(true);
        HapticFeedback.selectionClick();
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(44, 44, 46, 0.66),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(18, 18),
            painter: _CrosshairButtonPainter(color: Colors.white),
          ),
        ),
      ),
    );
  }

  // Dismiss Crosshair Button — replaces the activate button while crosshair is active
  Widget _buildDismissCrosshairButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _isDrawingPanelVisible = false;
          _selectedDrawing = null;
          _activeTool = DrawingTool.none;
        });
        _setCrosshairActive(false);
        HapticFeedback.selectionClick();
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0A84FF).withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF0A84FF).withValues(alpha: 0.6),
              width: 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: Color(0xFF4DA3FF),
          ),
        ),
      ),
    );
  }
}

class _FullblownChartPainter extends CustomPainter {
  final List<BiquoteCandle> candles;
  final double currentPrice;
  final List<PriceAlert> alerts;
  final int precision;
  final bool isDark;
  final double scrollOffset;
  final double candleWidth;
  final double candleSpacing;
  final double minPrice;
  final double maxPrice;
  final double priceRange;
  final Rect chartArea;
  final List<ChartDrawing> drawings;
  final ChartDrawing? inProgressDrawing;
  final ChartDrawing? selectedDrawing;
  final Offset? crosshairPosition;
  final DateTime? crosshairTime;
  final double? crosshairPrice;
  final int? crosshairCandleIndex;
  final BiquoteCandle? hoverCandle;
  final double? hoverPrice;
  final bool isCrosshairActive;
  final double pulseValue;
  final bool isPinnedToRight;
  final String interval;
  final AgentSignal? signalOverlay;
  // Technical Indicators
  final Map<String, IndicatorCalculationResult> indicatorResults;
  final bool hasSubPane;
  final double subPaneHeight;
  final List<IndicatorConfig> subPaneIndicators;

  // Global Settings Properties
  final String candleType;
  final bool showCountdown;
  final bool sessionShading;
  final String colorblindMode;
  final String tradingTimezone;

  _FullblownChartPainter({
    required this.candles,
    required this.currentPrice,
    required this.alerts,
    required this.precision,
    required this.isDark,
    required this.scrollOffset,
    required this.candleWidth,
    required this.candleSpacing,
    required this.minPrice,
    required this.maxPrice,
    required this.priceRange,
    required this.chartArea,
    required this.drawings,
    required this.inProgressDrawing,
    required this.selectedDrawing,
    required this.crosshairPosition,
    this.crosshairTime,
    this.crosshairPrice,
    this.crosshairCandleIndex,
    required this.hoverCandle,
    required this.hoverPrice,
    required this.isCrosshairActive,
    required this.pulseValue,
    required this.isPinnedToRight,
    required this.interval,
    this.signalOverlay,
    this.indicatorResults = const {},
    this.hasSubPane = false,
    this.subPaneHeight = 0.0,
    this.subPaneIndicators = const [],
    this.candleType = 'Japanese Candles',
    this.showCountdown = true,
    this.sessionShading = true,
    this.colorblindMode = 'Standard',
    this.tradingTimezone = 'UTC / GMT',
  });

  double get candleStep => candleWidth + candleSpacing;

  bool get _isDeuteranopia =>
      colorblindMode.toLowerCase().contains('deuteranopia');
  bool get _isMonochrome => colorblindMode.toLowerCase().contains('monochrome');
  Color get _paletteBullColor => _isDeuteranopia
      ? const Color(0xFF00B8D4)
      : (_isMonochrome
            ? Colors.white
            : (isDark ? AppTheme.darkBullish : AppTheme.lightBullish));
  Color get _paletteBearColor => _isDeuteranopia
      ? const Color(0xFFFF8F00)
      : (_isMonochrome
            ? const Color(0xFF77777D)
            : (isDark ? AppTheme.darkBearish : AppTheme.lightBearish));
  Color get _paletteAccent => _isMonochrome
      ? const Color(0xFFB0B0B8)
      : (_isDeuteranopia ? const Color(0xFF00B8D4) : const Color(0xFFFF9F0A));
  Color get _paletteGridColor => _isMonochrome
      ? (isDark ? const Color(0xFF303036) : const Color(0xFFD0D0D5))
      : (isDark ? const Color(0xFF20242B) : const Color(0xFFE5E7EB));
  Color get _paletteTextColor => _isMonochrome
      ? (isDark ? const Color(0xFFD0D0D5) : const Color(0xFF424248))
      : (isDark ? const Color(0xFFD1D5DB) : AppTheme.lightTextSecondary);

  double indexToX(double index) {
    return chartArea.width - (scrollOffset - index) * candleStep;
  }

  double priceToY(double p) {
    return chartArea.bottom - ((p - minPrice) / priceRange) * chartArea.height;
  }

  int findNearestCandleIndex(DateTime time) {
    if (candles.isEmpty) return 0;
    int closestIdx = 0;
    int minDiff = 9007199254740992; // Number.MAX_SAFE_INTEGER — web-safe
    for (int i = 0; i < candles.length; i++) {
      final diff =
          (candles[i].openTime.millisecondsSinceEpoch -
                  time.millisecondsSinceEpoch)
              .abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIdx = i;
      }
    }
    return closestIdx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Subtle Grid Lines & Price Axis
    _drawGridAndAxes(canvas, size);

    // 2. Clip to Chart Canvas Area for Candles & Drawings
    canvas.save();
    canvas.clipRect(chartArea);

    // 3. Draw Candlesticks in visible viewport slice
    _drawCandlesticks(canvas);

    // 4. Draw Indicator Overlays (EMA, SMA, Bollinger Bands) on top of candles
    _drawIndicatorOverlays(canvas);

    // 5. Draw User Technical Drawings (Trendlines, Fibs, Zones, Ruler)
    _drawAllUserDrawings(canvas);

    // 6. Draw Alert Lines
    _drawAlertLines(canvas);

    // 6.5 Draw AI Signal Overlay (Entry / SL / TP)
    if (signalOverlay != null && signalOverlay!.hasValidTradeSetup) {
      _drawSignalOverlay(canvas);
    }

    // 7. Draw Real-time Pulsing Beacon on rightmost forming candle
    _drawRealtimeBeacon(canvas);

    canvas.restore();

    // 8. Draw Right Price Scale Axis Labels & Price Tags
    _drawPriceScaleLabels(canvas, size);

    // 9. Draw Bottom Time Axis Date/Time Labels
    _drawTimeAxisLabels(canvas, size);

    // 10. Draw Oscillator Sub-Pane (RSI / MACD / Stoch)
    if (hasSubPane && subPaneHeight > 0 && subPaneIndicators.isNotEmpty) {
      _drawSubPane(canvas, size);
    }

    // 11. Draw Interactive Crosshair & Snap Badges
    if (isCrosshairActive && crosshairPosition != null) {
      _drawCrosshair(canvas, size);
      if (hasSubPane && subPaneHeight > 0) {
        _drawSubPaneCrosshair(canvas, size);
      }
    }
  }

  void _drawGridAndAxes(Canvas canvas, Size size) {
    // 1. Active Market Session Background Shading (Tokyo, London, New York)
    if (sessionShading && candles.isNotEmpty) {
      final visibleCount = chartArea.width / candleStep;
      final startIndex = max(0, (scrollOffset - visibleCount - 2).floor());
      final endIndex = min(candles.length, (scrollOffset + 2).ceil());
      for (int i = startIndex; i < endIndex; i++) {
        final c = candles[i];
        // Sessions are defined in each market's own civil time, not as fixed
        // UTC/display-timezone bands. Convert each candle instant through the
        // market's DST rule so the band follows the real session year-round.
        final utc = c.openTime.toUtc();
        final tokyo = _convertTimezone(utc, 'Tokyo');
        final london = _convertTimezone(utc, 'London');
        final newYork = _convertTimezone(utc, 'New York');
        bool weekday(DateTime value) =>
            value.weekday >= DateTime.monday &&
            value.weekday <= DateTime.friday;
        final isTokyo = weekday(tokyo) && tokyo.hour >= 9 && tokyo.hour < 18;
        final isLondon =
            weekday(london) && london.hour >= 8 && london.hour < 17;
        final isNewYork =
            weekday(newYork) && newYork.hour >= 8 && newYork.hour < 17;
        Color? sessionColor;
        if (isLondon && isNewYork) {
          // Real London/New York overlap, including the DST transition weeks.
          sessionColor = _isMonochrome
              ? const Color(0x20888890)
              : (_isDeuteranopia
                    ? const Color(0x2031B7C8)
                    : const Color(0x1400E5FF));
        } else if (isTokyo && isLondon) {
          // Tokyo/London overlap (London 08:00-09:00 in winter).
          sessionColor = _isMonochrome
              ? const Color(0x247A7A84)
              : (_isDeuteranopia
                    ? const Color(0x24D5A000)
                    : const Color(0x18E040FB));
        } else if (isTokyo) {
          // Tokyo / Asian session
          sessionColor = _isMonochrome
              ? const Color(0x1477777D)
              : (_isDeuteranopia
                    ? const Color(0x1431B7C8)
                    : const Color(0x0A9C27B0));
        } else if (isLondon) {
          // London session
          sessionColor = _isMonochrome
              ? const Color(0x1A92929A)
              : (_isDeuteranopia
                    ? const Color(0x14FF8F00)
                    : const Color(0x0C2196F3));
        } else if (isNewYork) {
          // New York session
          sessionColor = _isMonochrome
              ? const Color(0x1466666E)
              : (_isDeuteranopia
                    ? const Color(0x14FF8F00)
                    : const Color(0x0CFF9800));
        }

        if (sessionColor != null) {
          final x = indexToX(i.toDouble());
          canvas.drawRect(
            Rect.fromLTWH(
              x - candleStep / 2,
              chartArea.top,
              candleStep,
              chartArea.height,
            ),
            Paint()..color = sessionColor,
          );
        }
      }
    }

    final gridPaint = Paint()
      ..color = _paletteGridColor
      ..strokeWidth = 0.8;

    // 5 Horizontal Price Grid Lines
    for (int i = 0; i <= 4; i++) {
      final y = chartArea.top + (chartArea.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(chartArea.right, y), gridPaint);
    }

    // Vertical Time Grid Lines (every ~80px)
    final double vStep = max(60.0, 80.0);
    final int vCount = (chartArea.width / vStep).floor();
    for (int i = 1; i <= vCount; i++) {
      final x = i * (chartArea.width / (vCount + 1));
      canvas.drawLine(Offset(x, 0), Offset(x, chartArea.bottom), gridPaint);
    }
  }

  void _drawCandlesticks(Canvas canvas) {
    Color bullColor;
    Color bearColor;
    bullColor = _paletteBullColor;
    bearColor = _paletteBearColor;

    final isHollow = candleType.toLowerCase().contains('hollow');
    final isLine = candleType.toLowerCase().contains('line');
    final isArea = candleType.toLowerCase().contains('area');
    final isHeikinAshi = candleType.toLowerCase().contains('heikin');

    final bullPaint = Paint()
      ..color = bullColor
      ..style = isHollow ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = isHollow ? 1.5 : 1.0;

    final bearPaint = Paint()
      ..color = bearColor
      ..style = PaintingStyle.fill;

    final wickPaint = Paint()
      ..strokeWidth = max(1.0, candleWidth * 0.15)
      ..style = PaintingStyle.stroke;

    // Viewport visible indices
    final visibleCount = chartArea.width / candleStep;
    final startIndex = max(0, (scrollOffset - visibleCount - 2).floor());
    final endIndex = min(candles.length, (scrollOffset + 2).ceil());

    if (isLine || isArea) {
      final linePath = Path();
      bool started = false;
      double firstX = 0.0;
      double lastX = 0.0;
      for (int i = startIndex; i < endIndex; i++) {
        final x = indexToX(i.toDouble());
        final y = priceToY(candles[i].close);
        if (!started) {
          linePath.moveTo(x, y);
          firstX = x;
          started = true;
        } else {
          linePath.lineTo(x, y);
        }
        lastX = x;
      }
      if (isArea && started) {
        final areaPath = Path.from(linePath);
        areaPath.lineTo(lastX, chartArea.bottom);
        areaPath.lineTo(firstX, chartArea.bottom);
        areaPath.close();

        final areaPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bullColor.withValues(alpha: 0.35),
              bullColor.withValues(alpha: 0.0),
            ],
          ).createShader(chartArea)
          ..style = PaintingStyle.fill;
        canvas.drawPath(areaPath, areaPaint);
      }
      final linePaint = Paint()
        ..color = bullColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawPath(linePath, linePaint);
      return;
    }

    List<BiquoteCandle> displayCandles = candles;
    if (isHeikinAshi && candles.isNotEmpty) {
      displayCandles = [];
      double prevHaOpen = candles.first.open;
      double prevHaClose = candles.first.close;
      for (int i = 0; i < candles.length; i++) {
        final c = candles[i];
        final haClose = (c.open + c.high + c.low + c.close) / 4.0;
        final haOpen = i == 0
            ? (c.open + c.close) / 2.0
            : (prevHaOpen + prevHaClose) / 2.0;
        final haHigh = max(c.high, max(haOpen, haClose));
        final haLow = min(c.low, min(haOpen, haClose));
        prevHaOpen = haOpen;
        prevHaClose = haClose;
        displayCandles.add(
          BiquoteCandle(
            openTime: c.openTime,
            open: haOpen,
            high: haHigh,
            low: haLow,
            close: haClose,
            tickVolume: c.tickVolume,
            isOpen: c.isOpen,
          ),
        );
      }
    }

    for (int i = startIndex; i < endIndex; i++) {
      final c = displayCandles[i];
      final x = indexToX(i.toDouble());
      final isBull = c.isBullish;
      final paint = isBull ? bullPaint : bearPaint;
      wickPaint.color = isBull ? bullColor : bearColor;

      final openY = priceToY(c.open);
      final closeY = priceToY(c.close);
      final highY = priceToY(c.high);
      final lowY = priceToY(c.low);

      // Wick
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), wickPaint);

      // Candle Body (ensure minimum 1px height for flat candles)
      final topY = min(openY, closeY);
      final bodyHeight = max(1.5, (openY - closeY).abs());
      final bodyRect = Rect.fromCenter(
        center: Offset(x, topY + bodyHeight / 2),
        width: candleWidth,
        height: bodyHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(1.5)),
        paint,
      );
    }
  }

  void _drawRealtimeBeacon(Canvas canvas) {
    if (candles.isEmpty || currentPrice <= 0) return;
    final lastIdx = candles.length - 1;
    final x = indexToX(lastIdx.toDouble());
    final y = priceToY(candles[lastIdx].close);

    if (x < 0 || x > chartArea.right + 50) return;

    final bullColor = isDark ? AppTheme.darkBullish : AppTheme.lightBullish;
    final bearColor = isDark ? AppTheme.darkBearish : AppTheme.lightBearish;
    final color = candles[lastIdx].isBullish ? bullColor : bearColor;

    // Outer pulsating halo
    final haloPaint = Paint()
      ..color = color.withValues(alpha: 0.35 * pulseValue)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 8.0 * pulseValue + 4.0, haloPaint);

    // Inner glowing core
    final corePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 3.5, corePaint);

    // Live horizontal dashed price line across chart to price scale (Matching Chart.dc.html)
    final liveDashedPaint = Paint()
      ..color = const Color(0xFF30D158).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    double liveStartX = 0;
    while (liveStartX < chartArea.right) {
      canvas.drawLine(
        Offset(liveStartX, y),
        Offset(liveStartX + 4, y),
        liveDashedPaint,
      );
      liveStartX += 8;
    }

    // Right live price badge (Matching Chart.dc.html)
    final liveBadgeRect = Rect.fromLTWH(chartArea.right + 2, y - 10, 46, 20);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        liveBadgeRect,
        topLeft: const Radius.circular(4),
        bottomLeft: const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF30D158),
    );
    final liveTp = TextPainter(
      text: TextSpan(
        text: currentPrice > 0
            ? currentPrice.toStringAsFixed(precision > 4 ? 4 : precision)
            : candles[lastIdx].close.toStringAsFixed(4),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    liveTp.paint(
      canvas,
      Offset(
        liveBadgeRect.left + (liveBadgeRect.width - liveTp.width) / 2,
        liveBadgeRect.top + (liveBadgeRect.height - liveTp.height) / 2,
      ),
    );
  }

  void _drawAlertLines(Canvas canvas) {
    for (final a in alerts) {
      if (!a.isActive) continue;
      final y = priceToY(a.targetPrice);
      if (y < 0 || y > chartArea.bottom) continue;

      // Exact alert line styling from Chart.dc.html: 1.5px dashed #FF9F0A
      final alertPaint = Paint()
        ..color = _paletteAccent.withValues(alpha: 0.9)
        ..strokeWidth = 1.5;

      double startX = 0;
      while (startX < chartArea.right) {
        canvas.drawLine(Offset(startX, y), Offset(startX + 5, y), alertPaint);
        startX += 9;
      }

      // Exact alert left tag from Chart.dc.html: pinned to left 0, height 22, border-radius: 0 11px 11px 0, #FF9F0A
      final labelText = a.targetPrice.toStringAsFixed(precision);
      final tp = TextPainter(
        text: TextSpan(
          text: '🔔 $labelText',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeWidth = tp.width + 14;
      final badgeRect = Rect.fromLTWH(0, y - 11, badgeWidth, 22);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          badgeRect,
          topRight: const Radius.circular(11),
          bottomRight: const Radius.circular(11),
        ),
        Paint()..color = _paletteAccent,
      );
      tp.paint(canvas, Offset(6, y - tp.height / 2));
    }
  }

  void _drawSignalOverlay(Canvas canvas) {
    if (signalOverlay == null) return;
    final sig = signalOverlay!;

    // 1. Entry Price Line (Emerald Green)
    if (sig.entryPrice > 0) {
      _drawDashedSignalLine(
        canvas: canvas,
        price: sig.entryPrice,
        color: const Color(0xFF00E676),
        label: 'ENTRY',
      );
    }

    // 2. Stop Loss Line (Crimson Red)
    if (sig.stopLoss > 0) {
      _drawDashedSignalLine(
        canvas: canvas,
        price: sig.stopLoss,
        color: const Color(0xFFFF5252),
        label: 'SL',
      );
    }

    // 3. Take Profit Line (Accent Blue)
    if (sig.takeProfit > 0) {
      _drawDashedSignalLine(
        canvas: canvas,
        price: sig.takeProfit,
        color: const Color(0xFF448AFF),
        label: 'TP',
      );
    }
  }

  void _drawDashedSignalLine({
    required Canvas canvas,
    required double price,
    required Color color,
    required String label,
  }) {
    final y = priceToY(price);
    if (y < 0 || y > chartArea.bottom) return;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    double startX = 0;
    while (startX < chartArea.right) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(startX + dashWidth, y),
        linePaint,
      );
      startX += dashWidth + dashSpace;
    }

    // Pill badge on the right edge of chart area
    final badgeRect = Rect.fromLTWH(chartArea.right - 58, y - 9, 54, 18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = color,
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        badgeRect.left + (badgeRect.width - textPainter.width) / 2,
        badgeRect.top + 2.5,
      ),
    );
  }

  void _drawAllUserDrawings(Canvas canvas) {
    for (final d in drawings) {
      _drawSingleDrawing(canvas, d, isSelected: d == selectedDrawing);
    }
    if (inProgressDrawing != null) {
      _drawSingleDrawing(canvas, inProgressDrawing!, isSelected: true);
    }
  }

  void _drawSingleDrawing(
    Canvas canvas,
    ChartDrawing d, {
    bool isSelected = false,
  }) {
    if (d.points.isEmpty) return;

    final paint = Paint()
      ..color = d.color
      ..strokeWidth = d.strokeWidth
      ..style = PaintingStyle.stroke;

    switch (d.tool) {
      case DrawingTool.horizontalLine:
        final y = priceToY(d.points.first.price);
        final hasActiveAlert =
            d.hasAlert || alerts.any((a) => a.drawingId == d.id && a.isActive);

        // If alert is attached, paint a subtle golden alert halo
        if (hasActiveAlert) {
          final glowPaint = Paint()
            ..color = const Color(0xFFFF9100).withValues(alpha: 0.35)
            ..strokeWidth = d.strokeWidth + 3.5
            ..style = PaintingStyle.stroke;
          canvas.drawLine(Offset(0, y), Offset(chartArea.right, y), glowPaint);
        }

        canvas.drawLine(Offset(0, y), Offset(chartArea.right, y), paint);
        if (isSelected) {
          _drawHandle(canvas, Offset(chartArea.width * 0.5, y), d.color);
        }

        // Draw the price scale badge for horizontal lines
        final badgeWidth = hasActiveAlert ? 76.0 : 54.0;
        final badgeRect = Rect.fromLTWH(
          chartArea.right - (badgeWidth + 4),
          y - 9,
          badgeWidth,
          18,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
          Paint()..color = hasActiveAlert ? const Color(0xFFFF9100) : d.color,
        );
        final labelText = hasActiveAlert
            ? '🔔 ${d.points.first.price.toStringAsFixed(precision)}'
            : d.points.first.price.toStringAsFixed(precision);
        final tp = TextPainter(
          text: TextSpan(
            text: labelText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            badgeRect.left + (badgeRect.width - tp.width) / 2,
            badgeRect.top + 2.5,
          ),
        );
        break;

      case DrawingTool.trendline:
        if (d.points.length < 2) return;
        final p1 = _projectPoint(d.points[0]);
        final p2 = _projectPoint(d.points[1]);
        canvas.drawLine(p1, p2, paint);
        if (isSelected) {
          _drawHandle(canvas, p1, d.color);
          _drawHandle(canvas, p2, d.color);
        }
        break;

      case DrawingTool.rectangle:
        if (d.points.length < 2) return;
        final p1 = _projectPoint(d.points[0]);
        final p2 = _projectPoint(d.points[1]);
        final rect = Rect.fromPoints(p1, p2);

        // Shaded fill matching Image 2
        final fillPaint = Paint()
          ..color = d.color.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, fillPaint);

        // Dashed border matching Image 2: 1.5px dashed
        _drawDashedRect(
          canvas,
          rect,
          Paint()
            ..color = d.color.withValues(alpha: 0.70)
            ..strokeWidth = 1.5,
        );

        if (isSelected) {
          _drawHandle(canvas, rect.topLeft, d.color);
          _drawHandle(canvas, rect.bottomRight, d.color);
        }
        break;

      case DrawingTool.fibonacci:
        if (d.points.length < 2) return;
        final p1 = _projectPoint(d.points[0]);
        final p2 = _projectPoint(d.points[1]);
        final highPrice = max(d.points[0].price, d.points[1].price);
        final lowPrice = min(d.points[0].price, d.points[1].price);
        final span = highPrice - lowPrice;

        final levels = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];
        final leftX = min(p1.dx, p2.dx) - 20;
        final rightX = max(p1.dx, p2.dx) + 40;

        // Golden pocket shading (0.382 - 0.618)
        final y382 = priceToY(highPrice - span * 0.382);
        final y618 = priceToY(highPrice - span * 0.618);
        canvas.drawRect(
          Rect.fromLTRB(leftX, min(y382, y618), rightX, max(y382, y618)),
          Paint()..color = const Color(0xFFFFD700).withValues(alpha: 0.15),
        );

        for (final lvl in levels) {
          final levelPrice = highPrice - span * lvl;
          final y = priceToY(levelPrice);
          final isGolden = lvl == 0.5 || lvl == 0.618;

          final fibLinePaint = Paint()
            ..color = isGolden
                ? const Color(0xFFFFD700)
                : d.color.withValues(alpha: 0.7)
            ..strokeWidth = isGolden ? 1.5 : 1.0;

          canvas.drawLine(Offset(leftX, y), Offset(rightX, y), fibLinePaint);

          final tp = TextPainter(
            text: TextSpan(
              text:
                  '${(lvl * 100).toStringAsFixed(1)}% (${levelPrice.toStringAsFixed(precision)})',
              style: TextStyle(
                color: isGolden ? const Color(0xFFFFD700) : d.color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(leftX + 4, y - 12));
        }

        if (isSelected) {
          _drawHandle(canvas, p1, d.color);
          _drawHandle(canvas, p2, d.color);
        }
        break;

      case DrawingTool.ruler:
        if (d.points.length < 2) return;
        final p1 = _projectPoint(d.points[0]);
        final p2 = _projectPoint(d.points[1]);

        final rect = Rect.fromPoints(p1, p2);
        canvas.drawRect(
          rect,
          Paint()
            ..color =
                (d.points[1].price >= d.points[0].price
                        ? Colors.green
                        : Colors.red)
                    .withValues(alpha: 0.15),
        );
        canvas.drawLine(p1, p2, paint..strokeWidth = 1.5);

        // Pip calculation
        final priceDiff = d.points[1].price - d.points[0].price;
        final double multiplier = precision == 3
            ? 100.0
            : (precision == 2 ? 10.0 : 10000.0);
        final pips = (priceDiff * multiplier).abs();
        final pct = (priceDiff / d.points[0].price) * 100.0;
        final idx1 = findNearestCandleIndex(d.points[0].time);
        final idx2 = findNearestCandleIndex(d.points[1].time);
        final bars = (idx2 - idx1).abs();

        final label =
            '${priceDiff >= 0 ? '+' : ''}${pips.toStringAsFixed(1)} pips (${pct.toStringAsFixed(2)}%) • $bars bars';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final badgeRect = Rect.fromLTWH(
          p2.dx - 10,
          p2.dy - 22,
          tp.width + 12,
          20,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
          Paint()..color = Colors.black.withValues(alpha: 0.85),
        );
        tp.paint(canvas, Offset(badgeRect.left + 6, badgeRect.top + 3));

        if (isSelected) {
          _drawHandle(canvas, p1, d.color);
          _drawHandle(canvas, p2, d.color);
        }
        break;

      case DrawingTool.ray:
        if (d.points.length < 2) return;
        final p1 = _projectPoint(d.points[0]);
        final p2 = _projectPoint(d.points[1]);
        final dx = p2.dx - p1.dx;
        final dy = p2.dy - p1.dy;
        Offset farPoint;
        if (dx.abs() > 0.001) {
          final targetX = dx > 0 ? chartArea.right : chartArea.left;
          final t = (targetX - p1.dx) / dx;
          farPoint = Offset(targetX, p1.dy + dy * t);
        } else {
          farPoint = Offset(p1.dx, dy >= 0 ? chartArea.bottom : chartArea.top);
        }
        canvas.drawLine(p1, farPoint, paint);
        if (isSelected) {
          _drawHandle(canvas, p1, d.color);
          _drawHandle(canvas, p2, d.color);
        }
        break;

      case DrawingTool.verticalLine:
        if (d.points.isEmpty) return;
        final p1 = _projectPoint(d.points[0]);
        canvas.drawLine(
          Offset(p1.dx, chartArea.top),
          Offset(p1.dx, chartArea.bottom),
          paint,
        );
        if (isSelected) {
          _drawHandle(
            canvas,
            Offset(p1.dx, (chartArea.top + chartArea.bottom) * 0.5),
            d.color,
          );
        }
        break;

      case DrawingTool.none:
        break;
    }
  }

  Offset _projectPoint(ChartPoint pt) {
    final idx = findNearestCandleIndex(pt.time);
    final x = indexToX(idx.toDouble());
    final y = priceToY(pt.price);
    return Offset(x, y);
  }

  void _drawHandle(Canvas canvas, Offset pos, Color color) {
    // Exact .hd styling from ChartTools.dc.html: 20px circle, black fill, 2.5px colored border
    canvas.drawCircle(
      pos,
      10.0,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      pos,
      10.0,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    // Top
    double x = rect.left;
    while (x < rect.right) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(min(x + 4, rect.right), rect.top),
        paint,
      );
      x += 7;
    }
    // Bottom
    x = rect.left;
    while (x < rect.right) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(min(x + 4, rect.right), rect.bottom),
        paint,
      );
      x += 7;
    }
    // Left
    double y = rect.top;
    while (y < rect.bottom) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.left, min(y + 4, rect.bottom)),
        paint,
      );
      y += 7;
    }
    // Right
    y = rect.top;
    while (y < rect.bottom) {
      canvas.drawLine(
        Offset(rect.right, y),
        Offset(rect.right, min(y + 4, rect.bottom)),
        paint,
      );
      y += 7;
    }
  }

  void _drawPriceScaleLabels(Canvas canvas, Size size) {
    final textColor = _paletteTextColor;
    final textStyle = AppTheme.mono(
      color: textColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );

    // 5 Price labels on right scale
    for (int i = 0; i <= 4; i++) {
      final y = chartArea.top + (chartArea.height / 4) * i;
      final price =
          minPrice + ((chartArea.bottom - y) / chartArea.height) * priceRange;

      final tp = TextPainter(
        text: TextSpan(
          text: price.toStringAsFixed(precision),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartArea.right + 8, y - 6));
    }

    // Live Price Banner in Price Scale (Matching Chart.dc.html line 82: background #30d158 / #ff453a, color #000, 10px 700 tabular)
    if (currentPrice > 0) {
      final y = priceToY(currentPrice);
      if (y >= chartArea.top && y <= chartArea.bottom) {
        final badgeRect = Rect.fromLTWH(
          chartArea.right + 2,
          y - 10,
          size.width - chartArea.right - 4,
          20,
        );
        final isBull = candles.isNotEmpty
            ? (candles.last.close >= candles.last.open)
            : true;
        final liveColor = isBull ? _paletteBullColor : _paletteBearColor;

        canvas.drawRRect(
          RRect.fromRectAndCorners(
            badgeRect,
            topLeft: const Radius.circular(4),
            bottomLeft: const Radius.circular(4),
          ),
          Paint()..color = liveColor,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: currentPrice.toStringAsFixed(precision),
            style: AppTheme.mono(
              color: Colors.black,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            badgeRect.left + (badgeRect.width - tp.width) / 2,
            badgeRect.top + 3.0,
          ),
        );

        // Sub-second Bar Countdown Timer Badge
        if (showCountdown && candles.isNotEmpty) {
          final lastCandle = candles.last;
          final now = DateTime.now();
          int intervalSeconds = 3600;
          final iv = interval.toLowerCase();
          if (iv.contains('1m')) {
            intervalSeconds = 60;
          } else if (iv.contains('5m')) {
            intervalSeconds = 300;
          } else if (iv.contains('15m')) {
            intervalSeconds = 900;
          } else if (iv.contains('30m')) {
            intervalSeconds = 1800;
          } else if (iv.contains('1h')) {
            intervalSeconds = 3600;
          } else if (iv.contains('4h')) {
            intervalSeconds = 14400;
          } else if (iv.contains('1d')) {
            intervalSeconds = 86400;
          }

          final elapsed = now.difference(lastCandle.openTime).inSeconds;
          final remaining = max(
            0,
            intervalSeconds - (elapsed % intervalSeconds),
          );
          final remMin = remaining ~/ 60;
          final remSec = remaining % 60;
          final remStr =
              '${remMin.toString().padLeft(2, '0')}:${remSec.toString().padLeft(2, '0')}';

          if (y <= chartArea.bottom - 22) {
            final cdRect = Rect.fromLTWH(
              chartArea.right + 2,
              y + 12,
              size.width - chartArea.right - 4,
              16,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(cdRect, const Radius.circular(3)),
              Paint()..color = const Color(0xFF2C2C2E),
            );
            final tpCd = TextPainter(
              text: TextSpan(
                text: '⏳ $remStr',
                style: AppTheme.mono(
                  color: const Color(0xFFFFD60A),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tpCd.paint(
              canvas,
              Offset(
                cdRect.left + (cdRect.width - tpCd.width) / 2,
                cdRect.top + 2.5,
              ),
            );
          }
        }
      }
    }

    // AI Signal Price Scale Badges (Entry / SL / TP)
    if (signalOverlay != null && signalOverlay!.hasValidTradeSetup) {
      _drawSignalPriceScaleBadges(canvas, size);
    }
  }

  void _drawScaleBadge(
    Canvas canvas,
    Size size,
    double price,
    Color color,
    String prefix,
  ) {
    if (price <= 0) return;
    final y = priceToY(price);
    if (y < chartArea.top || y > chartArea.bottom) return;

    final badgeRect = Rect.fromLTWH(
      chartArea.right + 2,
      y - 10,
      size.width - chartArea.right - 4,
      20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = color,
    );

    final text = prefix.isNotEmpty
        ? '$prefix ${price.toStringAsFixed(precision)}'
        : price.toStringAsFixed(precision);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTheme.mono(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(badgeRect.left + 3, badgeRect.top + 3.5));
  }

  void _drawSignalPriceScaleBadges(Canvas canvas, Size size) {
    if (signalOverlay == null) return;
    final sig = signalOverlay!;

    _drawScaleBadge(canvas, size, sig.entryPrice, const Color(0xFF00E676), 'E');
    _drawScaleBadge(canvas, size, sig.stopLoss, const Color(0xFFFF5252), 'SL');
    _drawScaleBadge(
      canvas,
      size,
      sig.takeProfit,
      const Color(0xFF448AFF),
      'TP',
    );
  }

  void _drawTimeAxisLabels(Canvas canvas, Size size) {
    final textStyle = AppTheme.mono(
      color: _paletteTextColor.withValues(alpha: 0.82),
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
    );

    final double vStep = 90.0;
    final int count = (chartArea.width / vStep).floor();
    for (int i = 1; i <= count; i++) {
      final x = i * (chartArea.width / (count + 1));
      final rawIndex = scrollOffset - (chartArea.width - x) / candleStep;
      final idx = rawIndex.round().clamp(0, candles.length - 1);
      final date = _toTradingTimezone(candles[idx].openTime);

      final text = interval == '1D' || interval == '1W'
          ? DateFormat('MM/dd').format(date)
          : DateFormat('HH:mm').format(date);

      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartArea.bottom + 6));
    }
  }

  DateTime _toTradingTimezone(DateTime input) {
    return _convertTimezone(input.toUtc(), tradingTimezone);
  }

  DateTime _convertTimezone(DateTime utcInput, String timezone) {
    final utc = utcInput.toUtc();
    if (timezone.contains('Local Device')) return utc.toLocal();
    if (timezone.contains('Tokyo')) return utc.add(const Duration(hours: 9));
    if (timezone.contains('New York')) {
      // US DST: 02:00 local on the second Sunday in March through
      // 02:00 local on the first Sunday in November.
      final marchFirst = DateTime.utc(utc.year, 3, 1);
      final secondSundayMarch = 1 + ((7 - marchFirst.weekday) % 7) + 7;
      final novemberFirst = DateTime.utc(utc.year, 11, 1);
      final firstSundayNovember = 1 + ((7 - novemberFirst.weekday) % 7);
      final dstStartUtc = DateTime.utc(utc.year, 3, secondSundayMarch, 7);
      final dstEndUtc = DateTime.utc(utc.year, 11, firstSundayNovember, 6);
      final isDst = !utc.isBefore(dstStartUtc) && utc.isBefore(dstEndUtc);
      return utc.add(Duration(hours: isDst ? -4 : -5));
    }
    if (timezone.contains('London')) {
      // UK DST runs from 01:00 UTC on the last Sunday in March to
      // 01:00 UTC on the last Sunday in October.
      final marchLast = DateTime.utc(utc.year, 4, 0);
      final octoberLast = DateTime.utc(utc.year, 11, 0);
      final dstStartUtc = DateTime.utc(
        utc.year,
        3,
        marchLast.day - ((marchLast.weekday - DateTime.sunday) % 7),
        1,
      );
      final dstEndUtc = DateTime.utc(
        utc.year,
        10,
        octoberLast.day - ((octoberLast.weekday - DateTime.sunday) % 7),
        1,
      );
      final isDst = !utc.isBefore(dstStartUtc) && utc.isBefore(dstEndUtc);
      return utc.add(Duration(hours: isDst ? 1 : 0));
    }
    return utc;
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    double posX;
    double posY;

    if (crosshairCandleIndex != null &&
        crosshairCandleIndex! >= 0 &&
        crosshairCandleIndex! < candles.length) {
      posX = indexToX(crosshairCandleIndex!.toDouble());
    } else if (crosshairTime != null) {
      final idx = findNearestCandleIndex(crosshairTime!);
      posX = indexToX(idx.toDouble());
    } else if (crosshairPosition != null) {
      posX = crosshairPosition!.dx;
    } else {
      posX = chartArea.width / 2;
    }

    if (crosshairPrice != null) {
      posY = priceToY(crosshairPrice!);
    } else if (crosshairPosition != null) {
      posY = crosshairPosition!.dy;
    } else {
      posY = chartArea.height / 2;
    }

    final pos = Offset(posX, posY);

    // Exact Crosshair styling from ChartTools.dc.html:
    // stroke="rgba(255,255,255,.55)" stroke-dasharray="4 4"
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.0;

    // Horizontal dashed crosshair line
    if (pos.dy >= chartArea.top && pos.dy <= chartArea.bottom) {
      double startX = 0;
      while (startX < chartArea.right) {
        canvas.drawLine(
          Offset(startX, pos.dy),
          Offset(startX + 4, pos.dy),
          crossPaint,
        );
        startX += 8;
      }
    }

    // Vertical dashed crosshair line
    if (pos.dx >= chartArea.left && pos.dx <= chartArea.right) {
      double startY = 0;
      while (startY < chartArea.bottom) {
        canvas.drawLine(
          Offset(pos.dx, startY),
          Offset(pos.dx, startY + 4),
          crossPaint,
        );
        startY += 8;
      }
    }

    // Center circular reticle:
    // Outer: 44x44 (radius 22), 1.5px white border, rgba(255,255,255,0.08) fill
    canvas.drawCircle(
      pos,
      22.0,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      pos,
      22.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Center pip: 6x6 (radius 3) solid white dot
    canvas.drawCircle(
      pos,
      3.0,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Price tag on right scale: solid white badge with black text (Matching ChartTools.dc.html line 67)
    final activePrice = crosshairPrice ?? hoverPrice;
    if (activePrice != null &&
        pos.dy >= chartArea.top &&
        pos.dy <= chartArea.bottom) {
      final priceRect = Rect.fromLTWH(
        chartArea.right + 2,
        pos.dy - 10,
        size.width - chartArea.right - 4,
        20,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          priceRect,
          topLeft: const Radius.circular(4),
          bottomLeft: const Radius.circular(4),
        ),
        Paint()..color = Colors.white,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: activePrice.toStringAsFixed(precision),
          style: AppTheme.mono(
            color: Colors.black,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          priceRect.left + (priceRect.width - tp.width) / 2,
          priceRect.top + 3.0,
        ),
      );
    }

    // Time tag on bottom scale: solid white badge with black text
    final activeCandle =
        (crosshairCandleIndex != null &&
            crosshairCandleIndex! >= 0 &&
            crosshairCandleIndex! < candles.length)
        ? candles[crosshairCandleIndex!]
        : hoverCandle;
    if (activeCandle != null &&
        pos.dx >= chartArea.left &&
        pos.dx <= chartArea.right) {
      final dateText = DateFormat('dd MMM · HH:mm')
          .format(activeCandle.openTime);
      final tp = TextPainter(
        text: TextSpan(
          text: dateText,
          style: AppTheme.mono(
            color: Colors.black,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final timeRect = Rect.fromCenter(
        center: Offset(pos.dx, chartArea.bottom + 12),
        width: tp.width + 12,
        height: 20,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(timeRect, const Radius.circular(4)),
        Paint()..color = Colors.white,
      );
      tp.paint(canvas, Offset(timeRect.left + 6, timeRect.top + 3.5));
    }
  }

  // ─── INDICATOR OVERLAY RENDERING ───────────────────────────────────────────

  /// Draws EMA, SMA, and Bollinger Bands overlaid on the candlestick price chart.
  void _drawIndicatorOverlays(Canvas canvas) {
    final visibleCount = chartArea.width / candleStep;
    final startIndex = max(0, (scrollOffset - visibleCount - 2).floor());
    final endIndex = min(candles.length, (scrollOffset + 2).ceil());

    for (final entry in indicatorResults.entries) {
      final result = entry.value;
      final config = result.config;
      if (config.type.placement != IndicatorPlacement.overlay) continue;
      if (!config.isVisible) continue;

      switch (config.type) {
        case IndicatorType.ema:
        case IndicatorType.sma:
          _drawLineSeries(
            canvas,
            result.primary,
            config.getColor('main', const Color(0xFF00E5FF)),
            config.lineWidth,
            startIndex,
            endIndex,
          );
          break;

        case IndicatorType.bollingerBands:
          final upperColor = config.getColor('upper', const Color(0xFF00E5FF));
          final lowerColor = config.getColor('lower', const Color(0xFF00E5FF));
          final basisColor = config.getColor('basis', const Color(0xFFFF9800));
          final fillColor = config.getColor('fill', const Color(0x1A00E5FF));

          // Draw fill between upper and lower
          _drawBandFill(
            canvas,
            result.secondary,
            result.tertiary,
            fillColor,
            startIndex,
            endIndex,
          );
          // Upper band
          if (result.secondary != null) {
            _drawLineSeries(
              canvas,
              result.secondary!,
              upperColor,
              config.lineWidth,
              startIndex,
              endIndex,
            );
          }
          // Lower band
          if (result.tertiary != null) {
            _drawLineSeries(
              canvas,
              result.tertiary!,
              lowerColor,
              config.lineWidth,
              startIndex,
              endIndex,
            );
          }
          // Basis (SMA)
          _drawLineSeries(
            canvas,
            result.primary,
            basisColor,
            config.lineWidth,
            startIndex,
            endIndex,
          );
          break;

        case IndicatorType.supertrend:
          final bullColor = config.getColor('bull', const Color(0xFF30D158));
          final bearColor = config.getColor('bear', const Color(0xFFFF453A));
          _drawSupertrendSeries(
            canvas,
            result.primary,
            result.secondary,
            bullColor,
            bearColor,
            config.lineWidth,
            startIndex,
            endIndex,
          );
          break;

        default:
          break;
      }
    }
  }

  /// Draw a price series line (connecting non-null data points)
  void _drawLineSeries(
    Canvas canvas,
    List<double?> values,
    Color color,
    double strokeWidth,
    int startIndex,
    int endIndex,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool started = false;

    for (
      int i = max(0, startIndex - 1);
      i <= min(candles.length - 1, endIndex + 1);
      i++
    ) {
      if (i >= values.length) break;
      final v = values[i];
      if (v == null) {
        started = false;
        continue;
      }
      final x = indexToX(i.toDouble());
      final y = priceToY(v);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  /// Draw Supertrend series (green when bullish, red when bearish)
  void _drawSupertrendSeries(
    Canvas canvas,
    List<double?> values,
    List<double?>? directions,
    Color bullColor,
    Color bearColor,
    double strokeWidth,
    int startIndex,
    int endIndex,
  ) {
    if (values.isEmpty) return;
    final bullPaint = Paint()
      ..color = bullColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bearPaint = Paint()
      ..color = bearColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final from = max(0, startIndex - 1);
    final to = min(candles.length - 1, endIndex + 1);

    for (int i = from; i < to; i++) {
      if (i + 1 >= values.length) break;
      final v1 = values[i];
      final v2 = values[i + 1];
      if (v1 == null || v2 == null) continue;

      final dir =
          (directions != null &&
              i + 1 < directions.length &&
              directions[i + 1] != null)
          ? directions[i + 1]!
          : 1.0;
      final paint = dir >= 0 ? bullPaint : bearPaint;

      final x1 = indexToX(i.toDouble());
      final y1 = priceToY(v1);
      final x2 = indexToX((i + 1).toDouble());
      final y2 = priceToY(v2);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  /// Draw filled band between upper and lower series
  void _drawBandFill(
    Canvas canvas,
    List<double?>? upper,
    List<double?>? lower,
    Color fillColor,
    int startIndex,
    int endIndex,
  ) {
    if (upper == null || lower == null) return;

    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    bool started = false;

    final idxFrom = max(0, startIndex - 1);
    final idxTo = min(candles.length - 1, endIndex + 1);

    // Build upper path forward
    for (int i = idxFrom; i <= idxTo; i++) {
      if (i >= upper.length || i >= lower.length) break;
      final u = upper[i];
      if (u == null) {
        started = false;
        continue;
      }
      final x = indexToX(i.toDouble());
      final y = priceToY(u);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    // Close backward along lower band
    for (int i = idxTo; i >= idxFrom; i--) {
      if (i >= lower.length) continue;
      final l = lower[i];
      if (l == null) continue;
      path.lineTo(indexToX(i.toDouble()), priceToY(l));
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // ─── OSCILLATOR SUB-PANE RENDERING ─────────────────────────────────────────

  void _drawSubPane(Canvas canvas, Size size) {
    const double sep = 1.0;
    for (int i = 0; i < subPaneIndicators.length; i++) {
      final config = subPaneIndicators[i];
      final result = indicatorResults[config.id];
      if (result == null) continue;

      // Each sub-pane starts below the time axis (24px below main chart area)
      final currentSubPaneTop =
          chartArea.bottom + 24.0 + (i * (subPaneHeight + sep)) + sep;
      final subPaneRect = Rect.fromLTWH(
        0,
        currentSubPaneTop,
        chartArea.width,
        subPaneHeight,
      );

      // Background
      final bgPaint = Paint()
        ..color = (isDark ? Colors.black : const Color(0xFFF5F5F5));
      canvas.drawRect(subPaneRect, bgPaint);

      // Separator line
      canvas.drawLine(
        Offset(0, currentSubPaneTop),
        Offset(chartArea.width, currentSubPaneTop),
        Paint()
          ..color =
              (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppTheme.lightBorder)
                  .withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );

      _drawSubPaneGrid(canvas, subPaneRect, config);

      switch (config.type) {
        case IndicatorType.rsi:
        case IndicatorType.stochastic:
          _drawSubPaneOscillatorLines(canvas, subPaneRect, result, config);
          _drawSubPaneLabels(canvas, subPaneRect, size, config, result);
          break;
        case IndicatorType.macd:
          _drawSubPaneMacd(canvas, subPaneRect, result, config);
          _drawSubPaneLabels(canvas, subPaneRect, size, config, result);
          break;
        default:
          break;
      }
    }
  }

  void _drawSubPaneGrid(
    Canvas canvas,
    Rect subPaneRect,
    IndicatorConfig config,
  ) {
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF16181D) : const Color(0xFFE5E7EB)
      ..strokeWidth = 0.8;

    // Horizontal guide lines at overbought / midpoint / oversold
    final double high = (config.type == IndicatorType.stochastic)
        ? config.getDouble('overbought', 80.0)
        : (config.type == IndicatorType.rsi
              ? config.getDouble('overbought', 70.0)
              : 0.0);
    final double low = (config.type == IndicatorType.stochastic)
        ? config.getDouble('oversold', 20.0)
        : (config.type == IndicatorType.rsi
              ? config.getDouble('oversold', 30.0)
              : 0.0);
    final double range = config.type == IndicatorType.macd ? 1.0 : 100.0;

    if (config.type != IndicatorType.macd) {
      // Overbought line
      final yHigh = subPaneRect.bottom - (high / range) * subPaneRect.height;
      final yLow = subPaneRect.bottom - (low / range) * subPaneRect.height;
      final yMid = subPaneRect.bottom - 0.5 * subPaneRect.height;

      // Shaded band between oversold and overbought
      final upperColor = config.getColor('upper', const Color(0xFFEF5350));
      final lowerColor = config.getColor('lower', const Color(0xFF26A69A));
      final bandFill = config.getColor('bandFill', const Color(0x1F7E57C2));

      canvas.drawRect(
        Rect.fromLTRB(0, yHigh, subPaneRect.width, yLow),
        Paint()..color = bandFill,
      );

      // Overbought dashed line
      _drawDashedLine(
        canvas,
        Offset(0, yHigh),
        Offset(subPaneRect.width, yHigh),
        upperColor.withValues(alpha: 0.7),
        1.2,
      );

      // Oversold dashed line
      _drawDashedLine(
        canvas,
        Offset(0, yLow),
        Offset(subPaneRect.width, yLow),
        lowerColor.withValues(alpha: 0.7),
        1.2,
      );

      // Midpoint guide
      _drawDashedLine(
        canvas,
        Offset(0, yMid),
        Offset(subPaneRect.width, yMid),
        gridPaint.color,
        1.0,
      );
    } else {
      // Zero line for MACD
      final y = subPaneRect.bottom - 0.5 * subPaneRect.height;
      _drawDashedLine(
        canvas,
        Offset(0, y),
        Offset(subPaneRect.width, y),
        (isDark ? const Color(0xFF24262B) : Colors.black26),
        1.0,
      );
    }

    // Outer border
    canvas.drawLine(
      Offset(0, subPaneRect.top),
      Offset(subPaneRect.width, subPaneRect.top),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, subPaneRect.bottom),
      Offset(subPaneRect.width, subPaneRect.bottom),
      gridPaint,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    double dist = 0;
    final total = (end - start).distance;
    final dir = (end - start) / total;
    while (dist < total) {
      final from = start + dir * dist;
      final to = start + dir * (dist + 4).clamp(0, total);
      canvas.drawLine(from, to, paint);
      dist += 8;
    }
  }

  void _drawSubPaneOscillatorLines(
    Canvas canvas,
    Rect subPaneRect,
    IndicatorCalculationResult result,
    IndicatorConfig config,
  ) {
    canvas.save();
    canvas.clipRect(subPaneRect);

    final visibleCount = chartArea.width / candleStep;
    final startIndex = max(0, (scrollOffset - visibleCount - 2).floor());
    final endIndex = min(candles.length, (scrollOffset + 2).ceil());

    // Normalise value (0-100) → Y in sub-pane
    double toSubY(double v) =>
        subPaneRect.bottom - (v.clamp(0, 100) / 100.0) * subPaneRect.height;

    void drawSeries(List<double?> values, Color color, double sw) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      bool started = false;
      for (
        int i = max(0, startIndex - 1);
        i <= min(candles.length - 1, endIndex + 1);
        i++
      ) {
        if (i >= values.length) break;
        final v = values[i];
        if (v == null) {
          started = false;
          continue;
        }
        final x = indexToX(i.toDouble());
        final y = toSubY(v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    final primaryColor = config.type == IndicatorType.stochastic
        ? config.getColor('k', const Color(0xFF2196F3))
        : config.getColor('main', const Color(0xFFBF5AF2));
    drawSeries(result.primary, primaryColor, config.lineWidth);

    // Secondary line (Stoch %D)
    if (result.secondary != null) {
      final dColor = config.getColor('d', const Color(0xFFFF9800));
      drawSeries(result.secondary!, dColor, config.lineWidth * 0.85);
    }

    canvas.restore();
  }

  void _drawSubPaneMacd(
    Canvas canvas,
    Rect subPaneRect,
    IndicatorCalculationResult result,
    IndicatorConfig config,
  ) {
    canvas.save();
    canvas.clipRect(subPaneRect);

    final visibleCount = chartArea.width / candleStep;
    final startIndex = max(0, (scrollOffset - visibleCount - 2).floor());
    final endIndex = min(candles.length, (scrollOffset + 2).ceil());

    // Auto-scale MACD to visible range
    double macdMin = 0, macdMax = 0;
    for (int i = max(0, startIndex); i < min(candles.length, endIndex); i++) {
      if (result.histogram != null &&
          i < result.histogram!.length &&
          result.histogram![i] != null) {
        final h = result.histogram![i]!;
        if (h < macdMin) macdMin = h;
        if (h > macdMax) macdMax = h;
      }
      if (i < result.primary.length && result.primary[i] != null) {
        final m = result.primary[i]!;
        if (m < macdMin) macdMin = m;
        if (m > macdMax) macdMax = m;
      }
    }
    final macdRange = (macdMax - macdMin).abs();
    final paddedRange = macdRange == 0 ? 0.001 : macdRange * 1.2;
    final macdCenter = (macdMin + macdMax) / 2;

    double toSubY(double v) {
      final ratio = (v - (macdCenter - paddedRange / 2)) / paddedRange;
      return subPaneRect.bottom - ratio.clamp(0.0, 1.0) * subPaneRect.height;
    }

    final histUpColor = config.getColor('histUp', const Color(0xFF26A69A));
    final histDownColor = config.getColor('histDown', const Color(0xFFEF5350));
    final macdColor = config.getColor('macd', const Color(0xFF2962FF));
    final signalColor = config.getColor('signal', const Color(0xFFFF6D00));

    // Zero line y
    final zeroY = toSubY(0);

    // Draw histogram bars
    if (result.histogram != null) {
      for (
        int i = max(0, startIndex);
        i < min(candles.length, endIndex + 1);
        i++
      ) {
        if (i >= result.histogram!.length) break;
        final h = result.histogram![i];
        if (h == null) continue;
        final x = indexToX(i.toDouble());
        final y = toSubY(h);

        // Determine bar color based on expansion/contraction
        Color barColor;
        if (h >= 0) {
          final prev = i > 0 && i - 1 < result.histogram!.length
              ? result.histogram![i - 1]
              : null;
          barColor = (prev != null && h >= prev)
              ? histUpColor
              : histUpColor.withValues(alpha: 0.55);
        } else {
          final prev = i > 0 && i - 1 < result.histogram!.length
              ? result.histogram![i - 1]
              : null;
          barColor = (prev != null && h <= prev)
              ? histDownColor
              : histDownColor.withValues(alpha: 0.55);
        }

        final barWidth = max(1.0, candleWidth * 0.8);
        canvas.drawRect(
          Rect.fromLTRB(
            x - barWidth / 2,
            min(y, zeroY),
            x + barWidth / 2,
            max(y, zeroY),
          ),
          Paint()..color = barColor,
        );
      }
    }

    // MACD line
    void drawLine(List<double?> vals, Color color, double sw) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = sw
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      bool started = false;
      for (
        int i = max(0, startIndex - 1);
        i <= min(candles.length - 1, endIndex + 1);
        i++
      ) {
        if (i >= vals.length) break;
        final v = vals[i];
        if (v == null) {
          started = false;
          continue;
        }
        final x = indexToX(i.toDouble());
        final y = toSubY(v);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }

    drawLine(result.primary, macdColor, config.lineWidth);
    if (result.secondary != null) {
      drawLine(result.secondary!, signalColor, config.lineWidth * 0.85);
    }

    canvas.restore();
  }

  void _drawSubPaneLabels(
    Canvas canvas,
    Rect subPaneRect,
    Size size,
    IndicatorConfig config,
    IndicatorCalculationResult result,
  ) {
    final textStyle = AppTheme.mono(
      color: const Color(0xFFE5E7EB),
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
    );

    // Get active/current value
    double? activeVal;
    if (crosshairCandleIndex != null &&
        crosshairCandleIndex! >= 0 &&
        crosshairCandleIndex! < result.primary.length) {
      activeVal = result.primary[crosshairCandleIndex!];
    }
    if (activeVal == null && result.primary.isNotEmpty) {
      for (int k = result.primary.length - 1; k >= 0; k--) {
        if (result.primary[k] != null) {
          activeVal = result.primary[k];
          break;
        }
      }
    }

    // Title label format matching Chart.dc.html (e.g. "RSI 14")
    final titleString = config.type == IndicatorType.rsi
        ? 'RSI ${config.getInt('period', 14)}'
        : config.titleWithParams;

    final List<TextSpan> titleSpans = [
      TextSpan(text: '$titleString ', style: textStyle),
    ];
    if (activeVal != null) {
      titleSpans.add(
        TextSpan(
          text: activeVal.toStringAsFixed(1),
          style: AppTheme.mono(
            color: const Color(0xFFD58CF7),
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final labelTp = TextPainter(
      text: TextSpan(children: titleSpans),
      textDirection: TextDirection.ltr,
    )..layout();
    labelTp.paint(canvas, Offset(8, subPaneRect.top + 6));

    if (config.type == IndicatorType.rsi ||
        config.type == IndicatorType.stochastic) {
      final high = config.type == IndicatorType.stochastic
          ? config.getDouble('overbought', 80.0)
          : config.getDouble('overbought', 70.0);
      final low = config.type == IndicatorType.stochastic
          ? config.getDouble('oversold', 20.0)
          : config.getDouble('oversold', 30.0);

      // Label the levels on the right price scale
      for (final level in [high, low]) {
        final y = subPaneRect.bottom - (level / 100.0) * subPaneRect.height;
        final tp = TextPainter(
          text: TextSpan(
            text: level.toStringAsFixed(0),
            style: AppTheme.mono(
              color: const Color(0xFFD1D5DB),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(chartArea.width + 6, y - 6));
      }
    }
  }

  void _drawSubPaneCrosshair(Canvas canvas, Size size) {
    if (crosshairPosition == null || subPaneIndicators.isEmpty) return;
    final pos = crosshairPosition!;
    const double sep = 1.0;
    final crossPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..strokeWidth = 1.0;

    for (int i = 0; i < subPaneIndicators.length; i++) {
      final config = subPaneIndicators[i];
      final currentSubPaneTop =
          chartArea.bottom + 24.0 + (i * (subPaneHeight + sep)) + sep;
      final subPaneRect = Rect.fromLTWH(
        0,
        currentSubPaneTop,
        chartArea.width,
        subPaneHeight,
      );

      // Vertical line through this sub-pane
      double sy = currentSubPaneTop;
      while (sy < subPaneRect.bottom) {
        canvas.drawLine(Offset(pos.dx, sy), Offset(pos.dx, sy + 4), crossPaint);
        sy += 8;
      }

      // Show current sub-pane indicator value at crosshair on right axis
      if (hoverCandle != null) {
        final result = indicatorResults[config.id];
        if (result != null) {
          int idx = 0;
          for (int c = 0; c < candles.length; c++) {
            if (candles[c].openTime == hoverCandle!.openTime) {
              idx = c;
              break;
            }
          }
          final v = idx < result.primary.length ? result.primary[idx] : null;
          if (v != null) {
            final label = '${config.type.shortName}: ${v.toStringAsFixed(2)}';
            final tp = TextPainter(
              text: TextSpan(
                text: label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            final badgeRect = Rect.fromLTWH(
              chartArea.width + 2,
              subPaneRect.top + 2,
              tp.width + 8,
              16,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
              Paint()..color = const Color(0xFF00E5FF),
            );
            tp.paint(canvas, Offset(badgeRect.left + 4, badgeRect.top + 2));
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FullblownChartPainter oldDelegate) {
    return true; // Live ticks, panning, zooming, and animations require active repaints
  }
}

class _DrawingIconPainter extends CustomPainter {
  final DrawingTool tool;
  final Color color;

  const _DrawingIconPainter({required this.tool, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    switch (tool) {
      case DrawingTool.none: // Cursor
        final path = Path()
          ..moveTo(w * 0.22, h * 0.18)
          ..lineTo(w * 0.82, h * 0.48)
          ..lineTo(w * 0.54, h * 0.58)
          ..lineTo(w * 0.44, h * 0.84)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case DrawingTool.horizontalLine:
        canvas.drawLine(
          Offset(w * 0.12, h * 0.5),
          Offset(w * 0.88, h * 0.5),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), 2.2, fillPaint);
        break;

      case DrawingTool.trendline:
        canvas.drawLine(
          Offset(w * 0.2, h * 0.8),
          Offset(w * 0.8, h * 0.25),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.2, h * 0.8), 2.0, fillPaint);
        canvas.drawCircle(Offset(w * 0.8, h * 0.25), 2.0, fillPaint);
        break;

      case DrawingTool.ray:
        canvas.drawLine(
          Offset(w * 0.2, h * 0.75),
          Offset(w * 0.85, h * 0.35),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.2, h * 0.75), 2.0, fillPaint);
        final arrowPath = Path()
          ..moveTo(w * 0.68, h * 0.28)
          ..lineTo(w * 0.85, h * 0.35)
          ..lineTo(w * 0.76, h * 0.48);
        canvas.drawPath(arrowPath, paint);
        break;

      case DrawingTool.fibonacci:
        for (int i = 0; i < 4; i++) {
          final y = h * (0.22 + i * 0.18);
          canvas.drawLine(
            Offset(w * 0.18, y),
            Offset(w * 0.82, y),
            paint..strokeWidth = 1.3,
          );
        }
        break;

      case DrawingTool.rectangle:
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.18, h * 0.25, w * 0.64, h * 0.5),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(rrect, paint);
        break;

      case DrawingTool.verticalLine:
        canvas.drawLine(
          Offset(w * 0.5, h * 0.15),
          Offset(w * 0.5, h * 0.85),
          paint,
        );
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), 2.2, fillPaint);
        break;

      case DrawingTool.ruler:
        canvas.drawRect(
          Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.6, h * 0.6),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.2, h * 0.8),
          Offset(w * 0.8, h * 0.2),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingIconPainter oldDelegate) =>
      oldDelegate.tool != tool || oldDelegate.color != color;
}

class _CrosshairButtonPainter extends CustomPainter {
  final Color color;

  const _CrosshairButtonPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 3.0, paint);
    final w = size.width;
    final h = size.height;
    canvas.drawLine(
      Offset(center.dx, 1.5),
      Offset(center.dx, center.dy - 3.8),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + 3.8),
      Offset(center.dx, h - 1.5),
      paint,
    );
    canvas.drawLine(
      Offset(1.5, center.dy),
      Offset(center.dx - 3.8, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + 3.8, center.dy),
      Offset(w - 1.5, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairButtonPainter oldDelegate) =>
      oldDelegate.color != color;
}
