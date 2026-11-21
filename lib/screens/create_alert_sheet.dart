import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/market_models.dart';
import '../services/alarm_service.dart';
import '../services/biquote_service.dart';
import '../services/market_data_api.dart';
import '../services/settings_provider.dart';
import '../theme/app_theme.dart';

const _s1 = Color(0xFF1C1C1E);
const _s2 = Color(0xFF2C2C2E);
const _s3 = Color(0xFF3A3A3C);
const _t2 = Color(0x9DEBEBF5);
const _t3 = Color(0x57EBEBF5);
const _bl = Color(0xFF0A84FF);
const _up = Color(0xFF30D158);

class CreateAlertSheet extends StatefulWidget {
  final String symbol;
  final double currentPrice;
  final BiquoteService? biquoteService;
  final int precision;
  final double? initialTargetPrice;
  final String? drawingId;
  final AlarmService? alarmService;
  final AlertType? initialAlertType;
  final String? initialNote;
  final List<ChainStage>? initialChainStages;
  final AlertCondition? initialCondition;
  final IndicatorAlertConfig? initialIndicatorConfig;
  final DateTime? initialScheduledTime;
  final Function onAlertCreated;

  const CreateAlertSheet({
    super.key,
    required this.symbol,
    required this.currentPrice,
    this.biquoteService,
    required this.precision,
    this.initialTargetPrice,
    this.drawingId,
    this.alarmService,
    this.initialAlertType,
    this.initialIndicatorConfig,
    this.initialNote,
    this.initialChainStages,
    this.initialCondition,
    this.initialScheduledTime,
    required this.onAlertCreated,
  });

  @override
  State<CreateAlertSheet> createState() => _CreateAlertSheetState();
}

class _CreateAlertSheetState extends State<CreateAlertSheet> {
  late String _selectedSymbol;
  late double _selectedPrice;
  late int _selectedPrecision;
  AlertType _alertType = AlertType.priceLevel;
  late AlertCondition _condition;
  late double _targetPrice;
  late TextEditingController _priceController;
  final TextEditingController _noteController = TextEditingController();
  late final AlarmService _alarmService;
  DateTime? _scheduledTime;

  CandlestickPattern _selectedPattern = CandlestickPattern.bullishEngulfing;
  String _selectedTimeframe = '15m';
  String _patternFilter = 'All'; // 'All', 'Bullish', 'Bearish', 'Indecision'

  // Indicator Alert Configuration State
  AlertIndicatorType _selectedIndicator = AlertIndicatorType.rsi;
  int _rsiPeriod = 14;
  String _rsiSource = 'Close';
  String _rsiSmoothingType = 'RMA';
  double _rsiLevel = 30.0;
  double _rsiOverbought = 70.0;
  double _rsiOversold = 30.0;
  bool _rsiApplySignalMa = false;
  String _rsiSignalMaType = 'EMA';
  int _rsiSignalMaPeriod = 9;
  String _rsiCondition = 'crossesBelowOversold';

  int _macdFast = 12;
  int _macdSlow = 26;
  int _macdSignal = 9;
  String _macdSource = 'Close';
  String _macdFastMaType = 'EMA';
  String _macdSlowMaType = 'EMA';
  String _macdSignalMaType = 'EMA';
  String _macdCondition = 'bullishSignalCross';

  int _maFastPeriod = 50;
  int _maSlowPeriod = 200;
  String _maType = 'EMA';
  String _maFastMaType = 'EMA';
  String _maSlowMaType = 'EMA';
  String _maSource = 'Close';
  String _maCondition = 'goldenCross';

  int _bbPeriod = 20;
  double _bbStdDev = 2.0;
  double _bbSqueezeThreshold = 0.015;
  String _bbSource = 'Close';
  String _bbMaType = 'SMA';
  String _bbCondition = 'lowerBandTouch';

  int _stochK = 14;
  int _stochKSlowing = 3;
  int _stochD = 3;
  String _stochDMaType = 'SMA';
  double _stochOversold = 20.0;
  double _stochOverbought = 80.0;
  String _stochCondition = 'bullishOversoldCross';

  int _stPeriod = 10;
  double _stMultiplier = 3.0;
  String _stSource = 'HL2';
  String _stAtrSmoothing = 'RMA';
  double _stDistanceThreshold = 1.0;
  String _stCondition = 'bullishFlip';

  // Multi-Step Logic Chain State
  late List<ChainStage> _chainStages;

  // Multi-Currency and Execution Engine Settings
  late Set<String> _selectedCurrencies;
  List<BiquoteInstrument> _allInstruments = [];
  bool _instrumentsLoaded = false;
  bool _rearmAfterCooldown = true;
  bool _showAdvancedOptions = false;
  final TextEditingController _chainNameController = TextEditingController(
    text: 'Breakout → Pullback → Hammer',
  );
  int _defaultTimeoutMinutes = 30;
  final Set<String> _expandedNodeIds = {};

  bool _triggerOnCandleClose = true;
  bool _targetManuallyEdited = false;
  bool _chainManuallyEdited = false;
  StreamSubscription<BiquoteTick>? _priceSubscription;
  final Map<String, TextEditingController> _chainPriceControllers = {};
  int _cooldownMinutes = 0;

  String _selectedRingtoneTitle = 'Default Alarm';
  String? _selectedRingtoneUri;
  List<RingtoneItem> _availableRingtones = [];
  String? _previewingUri;
  bool _isDndGranted = false;

  final List<String> _timeframes = ['5m', '15m', '30m', '1h', '4h', '1d'];

  double get _pipValue {
    if (_selectedSymbol.contains('JPY')) return 0.01;
    if (_selectedSymbol.contains('BTC') || _selectedSymbol.contains('XAU')) {
      return 1.0;
    }
    return 0.0001; // Standard forex pip
  }

  @override
  void initState() {
    super.initState();
    _selectedSymbol = widget.symbol;
    _selectedPrice = widget.currentPrice;
    _selectedPrecision = widget.precision;
    final globalSoundTitle = SettingsProvider().soundTitle;
    final globalSoundUri = SettingsProvider().soundUri;
    _selectedRingtoneTitle = globalSoundTitle.isNotEmpty
        ? globalSoundTitle
        : 'Default Alarm';
    _selectedRingtoneUri = globalSoundUri.isNotEmpty ? globalSoundUri : null;
    _selectedCurrencies = {_selectedSymbol};
    _alarmService = widget.alarmService ?? AlarmService();
    _loadAllInstruments();
    if (widget.initialAlertType != null) {
      _alertType = widget.initialAlertType!;
    }
    if (widget.initialScheduledTime != null) {
      _scheduledTime = widget.initialScheduledTime;
      _alertType = AlertType.timeSchedule;
    }
    if (widget.initialIndicatorConfig != null) {
      _alertType = AlertType.technicalIndicator;
      _applySavedIndicatorConfig(widget.initialIndicatorConfig!);
    }
    _triggerOnCandleClose = _alertType == AlertType.priceLevel ? false : true;
    _cooldownMinutes = 15;
    _rearmAfterCooldown = true;
    if (widget.initialNote != null && widget.initialNote!.isNotEmpty) {
      _noteController.text = widget.initialNote!;
    }

    if (widget.initialCondition != null) {
      _condition = widget.initialCondition!;
    } else if (widget.initialTargetPrice != null &&
        widget.initialTargetPrice! > 0) {
      _condition = widget.initialTargetPrice! >= _selectedPrice
          ? AlertCondition.crossesAbove
          : AlertCondition.crossesBelow;
    } else {
      _condition = AlertCondition.crossesAbove;
    }

    if (widget.initialTargetPrice != null && widget.initialTargetPrice! > 0) {
      _targetPrice = widget.initialTargetPrice!;
    } else {
      _targetPrice = _selectedPrice + (_pipValue * 10);
    }
    _priceController = TextEditingController(
      text: _targetPrice.toStringAsFixed(_selectedPrecision),
    );

    // Initialize Logic Chain from initialChainStages if provided, else use Default
    if (widget.initialChainStages != null &&
        widget.initialChainStages!.isNotEmpty) {
      _chainStages = List.from(widget.initialChainStages!);
    } else {
      _chainStages = [
        ChainStage(
          id: 'stage_1',
          name: 'Breakout',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_1',
              nodeType: AlertType.priceLevel,
              targetPrice: _selectedPrice > 0
                  ? _selectedPrice + (_pipValue * 10)
                  : 0,
              condition: AlertCondition.crossesAbove,
            ),
          ],
        ),
        ChainStage(
          id: 'stage_2',
          name: 'Pullback to support',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_2_1',
              nodeType: AlertType.priceLevel,
              targetPrice: _selectedPrice > 0
                  ? _selectedPrice - (_pipValue * 5)
                  : 0,
              condition: AlertCondition.crossesBelow,
              operatorToPrevious: 'AND',
            ),
            ChainNode(
              id: 'node_2_2',
              nodeType: AlertType.technicalIndicator,
              isNegated: true,
              indicatorConfig: IndicatorAlertConfig(
                indicatorType: AlertIndicatorType.rsi,
                condition: 'crossesAboveLevel',
                params: {
                  'period': 14,
                  'level': 70.0,
                  'source': 'Close',
                  'smoothingType': 'RMA',
                },
              ),
              timeframe: '15m',
              operatorToPrevious: 'AND',
            ),
          ],
        ),
        ChainStage(
          id: 'stage_3',
          name: 'Confirmation',
          timeoutMinutes: 30,
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_3_1',
              nodeType: AlertType.candlestickPattern,
              candlestickPattern: CandlestickPattern.hammer,
              timeframe: '15m',
              operatorToPrevious: 'AND',
            ),
          ],
        ),
      ];
    }
    _loadAlarmData();
    _startLivePriceUpdates();
  }

  void _startLivePriceUpdates() {
    final service = widget.biquoteService;
    if (service == null) return;
    service.subscribe([_selectedSymbol]);
    _priceSubscription = service.tickStream.listen((tick) {
      if (!mounted || tick.symbol != _selectedSymbol || tick.mid <= 0) return;
      _applyLivePrice(tick.mid, tick.precision);
    });
    unawaited(_fetchLivePrice(_selectedSymbol));
  }

  Future<void> _fetchLivePrice(String symbol) async {
    final service = widget.biquoteService;
    if (service == null) return;
    try {
      final tick = await service.getSingleQuote(symbol);
      if (tick != null &&
          mounted &&
          symbol == _selectedSymbol &&
          tick.mid > 0) {
        _applyLivePrice(tick.mid, tick.precision);
      }
    } catch (_) {
      // Keep the chart's last known quote for offline use.
    }
  }

  void _applyLivePrice(double price, int precision) {
    setState(() {
      _selectedPrice = price;
      if (precision > 0) _selectedPrecision = precision;
      if (!_targetManuallyEdited &&
          _alertType == AlertType.priceLevel &&
          (widget.initialTargetPrice == null ||
              widget.initialTargetPrice! <= 0)) {
        _targetPrice = price + (_pipValue * 10);
        _priceController.text = _targetPrice.toStringAsFixed(
          _selectedPrecision,
        );
        _condition = AlertCondition.crossesAbove;
      }
      if (!_chainManuallyEdited) {
        _chainStages = _buildDefaultChainStages();
        _syncChainPriceControllers();
      }
    });
  }

  List<ChainStage> _buildDefaultChainStages() => [
    ChainStage(
      id: 'stage_1',
      name: 'Breakout',
      timeoutMinutes: 30,
      logicOperator: 'AND',
      nodes: [
        ChainNode(
          id: 'node_1',
          nodeType: AlertType.priceLevel,
          targetPrice: _selectedPrice > 0
              ? _selectedPrice + (_pipValue * 10)
              : 0,
          condition: AlertCondition.crossesAbove,
        ),
      ],
    ),
    ChainStage(
      id: 'stage_2',
      name: 'Pullback to support',
      timeoutMinutes: 30,
      logicOperator: 'AND',
      nodes: [
        ChainNode(
          id: 'node_2_1',
          nodeType: AlertType.priceLevel,
          targetPrice: _selectedPrice > 0
              ? _selectedPrice - (_pipValue * 5)
              : 0,
          condition: AlertCondition.crossesBelow,
          operatorToPrevious: 'AND',
        ),
        ChainNode(
          id: 'node_2_2',
          nodeType: AlertType.technicalIndicator,
          isNegated: true,
          indicatorConfig: IndicatorAlertConfig(
            indicatorType: AlertIndicatorType.rsi,
            condition: 'crossesAboveLevel',
            params: {
              'period': 14,
              'level': 70.0,
              'source': 'Close',
              'smoothingType': 'RMA',
            },
          ),
          timeframe: '15m',
          operatorToPrevious: 'AND',
        ),
      ],
    ),
    ChainStage(
      id: 'stage_3',
      name: 'Confirmation',
      timeoutMinutes: 30,
      logicOperator: 'AND',
      nodes: [
        ChainNode(
          id: 'node_3_1',
          nodeType: AlertType.candlestickPattern,
          candlestickPattern: CandlestickPattern.hammer,
          timeframe: '15m',
          operatorToPrevious: 'AND',
        ),
      ],
    ),
  ];

  void _syncChainPriceControllers() {
    for (final stage in _chainStages) {
      for (final node in stage.nodes.where(
        (item) => item.nodeType == AlertType.priceLevel,
      )) {
        _chainPriceControllers[node.id]?.text =
            (node.targetPrice > 0 ? node.targetPrice : _selectedPrice)
                .toStringAsFixed(_selectedPrecision);
      }
    }
  }

  Future<void> _loadAlarmData() async {
    final ringtones = await _alarmService.getRingtones();
    final dndGranted = await _alarmService.isDndOverrideGranted();
    if (mounted) {
      setState(() {
        _availableRingtones = ringtones;
        _isDndGranted = dndGranted;

        // Preserve global setting from SettingsProvider if configured
        final globalTitle = SettingsProvider().soundTitle;
        final globalUri = SettingsProvider().soundUri;

        // Look for exact match in available ringtones
        final matched = ringtones
            .where(
              (r) =>
                  (globalUri.isNotEmpty && r.uri == globalUri) ||
                  (globalTitle.isNotEmpty &&
                      r.title.toLowerCase() == globalTitle.toLowerCase()),
            )
            .firstOrNull;

        if (matched != null) {
          _selectedRingtoneTitle = matched.title;
          _selectedRingtoneUri = matched.uri;
        } else if (globalTitle.isNotEmpty) {
          _selectedRingtoneTitle = globalTitle;
          _selectedRingtoneUri = globalUri.isNotEmpty
              ? globalUri
              : (ringtones.isNotEmpty ? ringtones.first.uri : null);
        } else if (ringtones.isNotEmpty) {
          _selectedRingtoneTitle = ringtones.first.title;
          _selectedRingtoneUri = ringtones.first.uri;
        }
      });
    }
  }

  @override
  void dispose() {
    _priceSubscription?.cancel();
    _priceController.dispose();
    for (final controller in _chainPriceControllers.values) {
      controller.dispose();
    }
    _noteController.dispose();
    _chainNameController.dispose();
    _alarmService.stopPreview();
    super.dispose();
  }

  TextEditingController _chainPriceController(ChainNode node) =>
      _chainPriceControllers.putIfAbsent(
        node.id,
        () => TextEditingController(
          text: (node.targetPrice > 0 ? node.targetPrice : _selectedPrice)
              .toStringAsFixed(_selectedPrecision),
        ),
      );

  void _adjustPips(double pips) {
    _targetManuallyEdited = true;
    setState(() {
      _targetPrice += pips * _pipValue;
      if (_targetPrice <= 0) _targetPrice = _pipValue;
      _priceController.text = _targetPrice.toStringAsFixed(_selectedPrecision);
      if (_targetPrice > _selectedPrice) {
        _condition = AlertCondition.crossesAbove;
      } else {
        _condition = AlertCondition.crossesBelow;
      }
    });
  }

  void _onPriceChanged(String val) {
    final parsed = double.tryParse(val);
    if (parsed != null && parsed > 0) {
      _targetManuallyEdited = true;
      setState(() {
        _targetPrice = parsed;
        if (_targetPrice > _selectedPrice) {
          _condition = AlertCondition.crossesAbove;
        } else {
          _condition = AlertCondition.crossesBelow;
        }
      });
    }
  }

  void _openRingtonePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                border: Border.all(color: theme.dividerColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SELECT ALARM RINGTONE',
                        style: AppTheme.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          _alarmService.stopPreview();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a tone that will play continuously until dismissed',
                    style: AppTheme.sans(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _availableRingtones.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tone = _availableRingtones[index];
                        final isSelected = tone.title == _selectedRingtoneTitle;
                        final isPreviewing = _previewingUri == tone.uri;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          title: Text(
                            tone.title,
                            style: AppTheme.sans(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tone.type.toUpperCase(),
                                  style: AppTheme.mono(
                                    context: context,
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(
                                  isPreviewing
                                      ? Icons.stop_circle
                                      : Icons.play_circle_fill,
                                  color: isPreviewing
                                      ? Colors.amber
                                      : theme.colorScheme.primary,
                                  size: 26,
                                ),
                                onPressed: () {
                                  if (isPreviewing) {
                                    _alarmService.stopPreview();
                                    setPickerState(() => _previewingUri = null);
                                    setState(() => _previewingUri = null);
                                  } else {
                                    _alarmService.previewRingtone(tone.uri);
                                    setPickerState(
                                      () => _previewingUri = tone.uri,
                                    );
                                    setState(() => _previewingUri = tone.uri);
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _selectedRingtoneTitle = tone.title;
                              _selectedRingtoneUri = tone.uri;
                            });
                            _alarmService.stopPreview();
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<CandlestickPattern> get _filteredPatterns {
    switch (_patternFilter) {
      case 'Bullish':
        return CandlestickPattern.values
            .where((p) => p.isBullish == true)
            .toList();
      case 'Bearish':
        return CandlestickPattern.values
            .where((p) => p.isBullish == false)
            .toList();
      case 'Indecision':
        return CandlestickPattern.values
            .where((p) => p.isBullish == null)
            .toList();
      default:
        return CandlestickPattern.values;
    }
  }

  String _getPatternDescription(CandlestickPattern pattern) {
    switch (pattern) {
      case CandlestickPattern.bullishEngulfing:
        return 'Green candle body completely engulfs prior red body. Major bullish reversal.';
      case CandlestickPattern.bearishEngulfing:
        return 'Red candle body completely engulfs prior green body. Strong bearish selloff.';
      case CandlestickPattern.hammer:
        return 'Small body at top, long lower shadow rejecting support.';
      case CandlestickPattern.hangingMan:
        return 'Small body with long lower wick forming after an uptrend, warning exhaustion.';
      case CandlestickPattern.shootingStar:
        return 'Long upper shadow rejecting resistance with small lower body.';
      case CandlestickPattern.invertedHammer:
        return 'Long upper wick at swing lows, hinting at upcoming buyer entry.';
      case CandlestickPattern.morningStar:
        return '3-candle powerhouse: Strong red, indecision star, strong green breakout.';
      case CandlestickPattern.eveningStar:
        return '3-candle reversal: Strong green, indecision star, deep red breakdown.';
      case CandlestickPattern.doji:
        return 'Open and close virtually equal. Market equilibrium and pending breakout.';
      case CandlestickPattern.dragonflyDoji:
        return 'Long lower wick with open and close at the high. Extreme low price rejection.';
      case CandlestickPattern.gravestoneDoji:
        return 'Long upper wick with open and close at the low. Extreme high price rejection.';
      case CandlestickPattern.piercingLine:
        return 'Green candle opens low and pierces above 50% midpoint of prior red candle.';
      case CandlestickPattern.darkCloudCover:
        return 'Red candle opens high and closes below 50% midpoint of prior green candle.';
      case CandlestickPattern.threeWhiteSoldiers:
        return '3 consecutive bullish candles closing near highs. Massive institutional momentum.';
      case CandlestickPattern.threeBlackCrows:
        return '3 consecutive bearish candles closing near lows. Heavy sell conviction.';
      case CandlestickPattern.bullishHarami:
        return 'Small green inside-bar contained within large red body. Momentum shift.';
      case CandlestickPattern.bearishHarami:
        return 'Small red inside-bar contained within large green body. Exhaustion warning.';
      case CandlestickPattern.tweezerBottom:
        return '2 candles matching the exact same low price before sharp bounce.';
      case CandlestickPattern.tweezerTop:
        return '2 candles hitting the exact same high resistance ceiling.';
      case CandlestickPattern.marubozu:
        return 'Full solid candle body with virtually no wicks. 90%+ pure directional power.';
    }
  }

  Widget _buildSegTab(String label, AlertType type) {
    final isSelected = _alertType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _alertType = type),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? _s3 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : _t2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOledChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    double height = 34,
    double fontSize = 12,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? _bl.withValues(alpha: 0.20)
              : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: isSelected ? _bl : Colors.transparent,
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: fontSize,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? const Color(0xFF4DA3FF) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildConditionButton(String label, AlertCondition condition) {
    final isSelected = _condition == condition;
    return GestureDetector(
      onTap: () => setState(() => _condition = condition),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x240A84FF) : _s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _bl : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? const Color(0xFF4DA3FF) : _t2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPair = _selectedSymbol.length == 6
        ? '${_selectedSymbol.substring(0, 3)}/${_selectedSymbol.substring(3)}'
        : _selectedSymbol;

    final pipDiff = ((_targetPrice - _selectedPrice) / _pipValue);
    final pipText =
        '${pipDiff >= 0 ? "+" : ""}${pipDiff.toStringAsFixed(1)} pips from current';

    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight - topPadding - 32;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      margin: EdgeInsets.only(top: topPadding + 16),
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0x33FFFFFF), width: 1)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(
          children: [
            // Frosted grab pill
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0x4DEBEBF5),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            // Header Bar: Cancel, New Alert, spacer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: AppTheme.sans(
                        fontSize: 17,
                        color: const Color(0xFF4DA3FF),
                      ),
                    ),
                  ),
                  Text(
                    'New Alert',
                    style: AppTheme.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 14),

                    // Segmented Control: Price, Pattern, Indicator, Chain, Time
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _s1,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            _buildSegTab('Price', AlertType.priceLevel),
                            _buildSegTab(
                              'Pattern',
                              AlertType.candlestickPattern,
                            ),
                            _buildSegTab(
                              'Indicator',
                              AlertType.technicalIndicator,
                            ),
                            _buildSegTab('Chain', AlertType.multiStepChain),
                            _buildSegTab('Time', AlertType.timeSchedule),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Asset Card
                    GestureDetector(
                      onTap: _openInstrumentPicker,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _s1,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0x330A84FF),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _selectedSymbol.length >= 2
                                    ? _selectedSymbol
                                          .substring(0, 2)
                                          .toUpperCase()
                                    : 'FX',
                                style: const TextStyle(
                                  color: Color(0xFF4DA3FF),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayPair,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Tap to change instrument',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _t2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _selectedPrice.toStringAsFixed(
                                    _selectedPrecision,
                                  ),
                                  style: AppTheme.mono(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  _selectedPrice > 0 ? 'Live' : 'No live quote',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: _selectedPrice > 0
                                        ? const Color(0xFF43E06A)
                                        : Colors.amber,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: _t3,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Main mode-specific content:
                    if (_alertType == AlertType.priceLevel) ...[
                      // Target Price Stepper Card
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        decoration: BoxDecoration(
                          color: _s1,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'TARGET PRICE',
                              style: AppTheme.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.99,
                                color: _t2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () => _adjustPips(-1),
                                  onLongPress: () => _adjustPips(-10),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: _s2,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.remove,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _priceController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.center,
                                    style: AppTheme.mono(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -1.5,
                                      color: Colors.white,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: _onPriceChanged,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _adjustPips(1),
                                  onLongPress: () => _adjustPips(10),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: _s2,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pipText,
                              style: AppTheme.mono(fontSize: 13, color: _t2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Condition buttons: Crosses Above, Crosses Below, Hits
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildConditionButton(
                                'Crosses Above',
                                AlertCondition.crossesAbove,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildConditionButton(
                                'Crosses Below',
                                AlertCondition.crossesBelow,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildConditionButton(
                                'Hits',
                                AlertCondition.hits,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Info explanatory banner
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x1A0A84FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Color(0xFF7CBCFF),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _condition == AlertCondition.crossesAbove
                                    ? "Fires only when price moves up through ${_targetPrice.toStringAsFixed(_selectedPrecision)} — never instantly if it's already above."
                                    : _condition == AlertCondition.crossesBelow
                                    ? "Fires only when price moves down through ${_targetPrice.toStringAsFixed(_selectedPrecision)} — never instantly if it's already below."
                                    : "Fires immediately when price touches or trades at ${_targetPrice.toStringAsFixed(_selectedPrecision)}.",
                                style: const TextStyle(
                                  color: Color(0xFF7CBCFF),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_alertType == AlertType.candlestickPattern) ...[
                      // Candlestick Pattern Configuration
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'TIMEFRAME',
                                  style: AppTheme.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _t2,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Text(
                                  'Evaluates on candle close',
                                  style: AppTheme.sans(
                                    fontSize: 11,
                                    color: _bl,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 34,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _timeframes.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, idx) {
                                  final tf = _timeframes[idx];
                                  final isSelected =
                                      _selectedTimeframe.toLowerCase() ==
                                      tf.toLowerCase();
                                  return _buildOledChip(
                                    label: tf.toUpperCase(),
                                    isSelected: isSelected,
                                    onTap: () =>
                                        setState(() => _selectedTimeframe = tf),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'CANDLESTICK PATTERN',
                              style: AppTheme.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _t2,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children:
                                    [
                                      'All',
                                      'Bullish',
                                      'Bearish',
                                      'Indecision',
                                    ].map((cat) {
                                      final isCatSelected =
                                          _patternFilter == cat;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: _buildOledChip(
                                          label: cat,
                                          isSelected: isCatSelected,
                                          onTap: () => setState(
                                            () => _patternFilter = cat,
                                          ),
                                          height: 32,
                                        ),
                                      );
                                    }).toList(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: _s1,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                itemCount: _filteredPatterns.length,
                                separatorBuilder: (_, _) => const Divider(
                                  color: Color(0x17FFFFFF),
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final pattern = _filteredPatterns[index];
                                  final isSelected =
                                      _selectedPattern == pattern;
                                  final isBullish = pattern.isBullish;
                                  final badgeColor = isBullish == true
                                      ? _up
                                      : (isBullish == false
                                            ? const Color(0xFFFF453A)
                                            : Colors.amber);

                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 2,
                                    ),
                                    leading: Icon(
                                      isSelected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: isSelected ? _bl : _t2,
                                      size: 18,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            pattern.label,
                                            style: TextStyle(
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              fontSize: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            isBullish == true
                                                ? 'BULLISH'
                                                : (isBullish == false
                                                      ? 'BEARISH'
                                                      : 'NEUTRAL'),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: badgeColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      _getPatternDescription(pattern),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _t2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => setState(
                                      () => _selectedPattern = pattern,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_alertType == AlertType.technicalIndicator) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildIndicatorSection(theme, true),
                        ),
                      ),
                    ] else if (_alertType == AlertType.timeSchedule) ...[
                      _buildTimeScheduleSection(),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _buildLogicChainSection(theme, true),
                        ),
                      ),
                    ],

                    // OPTIONS Section (Only for single alert types)
                    if (_alertType != AlertType.multiStepChain) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                        child: Text(
                          'OPTIONS',
                          style: AppTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.99,
                            color: _t2,
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _s1,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            // Row 1: Rearm after cooldown
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Rearm after cooldown',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _rearmAfterCooldown,
                                    activeTrackColor: _up,
                                    onChanged: (v) {
                                      setState(() {
                                        _rearmAfterCooldown = v;
                                        if (!v) {
                                          _cooldownMinutes = 0;
                                        } else if (_cooldownMinutes == 0) {
                                          _cooldownMinutes = 15;
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Color(0x17FFFFFF), height: 1),
                            // Row 2: Cooldown Slider
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                14,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Cooldown',
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _cooldownMinutes == 0
                                            ? 'Off'
                                            : '$_cooldownMinutes min',
                                        style: AppTheme.mono(
                                          fontSize: 15,
                                          color: _t2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: _bl,
                                      inactiveTrackColor: _s3,
                                      thumbColor: Colors.white,
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 10,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 18,
                                          ),
                                    ),
                                    child: Slider(
                                      value: _cooldownMinutes.toDouble().clamp(
                                        0.0,
                                        60.0,
                                      ),
                                      min: 0,
                                      max: 60,
                                      divisions: 12,
                                      onChanged: (v) {
                                        setState(() {
                                          _cooldownMinutes = v.round();
                                          _rearmAfterCooldown =
                                              _cooldownMinutes > 0;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(color: Color(0x17FFFFFF), height: 1),
                            // Row 3: Alarm sound
                            InkWell(
                              onTap: _openRingtonePicker,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(20),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Alarm sound',
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _selectedRingtoneTitle,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: _t2,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: _t3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_alertType != AlertType.priceLevel) ...[
                              const Divider(
                                color: Color(0x17FFFFFF),
                                height: 1,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Evaluate only on candle close',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: _triggerOnCandleClose,
                                      activeTrackColor: _up,
                                      onChanged: (v) => setState(
                                        () => _triggerOnCandleClose = v,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Advanced Options Expandable
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _showAdvancedOptions = !_showAdvancedOptions,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _s1,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: _t2,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Advanced Options (Note, Multi-Pair, DND)',
                                style: AppTheme.sans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _t2,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _showAdvancedOptions
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 20,
                                color: _t2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_showAdvancedOptions) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _s1,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ALERT NOTE',
                                style: AppTheme.sans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _t2,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _noteController,
                                style: AppTheme.sans(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Key support confirmation',
                                  hintStyle: TextStyle(
                                    color: _t2.withValues(alpha: 0.5),
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: _s2,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _isDndGranted
                                      ? _up.withValues(alpha: 0.12)
                                      : Colors.amber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _isDndGranted
                                          ? Icons.volume_up
                                          : Icons.do_not_disturb_on,
                                      color: _isDndGranted ? _up : Colors.amber,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _isDndGranted
                                            ? 'DND Override Active'
                                            : 'DND Override Disabled',
                                        style: AppTheme.sans(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (!_isDndGranted)
                                      TextButton(
                                        onPressed: () async {
                                          await _alarmService
                                              .requestDndOverride();
                                          final granted = await _alarmService
                                              .isDndOverrideGranted();
                                          setState(
                                            () => _isDndGranted = granted,
                                          );
                                        },
                                        child: const Text(
                                          'Grant',
                                          style: TextStyle(
                                            color: Colors.amber,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'DEPLOY TO MULTIPLE INSTRUMENTS',
                                    style: AppTheme.sans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _t2,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Text(
                                    '${_selectedCurrencies.length} selected',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _bl,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: _openMultiSymbolPicker,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _s2,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _s3, width: 0.8),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: _bl.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.tune,
                                          color: _bl,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedCurrencies.length == 1
                                                  ? _selectedCurrencies.first
                                                  : '${_selectedCurrencies.length} Instruments Selected',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _instrumentsLoaded
                                                  ? (_selectedCurrencies
                                                                .length ==
                                                            1
                                                        ? 'Tap to search & deploy across catalog'
                                                        : '${_selectedCurrencies.take(4).join(', ')}${_selectedCurrencies.length > 4 ? "…" : ""}')
                                                  : 'Loading catalog instruments…',
                                              style: const TextStyle(
                                                color: _t2,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: _t2,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_selectedCurrencies.length > 1) ...[
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _selectedCurrencies.map((sym) {
                                      final isCurrent = sym == _selectedSymbol;
                                      return Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? _bl.withValues(alpha: 0.2)
                                              : _s2,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: isCurrent
                                                ? _bl.withValues(alpha: 0.5)
                                                : _s3,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              sym,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isCurrent
                                                    ? _bl
                                                    : Colors.white,
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            if (!isCurrent) ...[
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                onTap: () {
                                                  setState(
                                                    () => _selectedCurrencies
                                                        .remove(sym),
                                                  );
                                                },
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 12,
                                                  color: _t2,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Create Alert Action Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () {
                          try {
                            (widget.onAlertCreated as dynamic)(
                              symbol: _selectedSymbol,
                              alertType: _alertType,
                              targetPrice: _alertType == AlertType.priceLevel
                                  ? _targetPrice
                                  : 0.0,
                              condition: _condition,
                              candlestickPattern:
                                  _alertType == AlertType.candlestickPattern
                                  ? _selectedPattern
                                  : null,
                              indicatorConfig:
                                  _alertType == AlertType.technicalIndicator
                                  ? _buildCurrentIndicatorConfig()
                                  : null,
                              multiStepConfig:
                                  _alertType == AlertType.multiStepChain
                                  ? MultiStepConfig(stages: _chainStages)
                                  : null,
                              timeframe: _selectedTimeframe,
                              note: _noteController.text.trim(),
                              ringtoneTitle: _selectedRingtoneTitle,
                              ringtoneUri: _selectedRingtoneUri,
                              drawingId: widget.drawingId,
                              targetSymbols: _selectedCurrencies.toList(),
                              triggerOnCandleClose: _triggerOnCandleClose,
                              cooldownMinutes: _cooldownMinutes,
                              scheduledTime:
                                  _alertType == AlertType.timeSchedule
                                  ? (_scheduledTime ??
                                        DateTime.now().add(
                                          const Duration(minutes: 15),
                                        ))
                                  : null,
                            );
                          } catch (_) {
                            (widget.onAlertCreated as dynamic)(
                              symbol: _selectedSymbol,
                              alertType: _alertType,
                              targetPrice: _alertType == AlertType.priceLevel
                                  ? _targetPrice
                                  : 0.0,
                              condition: _condition,
                              candlestickPattern:
                                  _alertType == AlertType.candlestickPattern
                                  ? _selectedPattern
                                  : null,
                              indicatorConfig:
                                  _alertType == AlertType.technicalIndicator
                                  ? _buildCurrentIndicatorConfig()
                                  : null,
                              multiStepConfig:
                                  _alertType == AlertType.multiStepChain
                                  ? MultiStepConfig(stages: _chainStages)
                                  : null,
                              timeframe: _selectedTimeframe,
                              note: _noteController.text.trim(),
                              ringtoneTitle: _selectedRingtoneTitle,
                              ringtoneUri: _selectedRingtoneUri,
                              drawingId: widget.drawingId,
                              targetSymbols: _selectedCurrencies.toList(),
                              triggerOnCandleClose: _triggerOnCandleClose,
                              cooldownMinutes: _cooldownMinutes,
                            );
                          }
                          Navigator.pop(context);
                        },
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: _bl,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _bl.withValues(alpha: 0.4),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Create Alert',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeScheduleSection() {
    final now = DateTime.now();
    final effectiveTime =
        _scheduledTime ?? now.add(const Duration(minutes: 15));
    final diff = effectiveTime.difference(now);
    final diffMinutes = diff.inMinutes;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TIME-PERIOD ALARM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _t2,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x33FFB340),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  diffMinutes > 0 ? 'Fires in ${diffMinutes}m' : 'Ready',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFB340),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _s2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  color: Color(0xFFFFB340),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, MMM d · HH:mm')
                            .format(effectiveTime.toLocal()),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'UTC: ${DateFormat('yyyy-MM-dd HH:mm').format(effectiveTime.toUtc())} UTC',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _t2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _pickCustomDateTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _bl,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Quick Offsets',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _t2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTimeChip('+15m', 15),
              _buildTimeChip('+30m', 30),
              _buildTimeChip('+1 Hour', 60),
              _buildTimeChip('+2 Hours', 120),
              _buildTimeChip('+4 Hours', 240),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Market Session Openings (Today / Next)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _t2,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              _buildSessionRow('London Open', 7, 0),
              _buildSessionRow('New York Open', 12, 0),
              _buildSessionRow('Tokyo Open', 0, 0),
              _buildSessionRow('Sydney Open', 21, 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String label, int minutes) {
    final now = DateTime.now();
    final target = now.add(Duration(minutes: minutes));
    final isSelected =
        _scheduledTime != null &&
        (_scheduledTime!.difference(target).inMinutes.abs() <= 1);
    return GestureDetector(
      onTap: () {
        setState(() {
          _scheduledTime = now.add(Duration(minutes: minutes));
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _bl : _s2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : _t2,
          ),
        ),
      ),
    );
  }

  Widget _buildSessionRow(String name, int utcHour, int utcMinute) {
    final nowUtc = DateTime.now().toUtc();
    var sessionUtc = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
      utcHour,
      utcMinute,
    );
    if (sessionUtc.isBefore(nowUtc)) {
      sessionUtc = sessionUtc.add(const Duration(days: 1));
    }
    final isSelected =
        _scheduledTime != null &&
        _scheduledTime!.toUtc().isAtSameMomentAs(sessionUtc);

    return GestureDetector(
      onTap: () {
        setState(() {
          _scheduledTime = sessionUtc.toLocal();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0x330A84FF) : _s2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? _bl : const Color(0x0FFFFFFF)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  color: isSelected ? _bl : _t2,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : _t2,
                  ),
                ),
              ],
            ),
            Text(
              '${DateFormat('HH:mm').format(sessionUtc.toLocal())} Local (${utcHour.toString().padLeft(2, '0')}:00 UTC)',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isSelected ? _bl : const Color(0x80EBEBF5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledTime ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduledTime ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _scheduledTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  IndicatorAlertConfig _buildCurrentIndicatorConfig() {
    switch (_selectedIndicator) {
      case AlertIndicatorType.rsi:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.rsi,
          condition: _rsiCondition,
          params: {
            'period': _rsiPeriod,
            'source': _rsiSource,
            'smoothingType': _rsiSmoothingType,
            'level': _rsiLevel,
            'overbought': _rsiOverbought,
            'oversold': _rsiOversold,
            'applySignalMa': _rsiApplySignalMa,
            'signalMaType': _rsiSignalMaType,
            'signalMaPeriod': _rsiSignalMaPeriod,
          },
        );
      case AlertIndicatorType.macd:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.macd,
          condition: _macdCondition,
          params: {
            'fast': _macdFast,
            'slow': _macdSlow,
            'signal': _macdSignal,
            'source': _macdSource,
            'fastMaType': _macdFastMaType,
            'slowMaType': _macdSlowMaType,
            'signalMaType': _macdSignalMaType,
          },
        );
      case AlertIndicatorType.maCross:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.maCross,
          condition: _maCondition,
          params: {
            'fastPeriod': _maFastPeriod,
            'slowPeriod': _maSlowPeriod,
            'maType': _maType,
            'fastMaType': _maFastMaType,
            'slowMaType': _maSlowMaType,
            'source': _maSource,
          },
        );
      case AlertIndicatorType.bollingerBands:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.bollingerBands,
          condition: _bbCondition,
          params: {
            'period': _bbPeriod,
            'stdDev': _bbStdDev,
            'source': _bbSource,
            'maType': _bbMaType,
            'squeezeThreshold': _bbSqueezeThreshold,
          },
        );
      case AlertIndicatorType.stochastic:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.stochastic,
          condition: _stochCondition,
          params: {
            'kPeriod': _stochK,
            'kSlowing': _stochKSlowing,
            'dPeriod': _stochD,
            'dMaType': _stochDMaType,
            'oversoldLevel': _stochOversold,
            'overboughtLevel': _stochOverbought,
            'oversold': _stochOversold,
            'overbought': _stochOverbought,
          },
        );
      case AlertIndicatorType.supertrend:
        return IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.supertrend,
          condition: _stCondition,
          params: {
            'period': _stPeriod,
            'multiplier': _stMultiplier,
            'source': _stSource,
            'atrSmoothing': _stAtrSmoothing,
            'distanceThreshold': _stDistanceThreshold,
          },
        );
    }
  }

  List<Widget> _buildIndicatorSection(ThemeData theme, bool isDark) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TIMEFRAME',
            style: AppTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            'Evaluates on candle close',
            style: AppTheme.sans(
              fontSize: 11,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _timeframes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, idx) {
            final tf = _timeframes[idx];
            final isSelected =
                _selectedTimeframe.toLowerCase() == tf.toLowerCase();
            return _buildOledChip(
              label: tf.toUpperCase(),
              isSelected: isSelected,
              onTap: () => setState(() => _selectedTimeframe = tf),
            );
          },
        ),
      ),
      const SizedBox(height: 14),

      Text(
        'CHOOSE INDICATOR',
        style: AppTheme.sans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: _t2,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: AlertIndicatorType.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, idx) {
            final ind = AlertIndicatorType.values[idx];
            final isSelected = _selectedIndicator == ind;
            return _buildOledChip(
              label: ind.label,
              isSelected: isSelected,
              onTap: () => setState(() => _selectedIndicator = ind),
            );
          },
        ),
      ),
      const SizedBox(height: 6),
      Text(
        _selectedIndicator.description,
        style: const TextStyle(fontSize: 11, color: _t2),
      ),
      const SizedBox(height: 12),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'CALCULATION VARIABLES & LOGIC',
                    style: AppTheme.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _bl,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _openIndicatorConfigModal(
                    context: context,
                    initialConfig: _buildCurrentIndicatorConfig(),
                    initialTimeframe: _selectedTimeframe,
                    onConfigSaved: (cfg) =>
                        setState(() => _applySavedIndicatorConfig(cfg)),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _bl.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _bl.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: Color(0xFF4DA3FF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tune Parameters',
                          style: AppTheme.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4DA3FF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _buildParamBadges(_buildCurrentIndicatorConfig()),
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0x17FFFFFF), height: 1),
            const SizedBox(height: 14),
            Text(
              'ALERT CONDITION (SIGNAL)',
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _t2,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _buildIndicatorConditionSelector(),
          ],
        ),
      ),
    ];
  }

  Widget _buildIndicatorConditionSelector() {
    switch (_selectedIndicator) {
      case AlertIndicatorType.rsi:
        final isCustomLevel =
            _rsiCondition == 'crossesAboveLevel' ||
            _rsiCondition == 'crossesBelowLevel' ||
            _rsiCondition == 'crossesAbove' ||
            _rsiCondition == 'crossesBelow';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOledDropdown(
              value: _rsiCondition,
              items: const [
                DropdownMenuItem(
                  value: 'crossesBelowOversold',
                  child: Text('Crosses Below Oversold (< Oversold dip)'),
                ),
                DropdownMenuItem(
                  value: 'crossesAboveOversold',
                  child: Text(
                    'Crosses Above Oversold (Recovery / Exit Oversold)',
                  ),
                ),
                DropdownMenuItem(
                  value: 'crossesAboveOverbought',
                  child: Text('Crosses Above Overbought (> Overbought spike)'),
                ),
                DropdownMenuItem(
                  value: 'crossesBelowOverbought',
                  child: Text(
                    'Crosses Below Overbought (Pullback / Exit Overbought)',
                  ),
                ),
                DropdownMenuItem(
                  value: 'crossesAboveLevel',
                  child: Text('Crosses Above Custom Target Level'),
                ),
                DropdownMenuItem(
                  value: 'crossesBelowLevel',
                  child: Text('Crosses Below Custom Target Level'),
                ),
                DropdownMenuItem(
                  value: 'crossesAboveCenterline',
                  child: Text('Crosses Above 50 Centerline (Bullish Momentum)'),
                ),
                DropdownMenuItem(
                  value: 'crossesBelowCenterline',
                  child: Text('Crosses Below 50 Centerline (Bearish Momentum)'),
                ),
                DropdownMenuItem(
                  value: 'centerlineCross',
                  child: Text('Crosses 50 Centerline (Either Direction)'),
                ),
                DropdownMenuItem(
                  value: 'crossesAboveSignalMa',
                  child: Text('Crosses Above Signal MA (MA of RSI)'),
                ),
                DropdownMenuItem(
                  value: 'crossesBelowSignalMa',
                  child: Text('Crosses Below Signal MA (MA of RSI)'),
                ),
                DropdownMenuItem(
                  value: 'inOversold',
                  child: Text('Is in Oversold Zone (< Oversold)'),
                ),
                DropdownMenuItem(
                  value: 'inOverbought',
                  child: Text('Is in Overbought Zone (> Overbought)'),
                ),
                DropdownMenuItem(
                  value: 'inBandRange',
                  child: Text('Is Inside Normal Range (30 - 70)'),
                ),
                DropdownMenuItem(
                  value: 'outsideBandRange',
                  child: Text('Is Outside Normal Range (Extreme Zone)'),
                ),
                DropdownMenuItem(
                  value: 'rsiTurningUp',
                  child: Text('RSI Hooks Upward (Bullish Reversal)'),
                ),
                DropdownMenuItem(
                  value: 'rsiTurningDown',
                  child: Text('RSI Hooks Downward (Bearish Reversal)'),
                ),
              ],
              onChanged: (c) {
                if (c != null) {
                  setState(() {
                    _rsiCondition = c;
                    if (c == 'crossesAboveSignalMa' ||
                        c == 'crossesBelowSignalMa') {
                      _rsiApplySignalMa = true;
                    }
                  });
                }
              },
            ),
            if (isCustomLevel) ...[
              const SizedBox(height: 10),
              _buildNumberStepper(
                label: 'Trigger Level',
                value: _rsiLevel,
                min: 1,
                max: 99,
                step: 1,
                onChanged: (v) => setState(() => _rsiLevel = v.toDouble()),
              ),
            ],
          ],
        );

      case AlertIndicatorType.macd:
        return _buildOledDropdown(
          value: _macdCondition,
          items: const [
            DropdownMenuItem(
              value: 'bullishSignalCross',
              child: Text('MACD Line Crosses Above Signal (Bullish)'),
            ),
            DropdownMenuItem(
              value: 'bearishSignalCross',
              child: Text('MACD Line Crosses Below Signal (Bearish)'),
            ),
            DropdownMenuItem(
              value: 'zeroLineCrossAbove',
              child: Text('MACD Crosses Above Zero Line (Bullish)'),
            ),
            DropdownMenuItem(
              value: 'zeroLineCrossBelow',
              child: Text('MACD Crosses Below Zero Line (Bearish)'),
            ),
            DropdownMenuItem(
              value: 'histFlipPositive',
              child: Text('Histogram Flips Positive (Green)'),
            ),
            DropdownMenuItem(
              value: 'histFlipNegative',
              child: Text('Histogram Flips Negative (Red)'),
            ),
            DropdownMenuItem(
              value: 'histTurnUp',
              child: Text('Histogram Troughs & Turns Up'),
            ),
            DropdownMenuItem(
              value: 'histTurnDown',
              child: Text('Histogram Peaks & Turns Down'),
            ),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _macdCondition = c);
          },
        );

      case AlertIndicatorType.maCross:
        return _buildOledDropdown(
          value: _maCondition,
          items: const [
            DropdownMenuItem(
              value: 'goldenCross',
              child: Text('Golden Cross (Fast Crosses Above Slow)'),
            ),
            DropdownMenuItem(
              value: 'deathCross',
              child: Text('Death Cross (Fast Crosses Below Slow)'),
            ),
            DropdownMenuItem(
              value: 'priceCrossesAbove',
              child: Text('Price Crosses Above Fast MA'),
            ),
            DropdownMenuItem(
              value: 'priceCrossesBelow',
              child: Text('Price Crosses Below Fast MA'),
            ),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _maCondition = c);
          },
        );

      case AlertIndicatorType.bollingerBands:
        return _buildOledDropdown(
          value: _bbCondition,
          items: const [
            DropdownMenuItem(
              value: 'lowerBandTouch',
              child: Text('Price Touches Lower Band (Oversold Bounce)'),
            ),
            DropdownMenuItem(
              value: 'upperBandTouch',
              child: Text('Price Touches Upper Band (Overbought Resistance)'),
            ),
            DropdownMenuItem(
              value: 'squeeze',
              child: Text('Bollinger Band Squeeze (Volatility Contraction)'),
            ),
            DropdownMenuItem(
              value: 'bandwidthExpansion',
              child: Text('Bandwidth Expansion Breakout'),
            ),
            DropdownMenuItem(
              value: 'centerlineCross',
              child: Text('Price Crosses Basis (20 SMA Centerline)'),
            ),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _bbCondition = c);
          },
        );

      case AlertIndicatorType.stochastic:
        return _buildOledDropdown(
          value: _stochCondition,
          items: const [
            DropdownMenuItem(
              value: 'bullishOversoldCross',
              child: Text('%K Crosses Above %D in Oversold Zone (< 20)'),
            ),
            DropdownMenuItem(
              value: 'bearishOverboughtCross',
              child: Text('%K Crosses Below %D in Overbought Zone (> 80)'),
            ),
            DropdownMenuItem(
              value: 'kCrossAboveD',
              child: Text('%K Crosses Above %D (Any Level)'),
            ),
            DropdownMenuItem(
              value: 'kCrossBelowD',
              child: Text('%K Crosses Below %D (Any Level)'),
            ),
            DropdownMenuItem(
              value: 'inOversold',
              child: Text('Is in Oversold Zone (< 20)'),
            ),
            DropdownMenuItem(
              value: 'inOverbought',
              child: Text('Is in Overbought Zone (> 80)'),
            ),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _stochCondition = c);
          },
        );

      case AlertIndicatorType.supertrend:
        return _buildOledDropdown(
          value: _stCondition,
          items: const [
            DropdownMenuItem(
              value: 'bullishFlip',
              child: Text(
                'Trend Flips Bullish (Price Crosses Above Lower Band)',
              ),
            ),
            DropdownMenuItem(
              value: 'bearishFlip',
              child: Text(
                'Trend Flips Bearish (Price Crosses Below Upper Band)',
              ),
            ),
            DropdownMenuItem(
              value: 'touchesUpper',
              child: Text('Price Touches Upper Band'),
            ),
            DropdownMenuItem(
              value: 'touchesLower',
              child: Text('Price Touches Lower Band'),
            ),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _stCondition = c);
          },
        );
    }
  }

  Widget _buildOledDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(canvasColor: const Color(0xFF1C1C1E)),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        dropdownColor: const Color(0xFF1C1C1E),
        style: AppTheme.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF2C2C2E),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0A84FF), width: 1.5),
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildNumberStepper({
    required String label,
    required num value,
    required num min,
    required num max,
    required num step,
    bool isDecimal = false,
    String? unit,
    required ValueChanged<num> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayStr = isDecimal
        ? (value is double
              ? value.toStringAsFixed(value < 0.1 ? 3 : 1)
              : value.toString())
        : value.toInt().toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 16,
            onPressed: () {
              final next = value - step;
              if (next >= min) {
                onChanged(
                  isDecimal
                      ? double.parse(next.toStringAsFixed(3))
                      : next.toInt(),
                );
              }
            },
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final controller = TextEditingController(text: displayStr);
              final typed = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    'Edit $label',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: isDecimal,
                    ),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Enter value ($min - $max)',
                      suffixText: unit,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Set'),
                    ),
                  ],
                ),
              );
              if (typed != null) {
                final parsed = num.tryParse(typed);
                if (parsed != null && parsed >= min && parsed <= max) {
                  onChanged(isDecimal ? parsed.toDouble() : parsed.toInt());
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayStr + (unit != null ? ' $unit' : ''),
                    style: AppTheme.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit_outlined,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            splashRadius: 16,
            onPressed: () {
              final next = value + step;
              if (next <= max) {
                onChanged(
                  isDecimal
                      ? double.parse(next.toStringAsFixed(3))
                      : next.toInt(),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showNewChainDialog() async {
    HapticFeedback.lightImpact();
    final nameCtrl = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              title: Text(
                'New Logic Chain',
                style: AppTheme.sans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Give your new multi-step strategy chain a name to proceed:',
                    style: AppTheme.sans(fontSize: 13, color: _t2),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    style: AppTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. Double Bottom Confirmation',
                      hintStyle: AppTheme.sans(color: _t3, fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFF2C2C2E),
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
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
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: AppTheme.sans(
                      color: _t2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please enter a chain name';
                      });
                      return;
                    }
                    Navigator.pop(ctx);
                    setState(() {
                      _chainNameController.text = name;
                      _chainStages = [
                        ChainStage(
                          id: 'stage_${DateTime.now().millisecondsSinceEpoch}',
                          name: 'Stage 1',
                          timeoutMinutes: _defaultTimeoutMinutes,
                          logicOperator: 'AND',
                          nodes: [
                            ChainNode(
                              id: 'node_${DateTime.now().millisecondsSinceEpoch}',
                              nodeType: AlertType.priceLevel,
                              targetPrice: _selectedPrice,
                              condition: AlertCondition.crossesAbove,
                            ),
                          ],
                        ),
                      ];
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Created new chain: $name',
                          style: AppTheme.sans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        backgroundColor: const Color(0xFF1C1C1E),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bl,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Create Chain',
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
      },
    );
  }

  // ==========================================
  // MULTI-STEP LOGIC CHAIN (TREE BUILDER)
  // ==========================================

  List<Widget> _buildLogicChainSection(ThemeData theme, bool isDark) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'LOGIC CHAIN BUILDER',
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _t2,
                letterSpacing: 0.8,
              ),
            ),
            GestureDetector(
              onTap: _showNewChainDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _bl.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _bl.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 15,
                      color: Color(0xFF4DA3FF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'New Chain',
                      style: AppTheme.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4DA3FF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // Name row card
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Text('Name', style: TextStyle(fontSize: 16, color: _t2)),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _chainNameController,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // Quick Strategy Templates Row
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildStrategyTemplateChip('Breakout & Retest', 'breakout_retest'),
            const SizedBox(width: 8),
            _buildStrategyTemplateChip('RSI Reversal', 'rsi_reversal'),
            const SizedBox(width: 8),
            _buildStrategyTemplateChip('Trend Pullback', 'trend_pullback'),
            const SizedBox(width: 8),
            _buildStrategyTemplateChip('BB Squeeze', 'bb_squeeze_breakout'),
          ],
        ),
      ),
      const SizedBox(height: 10),

      // Default stage timeout card
      GestureDetector(
        onTap: _showTimeoutPicker,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Default stage timeout',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
              Row(
                children: [
                  Text(
                    '$_defaultTimeoutMinutes min',
                    style: AppTheme.mono(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _bl,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: _t3),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),

      // Chain Stages
      ..._chainStages.asMap().entries.map((entry) {
        final stageIdx = entry.key;
        final stage = entry.value;
        final isLastStage = stageIdx == _chainStages.length - 1;

        return Column(
          children: [
            _buildStageCardRestyled(stageIdx, stage),
            if (!isLastStage) _buildConnectorSpine(stageIdx, stage),
          ],
        );
      }),

      const SizedBox(height: 12),

      // + Add Stage dashed button
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: _addStage,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _s3, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: _bl, size: 20),
                const SizedBox(width: 6),
                const Text(
                  'Add Stage',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _bl,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // Bottom Buttons Row: Multi-symbol + Create Chain
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _openMultiSymbolPicker,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: _s2,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Multi-symbol',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  widget.onAlertCreated(
                    symbol: _selectedSymbol,
                    alertType: AlertType.multiStepChain,
                    targetPrice:
                        _chainStages.isNotEmpty &&
                            _chainStages.first.nodes.isNotEmpty
                        ? _chainStages.first.nodes.first.targetPrice
                        : 0.0,
                    condition:
                        _chainStages.isNotEmpty &&
                            _chainStages.first.nodes.isNotEmpty
                        ? _chainStages.first.nodes.first.condition
                        : AlertCondition.crossesAbove,
                    multiStepConfig: MultiStepConfig(stages: _chainStages),
                    timeframe: _selectedTimeframe,
                    note: _chainNameController.text.trim(),
                    ringtoneTitle: _selectedRingtoneTitle,
                    ringtoneUri: _selectedRingtoneUri,
                    drawingId: widget.drawingId,
                    targetSymbols: _selectedCurrencies.toList(),
                    triggerOnCandleClose: _triggerOnCandleClose,
                    cooldownMinutes: _cooldownMinutes,
                  );
                  Navigator.pop(context);
                },
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: _bl,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _bl.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Create Chain',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildStageCardRestyled(int stageIdx, ChainStage stage) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row: blue circle number, Stage Name, Delete icon
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: _bl,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${stageIdx + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (_chainStages.length > 1)
                GestureDetector(
                  onTap: () => _removeStage(stageIdx),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      color: Color(0xFF636366),
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Nodes in this stage
          ...stage.nodes.asMap().entries.map((entry) {
            final nodeIdx = entry.key;
            final node = entry.value;
            final isExpanded = _expandedNodeIds.contains(
              '${stageIdx}_$nodeIdx',
            );

            return Column(
              children: [
                if (nodeIdx > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          final currentOp = node.operatorToPrevious;
                          node.operatorToPrevious = currentOp == 'AND'
                              ? 'OR'
                              : 'AND';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x33BF5AF2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          node.operatorToPrevious,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD58CF7),
                          ),
                        ),
                      ),
                    ),
                  ),
                _buildNodeTile(stageIdx, nodeIdx, stage, node, isExpanded),
              ],
            );
          }),

          // Option to add condition to stage
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => _addNodeToStage(stageIdx),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: _bl),
                    SizedBox(width: 4),
                    Text(
                      '+ Add Condition',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _bl,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    bool isExpanded,
  ) {
    final isPrice = node.nodeType == AlertType.priceLevel;
    final isIndicator = node.nodeType == AlertType.technicalIndicator;
    final isPattern = node.nodeType == AlertType.candlestickPattern;

    final Color tileBg;
    final Widget tileIcon;
    if (isPrice) {
      tileBg = const Color(0x330A84FF);
      tileIcon = const Icon(Icons.remove, color: Color(0xFF4DA3FF), size: 16);
    } else if (isIndicator) {
      tileBg = const Color(0x33BF5AF2);
      tileIcon = const Icon(Icons.waves, color: Color(0xFFD58CF7), size: 16);
    } else {
      tileBg = const Color(0x33FF9F0A);
      tileIcon = const Icon(
        Icons.candlestick_chart,
        color: Color(0xFFFFB340),
        size: 16,
      );
    }

    String displayText = '';
    if (isPrice) {
      final condStr = node.condition == AlertCondition.crossesAbove
          ? 'crosses above'
          : node.condition == AlertCondition.crossesBelow
          ? 'crosses below'
          : 'hits';
      displayText =
          'Price $condStr ${node.targetPrice.toStringAsFixed(_selectedPrecision > 2 ? 4 : 2)}';
    } else if (isIndicator) {
      final period = node.indicatorConfig?.params['period'] ?? 14;
      final level = node.indicatorConfig?.params['level'] ?? 70;
      final indName = node.indicatorConfig?.indicatorType.label ?? 'RSI';
      displayText =
          '$indName($period) > ${level is double ? level.toStringAsFixed(0) : level}';
    } else if (isPattern) {
      final patName = node.candlestickPattern?.label ?? 'Hammer';
      displayText = '$patName · ${node.timeframe} close';
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          final key = '${stageIdx}_$nodeIdx';
          if (_expandedNodeIds.contains(key)) {
            _expandedNodeIds.remove(key);
          } else {
            _expandedNodeIds.add(key);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _s2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: tileIcon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        if (node.isNegated)
                          const TextSpan(
                            text: 'NOT ',
                            style: TextStyle(
                              color: Color(0xFFFF453A),
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        TextSpan(
                          text: displayText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up : Icons.tune_rounded,
                  size: 16,
                  color: _t2,
                ),
              ],
            ),
            if (isExpanded) ...[
              const Divider(color: Color(0x17FFFFFF), height: 16),
              _buildInlineNodeEditor(stageIdx, nodeIdx, stage, node),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectorSpine(int stageIdx, ChainStage stage) {
    return Column(
      children: [
        Container(width: 2, height: 12, color: _s3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _s2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_filled, size: 12, color: _bl),
              const SizedBox(width: 5),
              Text(
                'within ${stage.timeoutMinutes > 0 ? stage.timeoutMinutes : _defaultTimeoutMinutes}m',
                style: AppTheme.mono(
                  fontSize: 12,
                  color: const Color(0xFF4DA3FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(width: 2, height: 12, color: _s3),
      ],
    );
  }

  void _showTimeoutPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _s1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Default Stage Timeout',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              for (final mins in [5, 15, 30, 60, 120, 240, 1440])
                ListTile(
                  title: Text(
                    mins >= 60 ? '${mins ~/ 60} hour(s)' : '$mins minutes',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: _defaultTimeoutMinutes == mins
                      ? const Icon(Icons.check, color: _bl)
                      : null,
                  onTap: () {
                    setState(() {
                      _defaultTimeoutMinutes = mins;
                      for (final s in _chainStages) {
                        s.timeoutMinutes = mins;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAllInstruments() async {
    try {
      final list = await MarketDataApi.getAllSymbols();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _allInstruments = list;
          _instrumentsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _instrumentsLoaded = true);
    }
  }

  void _openMultiSymbolPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MultiSymbolPickerSheet(
        allInstruments: _allInstruments,
        selected: Set.from(_selectedCurrencies),
        currentSymbol: _selectedSymbol,
        onConfirm: (newSet) {
          if (mounted) setState(() => _selectedCurrencies = newSet);
        },
      ),
    );
  }

  void _openInstrumentPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MultiSymbolPickerSheet(
        allInstruments: _allInstruments,
        selected: {_selectedSymbol},
        currentSymbol: _selectedSymbol,
        singleSelect: true,
        onConfirm: (selection) async {
          if (selection.isEmpty) return;
          final symbol = selection.first;
          BiquoteInstrument? instrument;
          for (final item in _allInstruments) {
            if (item.symbol == symbol) {
              instrument = item;
              break;
            }
          }
          BiquoteTick? tick;
          try {
            tick = await widget.biquoteService?.getSingleQuote(symbol);
          } catch (_) {}
          double? livePrice = tick?.mid;
          var precision = tick?.precision ?? instrument?.digits ?? 5;
          if (tick == null) {
            final ticks = await MarketDataApi.getBatchTicks([symbol]);
            final fallback = ticks[symbol];
            livePrice = fallback?.mid;
            precision = fallback?.digits ?? precision;
          }
          if (!mounted) return;
          setState(() {
            _selectedSymbol = symbol;
            _selectedCurrencies = {symbol};
            _selectedPrecision = precision;
            _selectedPrice = livePrice ?? 0;
            if (!_targetManuallyEdited) {
              _targetPrice = _selectedPrice + (_pipValue * 10);
              _priceController.text = _targetPrice.toStringAsFixed(
                _selectedPrecision,
              );
            }
            _condition = AlertCondition.crossesAbove;
            if (!_chainManuallyEdited) {
              _chainStages = _buildDefaultChainStages();
              _syncChainPriceControllers();
            }
          });
          if (livePrice != null && livePrice > 0) {
            _applyLivePrice(livePrice, precision);
          }
          if (tick == null) unawaited(_fetchLivePrice(symbol));
          widget.biquoteService?.subscribe([symbol]);
        },
      ),
    );
  }

  Widget _buildInlineNodeEditor(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  stage.nodes[nodeIdx] = ChainNode(
                    id: node.id,
                    nodeType: node.nodeType,
                    targetPrice: node.targetPrice,
                    condition: node.condition,
                    candlestickPattern: node.candlestickPattern,
                    indicatorConfig: node.indicatorConfig,
                    timeframe: node.timeframe,
                    isNegated: !node.isNegated,
                    operatorToPrevious: node.operatorToPrevious,
                  );
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: node.isNegated ? const Color(0x33FF453A) : _s3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  node.isNegated ? 'NOT active' : '+ NOT invert',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: node.isNegated ? const Color(0xFFFF453A) : _t2,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _nodeTypeChip(
              stageIdx,
              nodeIdx,
              stage,
              node,
              AlertType.priceLevel,
              'Price',
            ),
            const SizedBox(width: 4),
            _nodeTypeChip(
              stageIdx,
              nodeIdx,
              stage,
              node,
              AlertType.candlestickPattern,
              'Pattern',
            ),
            const SizedBox(width: 4),
            _nodeTypeChip(
              stageIdx,
              nodeIdx,
              stage,
              node,
              AlertType.technicalIndicator,
              'Indicator',
            ),
            if (stage.nodes.length > 1) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _removeNodeFromStage(stageIdx, nodeIdx),
                child: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Color(0xFFFF453A),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (node.nodeType == AlertType.priceLevel)
          _buildPriceNodeControls(stageIdx, nodeIdx, stage, node, theme, true)
        else if (node.nodeType == AlertType.candlestickPattern)
          _buildPatternNodeControls(stageIdx, nodeIdx, stage, node, theme, true)
        else
          _buildIndicatorNodeControls(
            stageIdx,
            nodeIdx,
            stage,
            node,
            theme,
            true,
          ),
      ],
    );
  }

  Widget _nodeTypeChip(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    AlertType type,
    String label,
  ) {
    final isSelected = node.nodeType == type;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            ChainNode newNode;
            if (type == AlertType.priceLevel) {
              newNode = ChainNode(
                id: node.id,
                nodeType: AlertType.priceLevel,
                targetPrice: _selectedPrice,
                condition: AlertCondition.crossesAbove,
                isNegated: node.isNegated,
                operatorToPrevious: node.operatorToPrevious,
              );
            } else if (type == AlertType.candlestickPattern) {
              newNode = ChainNode(
                id: node.id,
                nodeType: AlertType.candlestickPattern,
                candlestickPattern: CandlestickPattern.bullishEngulfing,
                timeframe: '15m',
                isNegated: node.isNegated,
                operatorToPrevious: node.operatorToPrevious,
              );
            } else {
              newNode = ChainNode(
                id: node.id,
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.rsi,
                  condition: 'crossesBelowOversold',
                  params: {
                    'period': 14,
                    'source': 'Close',
                    'level': 30.0,
                    'overbought': 70.0,
                    'oversold': 30.0,
                    'applySignalMa': false,
                    'signalMaType': 'EMA',
                    'signalMaPeriod': 9,
                  },
                ),
                timeframe: '15m',
                isNegated: node.isNegated,
                operatorToPrevious: node.operatorToPrevious,
              );
            }
            stage.nodes[nodeIdx] = newNode;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? _bl : _s3,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPriceNodeControls(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Condition Dropdown
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<AlertCondition>(
                initialValue: node.condition,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Condition',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AlertCondition.crossesAbove,
                    child: Text(
                      'Crosses Above',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AlertCondition.crossesBelow,
                    child: Text(
                      'Crosses Below',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  DropdownMenuItem(
                    value: AlertCondition.hits,
                    child: Text(
                      'Hits / Touches',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      stage.nodes[nodeIdx] = ChainNode(
                        id: node.id,
                        nodeType: AlertType.priceLevel,
                        targetPrice: node.targetPrice > 0
                            ? node.targetPrice
                            : _selectedPrice,
                        condition: val,
                        isNegated: node.isNegated,
                        operatorToPrevious: node.operatorToPrevious,
                      );
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Target Price adjustment
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('chain-price-${node.id}'),
                      controller: _chainPriceController(node),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'),
                        ),
                      ],
                      textAlign: TextAlign.center,
                      style: AppTheme.mono(
                        context: context,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Target price',
                        labelStyle: const TextStyle(fontSize: 10),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onChanged: (value) {
                        _chainManuallyEdited = true;
                        final price = double.tryParse(value) ?? 0;
                        setState(() {
                          stage.nodes[nodeIdx] = ChainNode(
                            id: node.id,
                            nodeType: AlertType.priceLevel,
                            targetPrice: price,
                            condition: node.condition,
                            isNegated: node.isNegated,
                            operatorToPrevious: node.operatorToPrevious,
                          );
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: () {
                      final curr = node.targetPrice > 0
                          ? node.targetPrice
                          : _selectedPrice;
                      final next = curr - (_pipValue * 5);
                      _chainManuallyEdited = true;
                      _chainPriceController(node).text = next.toStringAsFixed(
                        _selectedPrecision,
                      );
                      setState(() {
                        stage.nodes[nodeIdx] = ChainNode(
                          id: node.id,
                          nodeType: AlertType.priceLevel,
                          targetPrice: next,
                          condition: node.condition,
                          isNegated: node.isNegated,
                          operatorToPrevious: node.operatorToPrevious,
                        );
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: () {
                      final curr = node.targetPrice > 0
                          ? node.targetPrice
                          : _selectedPrice;
                      final next = curr + (_pipValue * 5);
                      _chainManuallyEdited = true;
                      _chainPriceController(node).text = next.toStringAsFixed(
                        _selectedPrecision,
                      );
                      setState(() {
                        stage.nodes[nodeIdx] = ChainNode(
                          id: node.id,
                          nodeType: AlertType.priceLevel,
                          targetPrice: next,
                          condition: node.condition,
                          isNegated: node.isNegated,
                          operatorToPrevious: node.operatorToPrevious,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPatternNodeControls(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    ThemeData theme,
    bool isDark,
  ) {
    final curPattern =
        node.candlestickPattern ?? CandlestickPattern.bullishEngulfing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<CandlestickPattern>(
                initialValue: curPattern,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Pattern',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                items: CandlestickPattern.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.label,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (p) {
                  if (p != null) {
                    setState(() {
                      stage.nodes[nodeIdx] = ChainNode(
                        id: node.id,
                        nodeType: AlertType.candlestickPattern,
                        candlestickPattern: p,
                        timeframe: node.timeframe,
                        isNegated: node.isNegated,
                        operatorToPrevious: node.operatorToPrevious,
                      );
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // Timeframe
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: node.timeframe,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'TF',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                items: _timeframes.map((tf) {
                  return DropdownMenuItem(
                    value: tf,
                    child: Text(
                      tf.toUpperCase(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
                onChanged: (tf) {
                  if (tf != null) {
                    setState(() {
                      stage.nodes[nodeIdx] = ChainNode(
                        id: node.id,
                        nodeType: AlertType.candlestickPattern,
                        candlestickPattern: curPattern,
                        timeframe: tf,
                        isNegated: node.isNegated,
                        operatorToPrevious: node.operatorToPrevious,
                      );
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIndicatorNodeControls(
    int stageIdx,
    int nodeIdx,
    ChainStage stage,
    ChainNode node,
    ThemeData theme,
    bool isDark,
  ) {
    final curConfig =
        node.indicatorConfig ??
        IndicatorAlertConfig(
          indicatorType: AlertIndicatorType.rsi,
          condition: 'crossesBelow',
          params: {
            'period': 14,
            'source': 'Close',
            'level': 30.0,
            'overbought': 70.0,
            'oversold': 30.0,
            'applySignalMa': false,
            'signalMaType': 'EMA',
            'signalMaPeriod': 9,
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Indicator Type Dropdown
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<AlertIndicatorType>(
                initialValue: curConfig.indicatorType,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Indicator',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                items: AlertIndicatorType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(
                      type.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
                onChanged: (type) {
                  if (type != null) {
                    IndicatorAlertConfig newConfig;
                    switch (type) {
                      case AlertIndicatorType.rsi:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.rsi,
                          condition: 'crossesBelow',
                          params: {
                            'period': 14,
                            'source': 'Close',
                            'level': 30.0,
                            'overbought': 70.0,
                            'oversold': 30.0,
                            'applySignalMa': false,
                            'signalMaType': 'EMA',
                            'signalMaPeriod': 9,
                          },
                        );
                        break;
                      case AlertIndicatorType.macd:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.macd,
                          condition: 'bullishSignalCross',
                          params: {
                            'fast': 12,
                            'slow': 26,
                            'signal': 9,
                            'source': 'Close',
                            'fastMaType': 'EMA',
                            'slowMaType': 'EMA',
                            'signalMaType': 'EMA',
                          },
                        );
                        break;
                      case AlertIndicatorType.maCross:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.maCross,
                          condition: 'goldenCross',
                          params: {
                            'fastPeriod': 50,
                            'slowPeriod': 200,
                            'maType': 'EMA',
                            'fastMaType': 'EMA',
                            'slowMaType': 'EMA',
                            'source': 'Close',
                          },
                        );
                        break;
                      case AlertIndicatorType.bollingerBands:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.bollingerBands,
                          condition: 'lowerBandTouch',
                          params: {
                            'period': 20,
                            'stdDev': 2.0,
                            'source': 'Close',
                            'maType': 'SMA',
                            'squeezeThreshold': 0.015,
                          },
                        );
                        break;
                      case AlertIndicatorType.stochastic:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.stochastic,
                          condition: 'bullishOversoldCross',
                          params: {
                            'kPeriod': 14,
                            'kSlowing': 3,
                            'dPeriod': 3,
                            'dMaType': 'SMA',
                            'oversoldLevel': 20.0,
                            'overboughtLevel': 80.0,
                          },
                        );
                        break;
                      case AlertIndicatorType.supertrend:
                        newConfig = IndicatorAlertConfig(
                          indicatorType: AlertIndicatorType.supertrend,
                          condition: 'bullishFlip',
                          params: {
                            'period': 10,
                            'multiplier': 3.0,
                            'source': 'HL2',
                            'atrSmoothing': 'RMA',
                            'distanceThreshold': 1.0,
                          },
                        );
                        break;
                    }
                    setState(() {
                      stage.nodes[nodeIdx] = ChainNode(
                        id: node.id,
                        nodeType: AlertType.technicalIndicator,
                        indicatorConfig: newConfig,
                        timeframe: node.timeframe,
                        isNegated: node.isNegated,
                        operatorToPrevious: node.operatorToPrevious,
                      );
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            // Timeframe Dropdown
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: node.timeframe,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'TF',
                  labelStyle: const TextStyle(fontSize: 11),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                items: _timeframes.map((tf) {
                  return DropdownMenuItem(
                    value: tf,
                    child: Text(
                      tf.toUpperCase(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
                onChanged: (tf) {
                  if (tf != null) {
                    setState(() {
                      stage.nodes[nodeIdx] = ChainNode(
                        id: node.id,
                        nodeType: AlertType.technicalIndicator,
                        indicatorConfig: curConfig,
                        timeframe: tf,
                        isNegated: node.isNegated,
                        operatorToPrevious: node.operatorToPrevious,
                      );
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Pop-up Trigger Card: Opens full parametric config
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'PARAMETERS & CALCULATION VARIABLES:',
                      style: AppTheme.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.amber,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openIndicatorConfigModal(
                      context: context,
                      stage: stage,
                      node: node,
                      nodeIdx: nodeIdx,
                    ),
                    icon: const Icon(Icons.tune, size: 12, color: Colors.amber),
                    label: const Text(
                      'Configure Variables',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      side: const BorderSide(color: Colors.amber),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Detailed variable chips
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _buildParamBadges(curConfig),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openIndicatorConfigModal({
    required BuildContext context,
    ChainStage? stage,
    ChainNode? node,
    int? nodeIdx,
    IndicatorAlertConfig? initialConfig,
    String? initialTimeframe,
    ValueChanged<IndicatorAlertConfig>? onConfigSaved,
  }) {
    final curConfig =
        node?.indicatorConfig ??
        initialConfig ??
        _buildCurrentIndicatorConfig();

    AlertIndicatorType tempType = curConfig.indicatorType;
    String tempCondition = curConfig.condition;
    String tempTimeframe =
        node?.timeframe ?? initialTimeframe ?? _selectedTimeframe;
    Map<String, dynamic> tempParams = Map<String, dynamic>.from(
      curConfig.params,
    );

    if (tempType == AlertIndicatorType.rsi) {
      tempParams.putIfAbsent('period', () => 14);
      tempParams.putIfAbsent('source', () => 'Close');
      tempParams.putIfAbsent('smoothingType', () => 'RMA');
      tempParams.putIfAbsent('level', () => 30.0);
      tempParams.putIfAbsent('overbought', () => 70.0);
      tempParams.putIfAbsent('oversold', () => 30.0);
      tempParams.putIfAbsent('applySignalMa', () => false);
      tempParams.putIfAbsent('signalMaType', () => 'EMA');
      tempParams.putIfAbsent('signalMaPeriod', () => 9);
    } else if (tempType == AlertIndicatorType.macd) {
      tempParams.putIfAbsent('fast', () => 12);
      tempParams.putIfAbsent('slow', () => 26);
      tempParams.putIfAbsent('signal', () => 9);
      tempParams.putIfAbsent('source', () => 'Close');
      tempParams.putIfAbsent('fastMaType', () => 'EMA');
      tempParams.putIfAbsent('slowMaType', () => 'EMA');
      tempParams.putIfAbsent('signalMaType', () => 'EMA');
    } else if (tempType == AlertIndicatorType.maCross) {
      tempParams.putIfAbsent('fastPeriod', () => 50);
      tempParams.putIfAbsent('slowPeriod', () => 200);
      tempParams.putIfAbsent('maType', () => 'EMA');
      tempParams.putIfAbsent('fastMaType', () => 'EMA');
      tempParams.putIfAbsent('slowMaType', () => 'EMA');
      tempParams.putIfAbsent('source', () => 'Close');
    } else if (tempType == AlertIndicatorType.bollingerBands) {
      tempParams.putIfAbsent('period', () => 20);
      tempParams.putIfAbsent('stdDev', () => 2.0);
      tempParams.putIfAbsent('source', () => 'Close');
      tempParams.putIfAbsent('maType', () => 'SMA');
      tempParams.putIfAbsent('squeezeThreshold', () => 0.015);
    } else if (tempType == AlertIndicatorType.stochastic) {
      tempParams.putIfAbsent('kPeriod', () => 14);
      tempParams.putIfAbsent('kSlowing', () => 3);
      tempParams.putIfAbsent('dPeriod', () => 3);
      tempParams.putIfAbsent('dMaType', () => 'SMA');
      tempParams.putIfAbsent('oversoldLevel', () => 20.0);
      tempParams.putIfAbsent('overboughtLevel', () => 80.0);
    } else if (tempType == AlertIndicatorType.supertrend) {
      tempParams.putIfAbsent('period', () => 10);
      tempParams.putIfAbsent('multiplier', () => 3.0);
      tempParams.putIfAbsent('source', () => 'HL2');
      tempParams.putIfAbsent('atrSmoothing', () => 'RMA');
      tempParams.putIfAbsent('distanceThreshold', () => 1.0);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C0C0E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune,
                                color: Color(0xFF0A84FF),
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${tempType.label.toUpperCase()} CONFIGURATION',
                                style: AppTheme.sans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.white70,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      Text(
                        'Full parametric control over calculation variables, price source, and condition logic.',
                        style: AppTheme.sans(fontSize: 12, color: _t2),
                      ),
                      const SizedBox(height: 16),

                      // Indicator Type Selector Tabs
                      Text(
                        'SELECT INDICATOR',
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _t2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AlertIndicatorType.values.map((type) {
                          final isSelected = tempType == type;
                          return _buildOledChip(
                            label: type.label,
                            isSelected: isSelected,
                            onTap: () {
                              setModalState(() {
                                tempType = type;
                                switch (type) {
                                  case AlertIndicatorType.rsi:
                                    tempCondition = 'crossesBelow';
                                    tempParams = {
                                      'period': 14,
                                      'source': 'Close',
                                      'level': 30.0,
                                      'overbought': 70.0,
                                      'oversold': 30.0,
                                      'applySignalMa': false,
                                      'signalMaType': 'EMA',
                                      'signalMaPeriod': 9,
                                    };
                                    break;
                                  case AlertIndicatorType.macd:
                                    tempCondition = 'bullishSignalCross';
                                    tempParams = {
                                      'fast': 12,
                                      'slow': 26,
                                      'signal': 9,
                                      'source': 'Close',
                                      'fastMaType': 'EMA',
                                      'slowMaType': 'EMA',
                                      'signalMaType': 'EMA',
                                    };
                                    break;
                                  case AlertIndicatorType.maCross:
                                    tempCondition = 'goldenCross';
                                    tempParams = {
                                      'fastPeriod': 50,
                                      'slowPeriod': 200,
                                      'maType': 'EMA',
                                      'fastMaType': 'EMA',
                                      'slowMaType': 'EMA',
                                      'source': 'Close',
                                    };
                                    break;
                                  case AlertIndicatorType.bollingerBands:
                                    tempCondition = 'lowerBandTouch';
                                    tempParams = {
                                      'period': 20,
                                      'stdDev': 2.0,
                                      'source': 'Close',
                                      'maType': 'SMA',
                                      'squeezeThreshold': 0.015,
                                    };
                                    break;
                                  case AlertIndicatorType.stochastic:
                                    tempCondition = 'bullishOversoldCross';
                                    tempParams = {
                                      'kPeriod': 14,
                                      'kSlowing': 3,
                                      'dPeriod': 3,
                                      'dMaType': 'SMA',
                                      'oversoldLevel': 20.0,
                                      'overboughtLevel': 80.0,
                                    };
                                    break;
                                  case AlertIndicatorType.supertrend:
                                    tempCondition = 'bullishFlip';
                                    tempParams = {
                                      'period': 10,
                                      'multiplier': 3.0,
                                      'source': 'HL2',
                                      'atrSmoothing': 'RMA',
                                      'distanceThreshold': 1.0,
                                    };
                                    break;
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),

                      // Timeframe Selector
                      Text(
                        'EVALUATION TIMEFRAME',
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _t2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _timeframes.map((tf) {
                            final isSel = tempTimeframe == tf;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _buildOledChip(
                                label: tf.toUpperCase(),
                                isSelected: isSel,
                                onTap: () =>
                                    setModalState(() => tempTimeframe = tf),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const Divider(height: 28, color: Color(0x17FFFFFF)),

                      // Specific Parametric Controls for selected indicator
                      if (tempType == AlertIndicatorType.rsi) ...[
                        _buildRsiParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ] else if (tempType == AlertIndicatorType.macd) ...[
                        _buildMacdParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ] else if (tempType == AlertIndicatorType.maCross) ...[
                        _buildMaCrossParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ] else if (tempType ==
                          AlertIndicatorType.bollingerBands) ...[
                        _buildBollingerParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ] else if (tempType == AlertIndicatorType.stochastic) ...[
                        _buildStochParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ] else ...[
                        _buildSupertrendParamControls(
                          setModalState,
                          tempParams,
                          tempCondition,
                          (c) => setModalState(() => tempCondition = c),
                          theme,
                          isDark,
                        ),
                      ],

                      const SizedBox(height: 24),
                      // Submit / Apply Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final newConfig = IndicatorAlertConfig(
                              indicatorType: tempType,
                              condition: tempCondition,
                              params: tempParams,
                            );
                            if (stage != null &&
                                node != null &&
                                nodeIdx != null) {
                              setState(() {
                                stage.nodes[nodeIdx] = ChainNode(
                                  id: node.id,
                                  nodeType: AlertType.technicalIndicator,
                                  indicatorConfig: newConfig,
                                  timeframe: tempTimeframe,
                                  isNegated: node.isNegated,
                                  operatorToPrevious: node.operatorToPrevious,
                                );
                              });
                            } else if (onConfigSaved != null) {
                              onConfigSaved(newConfig);
                            }
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text(
                            'APPLY & SAVE PARAMETERS',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRsiParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    final bool applySignalMa = params['applySignalMa'] ?? false;
    final bool isCustomLevel =
        condition == 'crossesAboveLevel' ||
        condition == 'crossesBelowLevel' ||
        condition == 'crossesAbove' ||
        condition == 'crossesBelow';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModalStepper(
          'RSI Period (Length)',
          params['period'] ?? 14,
          2,
          200,
          (v) => setModalState(() => params['period'] = v),
        ),
        _buildModalSourceChips(
          params['source'] ?? 'Close',
          (s) => setModalState(() => params['source'] = s),
        ),
        const SizedBox(height: 6),

        // Smoothing Type
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(
                'Smoothing:',
                style: AppTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              ...['RMA', 'EMA', 'SMA', 'WMA'].map((sm) {
                final isSel = (params['smoothingType'] ?? 'RMA') == sm;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(sm, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (_) =>
                        setModalState(() => params['smoothingType'] = sm),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Trigger condition selection
        Text(
          'TRIGGER CONDITION / SIGNAL MIX',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'crossesBelowOversold',
              child: Text(
                'Crosses Below Oversold Level (< Oversold dip)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesAboveOversold',
              child: Text(
                'Crosses Above Oversold Level (Recovery / Exit Oversold)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesAboveOverbought',
              child: Text(
                'Crosses Above Overbought Level (> Overbought spike)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesBelowOverbought',
              child: Text(
                'Crosses Below Overbought Level (Pullback / Exit Overbought)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesAboveLevel',
              child: Text(
                'Crosses Above Custom Target Level',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesBelowLevel',
              child: Text(
                'Crosses Below Custom Target Level',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesAboveCenterline',
              child: Text(
                'Crosses Above 50 Centerline (Bullish Momentum Shift)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesBelowCenterline',
              child: Text(
                'Crosses Below 50 Centerline (Bearish Momentum Shift)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'centerlineCross',
              child: Text(
                'Crosses 50 Centerline (Either Direction)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesAboveSignalMa',
              child: Text(
                'Crosses Above Signal MA (MA of RSI line)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'crossesBelowSignalMa',
              child: Text(
                'Crosses Below Signal MA (MA of RSI line)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inOversold',
              child: Text(
                'Is in Oversold Zone (< Oversold)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inOverbought',
              child: Text(
                'Is in Overbought Zone (> Overbought)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inBandRange',
              child: Text(
                'Is Inside Normal Range (Between Oversold & Overbought)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'outsideBandRange',
              child: Text(
                'Is Outside Normal Range (Extreme Zone)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'rsiTurningUp',
              child: Text(
                'RSI Hooks Upward (Bullish Momentum Reversal)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'rsiTurningDown',
              child: Text(
                'RSI Hooks Downward (Bearish Momentum Exhaustion)',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) {
              onConditionChanged(c);
              if (c == 'crossesAboveSignalMa' || c == 'crossesBelowSignalMa') {
                setModalState(() => params['applySignalMa'] = true);
              }
            }
          },
        ),
        const SizedBox(height: 10),

        if (isCustomLevel) ...[
          _buildModalStepper(
            'Custom Target Level',
            (params['level'] ?? 30.0).toDouble(),
            1.0,
            99.0,
            (v) => setModalState(() => params['level'] = v),
            isDecimal: true,
            step: 1.0,
          ),
        ],
        _buildModalStepper(
          'Oversold Threshold',
          (params['oversold'] ?? 30.0).toDouble(),
          5.0,
          50.0,
          (v) => setModalState(() {
            params['oversold'] = v;
            if (!isCustomLevel) params['level'] = v;
          }),
          isDecimal: true,
          step: 1.0,
        ),
        _buildModalStepper(
          'Overbought Threshold',
          (params['overbought'] ?? 70.0).toDouble(),
          50.0,
          95.0,
          (v) => setModalState(() {
            params['overbought'] = v;
          }),
          isDecimal: true,
          step: 1.0,
        ),

        const Divider(height: 20),
        // Signal MA Toggle & Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Apply Moving Average on RSI (MA of RSI)',
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Calculates moving average directly on RSI curve',
                    style: AppTheme.sans(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: applySignalMa,
              activeThumbColor: Colors.amber,
              onChanged: (v) =>
                  setModalState(() => params['applySignalMa'] = v),
            ),
          ],
        ),
        if (applySignalMa) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Signal MA Type:',
                style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              ...['EMA', 'SMA', 'WMA'].map((t) {
                final isSel = (params['signalMaType'] ?? 'EMA') == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t, style: const TextStyle(fontSize: 11)),
                    selected: isSel,
                    onSelected: (_) =>
                        setModalState(() => params['signalMaType'] = t),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
            ],
          ),
          _buildModalStepper(
            'Signal MA Period',
            params['signalMaPeriod'] ?? 9,
            2,
            100,
            (v) => setModalState(() => params['signalMaPeriod'] = v),
          ),
        ],
      ],
    );
  }

  Widget _buildMacdParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Fast MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['EMA', 'SMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: (params['fastMaType'] ?? 'EMA') == t,
                  onSelected: (_) =>
                      setModalState(() => params['fastMaType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Fast MA Period',
          params['fast'] ?? 12,
          2,
          200,
          (v) => setModalState(() => params['fast'] = v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Slow MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['EMA', 'SMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: (params['slowMaType'] ?? 'EMA') == t,
                  onSelected: (_) =>
                      setModalState(() => params['slowMaType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Slow MA Period',
          params['slow'] ?? 26,
          5,
          500,
          (v) => setModalState(() => params['slow'] = v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Signal MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['EMA', 'SMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: (params['signalMaType'] ?? 'EMA') == t,
                  onSelected: (_) =>
                      setModalState(() => params['signalMaType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Signal MA Period',
          params['signal'] ?? 9,
          1,
          100,
          (v) => setModalState(() => params['signal'] = v),
        ),
        _buildModalSourceChips(
          params['source'] ?? 'Close',
          (s) => setModalState(() => params['source'] = s),
        ),
        const SizedBox(height: 10),

        Text(
          'TRIGGER CONDITION / SIGNAL',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'bullishSignalCross',
              child: Text(
                'Bullish Signal Cross (MACD > Signal)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'bearishSignalCross',
              child: Text(
                'Bearish Signal Cross (MACD < Signal)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'zeroLineCrossAbove',
              child: Text(
                'Zero Line Cross Above (MACD > 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'zeroLineCrossBelow',
              child: Text(
                'Zero Line Cross Below (MACD < 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'zeroLineCross',
              child: Text(
                'Zero Line Crossover (Any direction)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'signalZeroCrossAbove',
              child: Text(
                'Signal Line Crosses Above Zero',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'signalZeroCrossBelow',
              child: Text(
                'Signal Line Crosses Below Zero',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramFlipPositive',
              child: Text(
                'Histogram Flips Positive (> 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramFlipNegative',
              child: Text(
                'Histogram Flips Negative (< 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdAboveSignal',
              child: Text(
                'State: MACD Above Signal (Bullish)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdBelowSignal',
              child: Text(
                'State: MACD Below Signal (Bearish)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdAboveZero',
              child: Text(
                'State: MACD Above Zero (Bullish Zone)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdBelowZero',
              child: Text(
                'State: MACD Below Zero (Bearish Zone)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramPositive',
              child: Text(
                'State: Histogram Positive (> 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramNegative',
              child: Text(
                'State: Histogram Negative (< 0)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramTurningUp',
              child: Text(
                'Momentum: Histogram Turning Up (Hook)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'histogramTurningDown',
              child: Text(
                'Momentum: Histogram Turning Down (Hook)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdTurningUp',
              child: Text(
                'Momentum: MACD Line Turning Up',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'macdTurningDown',
              child: Text(
                'Momentum: MACD Line Turning Down',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) onConditionChanged(c);
          },
        ),
      ],
    );
  }

  Widget _buildMaCrossParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Fast MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['EMA', 'SMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected:
                      (params['fastMaType'] ?? params['maType'] ?? 'EMA') == t,
                  onSelected: (_) => setModalState(() {
                    params['fastMaType'] = t;
                    params['maType'] = t;
                  }),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Fast MA Period',
          params['fastPeriod'] ?? 50,
          1,
          500,
          (v) => setModalState(() => params['fastPeriod'] = v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              'Slow MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['EMA', 'SMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected:
                      (params['slowMaType'] ?? params['maType'] ?? 'EMA') == t,
                  onSelected: (_) =>
                      setModalState(() => params['slowMaType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Slow MA Period',
          params['slowPeriod'] ?? 200,
          2,
          1000,
          (v) => setModalState(() => params['slowPeriod'] = v),
        ),
        _buildModalSourceChips(
          params['source'] ?? 'Close',
          (s) => setModalState(() => params['source'] = s),
        ),
        const SizedBox(height: 10),

        Text(
          'TRIGGER CONDITION / SIGNAL',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'goldenCross',
              child: Text(
                'Bullish Golden Cross (Fast crosses above Slow)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'deathCross',
              child: Text(
                'Bearish Death Cross (Fast crosses below Slow)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'maCross',
              child: Text(
                'Any MA Crossover (Fast vs Slow)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesAboveFast',
              child: Text(
                'Price crosses above Fast MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesBelowFast',
              child: Text(
                'Price crosses below Fast MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesAboveSlow',
              child: Text(
                'Price crosses above Slow MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesBelowSlow',
              child: Text(
                'Price crosses below Slow MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'fastAboveSlow',
              child: Text(
                'State: Fast MA > Slow MA (Bullish Alignment)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'fastBelowSlow',
              child: Text(
                'State: Fast MA < Slow MA (Bearish Alignment)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceAboveFast',
              child: Text(
                'State: Price > Fast MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceBelowFast',
              child: Text(
                'State: Price < Fast MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceAboveSlow',
              child: Text(
                'State: Price > Slow MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceBelowSlow',
              child: Text(
                'State: Price < Slow MA',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceAboveBoth',
              child: Text(
                'State: Price above Both Fast & Slow MAs',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceBelowBoth',
              child: Text(
                'State: Price below Both Fast & Slow MAs',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceBetweenMAs',
              child: Text(
                'State: Price between Fast & Slow MAs (Pullback)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'fastTurningUp',
              child: Text(
                'Momentum: Fast MA hooks Upward (Inflection)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'fastTurningDown',
              child: Text(
                'Momentum: Fast MA hooks Downward (Inflection)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'slowTurningUp',
              child: Text(
                'Momentum: Slow MA hooks Upward (Trend Turn)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'slowTurningDown',
              child: Text(
                'Momentum: Slow MA hooks Downward (Trend Turn)',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) onConditionChanged(c);
          },
        ),
      ],
    );
  }

  Widget _buildBollingerParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Basis MA: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['SMA', 'EMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: (params['maType'] ?? 'SMA') == t,
                  onSelected: (_) => setModalState(() => params['maType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        _buildModalStepper(
          'Band Period',
          params['period'] ?? 20,
          2,
          200,
          (v) => setModalState(() => params['period'] = v),
        ),
        _buildModalStepper(
          'StdDev Multiplier',
          (params['stdDev'] ?? 2.0).toDouble(),
          0.1,
          5.0,
          (v) => setModalState(() => params['stdDev'] = v),
          isDecimal: true,
          step: 0.1,
        ),
        _buildModalSourceChips(
          params['source'] ?? 'Close',
          (s) => setModalState(() => params['source'] = s),
        ),
        _buildModalStepper(
          'Squeeze Threshold %',
          ((params['squeezeThreshold'] ?? 0.015) as num).toDouble() * 100,
          0.1,
          10.0,
          (v) => setModalState(() => params['squeezeThreshold'] = v / 100.0),
          isDecimal: true,
          step: 0.1,
          unit: '%',
        ),
        const SizedBox(height: 10),

        Text(
          'TRIGGER CONDITION / SIGNAL',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'lowerBandTouch',
              child: Text(
                'Price crosses below Lower Band (Oversold Dip)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesAboveLower',
              child: Text(
                'Price bounces back above Lower Band (Rebound)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'upperBandTouch',
              child: Text(
                'Price crosses above Upper Band (Overbought Breakout)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceCrossesBelowUpper',
              child: Text(
                'Price falls back below Upper Band (Rejection)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'middleBandCrossAbove',
              child: Text(
                'Price crosses above Middle Basis (Bullish)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'middleBandCrossBelow',
              child: Text(
                'Price crosses below Middle Basis (Bearish)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'middleBandCross',
              child: Text(
                'Price crosses Middle Basis (Any direction)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceAboveUpper',
              child: Text(
                'State: Price > Upper Band (Riding upper band)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceBelowLower',
              child: Text(
                'State: Price < Lower Band (Riding lower band)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceInsideBands',
              child: Text(
                'State: Price inside Bands (Normal volatility)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceInUpperHalf',
              child: Text(
                'State: Price in Upper Channel (Middle to Upper)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceInLowerHalf',
              child: Text(
                'State: Price in Lower Channel (Lower to Middle)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'squeeze',
              child: Text(
                'Volatility Squeeze (BW <= Threshold)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'squeezeBreakout',
              child: Text(
                'Squeeze Breakout / Volatility Explosion',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'bandwidthExpanding',
              child: Text(
                'Bandwidth Expanding (Trending Volatility)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'bandwidthContracting',
              child: Text(
                'Bandwidth Contracting (Volatility Decay)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'percentBCrossesAbove80',
              child: Text(
                '%B crosses above 0.80 (Overbought zone)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'percentBCrossesBelow20',
              child: Text(
                '%B crosses below 0.20 (Oversold zone)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'percentBCrossesAboveCenter',
              child: Text(
                '%B crosses above 0.50 (Centerline Cross)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'percentBCrossesBelowCenter',
              child: Text(
                '%B crosses below 0.50 (Centerline Cross)',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) onConditionChanged(c);
          },
        ),
      ],
    );
  }

  Widget _buildStochParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    final double osVal = (params['oversoldLevel'] ?? params['oversold'] ?? 20)
        .toDouble();
    final double obVal =
        (params['overboughtLevel'] ?? params['overbought'] ?? 80).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModalStepper(
          '%K Lookback Period',
          params['kPeriod'] ?? 14,
          1,
          100,
          (v) => setModalState(() => params['kPeriod'] = v),
        ),
        _buildModalStepper(
          '%K Slowing (Smoothing)',
          params['kSlowing'] ?? 3,
          1,
          50,
          (v) => setModalState(() => params['kSlowing'] = v),
        ),
        _buildModalStepper(
          '%D Signal MA Period',
          params['dPeriod'] ?? 3,
          1,
          50,
          (v) => setModalState(() => params['dPeriod'] = v),
        ),
        Row(
          children: [
            Text(
              '%D MA Type: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['SMA', 'EMA', 'WMA'].map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  selected: (params['dMaType'] ?? 'SMA') == t,
                  onSelected: (_) => setModalState(() => params['dMaType'] = t),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildModalStepper(
          'Oversold Level',
          osVal,
          5.0,
          45.0,
          (v) => setModalState(() {
            params['oversoldLevel'] = v;
            params['oversold'] = v;
          }),
          isDecimal: true,
          step: 1.0,
        ),
        _buildModalStepper(
          'Overbought Level',
          obVal,
          55.0,
          95.0,
          (v) => setModalState(() {
            params['overboughtLevel'] = v;
            params['overbought'] = v;
          }),
          isDecimal: true,
          step: 1.0,
        ),
        const SizedBox(height: 10),

        Text(
          'TRIGGER CONDITION / SIGNAL',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            const DropdownMenuItem(
              value: 'bullishCross',
              child: Text(
                'Bullish Cross (%K crosses above %D)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'bearishCross',
              child: Text(
                'Bearish Cross (%K crosses below %D)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'bullishOversoldCross',
              child: Text(
                'Bullish Cross in Oversold (< ${osVal.toInt()})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'bearishOverboughtCross',
              child: Text(
                'Bearish Cross in Overbought (> ${obVal.toInt()})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'kCrossesAboveOversold',
              child: Text(
                '%K crosses above Oversold level (${osVal.toInt()}) - Rebound',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'kCrossesBelowOversold',
              child: Text(
                '%K crosses below Oversold level (${osVal.toInt()}) - Dip',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'kCrossesAboveOverbought',
              child: Text(
                '%K crosses above Overbought level (${osVal.toInt()}) - Surge',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'kCrossesBelowOverbought',
              child: Text(
                '%K crosses below Overbought level (${obVal.toInt()}) - Pullback',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kCrossesAbove50',
              child: Text(
                '%K crosses above 50 Centerline (Bullish Momentum)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kCrossesBelow50',
              child: Text(
                '%K crosses below 50 Centerline (Bearish Momentum)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'centerlineCross',
              child: Text(
                '%K crosses 50 Centerline (Either Direction)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kAboveD',
              child: Text(
                'State: %K > %D (Bullish Alignment)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kBelowD',
              child: Text(
                'State: %K < %D (Bearish Alignment)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inOversold',
              child: Text(
                'State: %K in Oversold Zone (< ${osVal.toInt()})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inOverbought',
              child: Text(
                'State: %K in Overbought Zone (> ${obVal.toInt()})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'inNeutralBand',
              child: Text(
                'State: %K in Neutral Channel (${osVal.toInt()} - ${obVal.toInt()})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kTurningUp',
              child: Text(
                'Momentum: %K hooks Upward (Inflection)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'kTurningDown',
              child: Text(
                'Momentum: %K hooks Downward (Inflection)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'dTurningUp',
              child: Text(
                'Momentum: %D line hooks Upward',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'dTurningDown',
              child: Text(
                'Momentum: %D line hooks Downward',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) onConditionChanged(c);
          },
        ),
      ],
    );
  }

  Widget _buildSupertrendParamControls(
    StateSetter setModalState,
    Map<String, dynamic> params,
    String condition,
    ValueChanged<String> onConditionChanged,
    ThemeData theme,
    bool isDark,
  ) {
    final double dist = (params['distanceThreshold'] ?? 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModalStepper(
          'ATR Period',
          params['period'] ?? 10,
          1,
          100,
          (v) => setModalState(() => params['period'] = v),
        ),
        _buildModalStepper(
          'Multiplier',
          (params['multiplier'] ?? 3.0).toDouble(),
          0.5,
          10.0,
          (v) => setModalState(() => params['multiplier'] = v),
          isDecimal: true,
          step: 0.1,
        ),
        Row(
          children: [
            Text(
              'ATR Smoothing: ',
              style: AppTheme.sans(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            ...['RMA', 'SMA', 'EMA', 'WMA'].map(
              (sm) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(sm, style: const TextStyle(fontSize: 10)),
                  selected: (params['atrSmoothing'] ?? 'RMA') == sm,
                  onSelected: (_) =>
                      setModalState(() => params['atrSmoothing'] = sm),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildModalSourceChips(
          params['source'] ?? 'HL2',
          (src) => setModalState(() => params['source'] = src),
        ),
        _buildModalStepper(
          'Distance Threshold',
          dist,
          0.1,
          10.0,
          (v) => setModalState(() => params['distanceThreshold'] = v),
          isDecimal: true,
          step: 0.1,
          unit: '%',
        ),
        const SizedBox(height: 10),

        Text(
          'TRIGGER CONDITION / SIGNAL',
          style: AppTheme.sans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: condition,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            const DropdownMenuItem(
              value: 'bullishFlip',
              child: Text(
                'Bullish Trend Flip (Buy Signal)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'bearishFlip',
              child: Text(
                'Bearish Trend Flip (Sell Signal)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'trendFlip',
              child: Text(
                'Trend Direction Reversal (Any Flip)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceCrossesAboveTrail',
              child: Text(
                'Price crosses above Trailing Stop',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceCrossesBelowTrail',
              child: Text(
                'Price crosses below Trailing Stop',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceTouchesTrail',
              child: Text(
                'Price tests / touches Trailing Stop (S/R Test)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceBouncesOffTrail',
              child: Text(
                'Price tests Trail & Bounces in Trend Direction',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'inBullishTrend',
              child: Text(
                'State: Active Bullish Trend (Green Trail)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'inBearishTrend',
              child: Text(
                'State: Active Bearish Trend (Red Trail)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceAboveTrail',
              child: Text(
                'State: Price > Trailing Stop',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'priceBelowTrail',
              child: Text(
                'State: Price < Trailing Stop',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'trailRising',
              child: Text(
                'Momentum: Trailing Stop Rising (Tightening)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'trailFalling',
              child: Text(
                'Momentum: Trailing Stop Falling (Tightening)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const DropdownMenuItem(
              value: 'trailFlat',
              child: Text(
                'State: Trailing Stop Flat / Holding Level',
                style: TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceDistanceGreaterThan',
              child: Text(
                'Overextended (Distance >= ${dist.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            DropdownMenuItem(
              value: 'priceDistanceLessThan',
              child: Text(
                'Near Trail / Low Risk (Distance <= ${dist.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          onChanged: (c) {
            if (c != null) onConditionChanged(c);
          },
        ),
      ],
    );
  }

  Widget _buildModalStepper(
    String label,
    num value,
    num min,
    num max,
    ValueChanged<num> onChanged, {
    bool isDecimal = false,
    double step = 1.0,
    String? unit,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTheme.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                color: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = value - step;
                  if (next >= min) {
                    onChanged(
                      isDecimal
                          ? double.parse(next.toStringAsFixed(3))
                          : next.toInt(),
                    );
                  }
                },
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () async {
                  final displayStr = isDecimal
                      ? (value is double
                            ? value.toStringAsFixed(value < 0.1 ? 3 : 1)
                            : value.toString())
                      : value.toInt().toString();
                  final controller = TextEditingController(text: displayStr);
                  final typed = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        'Edit $label',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: TextField(
                        controller: controller,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: isDecimal,
                        ),
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Enter value ($min - $max)',
                          suffixText: unit,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, controller.text),
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                  );
                  if (typed != null) {
                    final parsed = num.tryParse(typed);
                    if (parsed != null && parsed >= min && parsed <= max) {
                      onChanged(isDecimal ? parsed.toDouble() : parsed.toInt());
                    }
                  }
                },
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isDecimal ? value.toStringAsFixed(1) : value.toString()}${unit ?? ''}',
                    textAlign: TextAlign.center,
                    style: AppTheme.mono(
                      context: context,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                color: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final next = value + step;
                  if (next <= max) {
                    onChanged(
                      isDecimal
                          ? double.parse(next.toStringAsFixed(3))
                          : next.toInt(),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModalSourceChips(
    String currentSource,
    ValueChanged<String> onChanged,
  ) {
    final sources = ['Close', 'Open', 'High', 'Low', 'HL2', 'HLC3', 'OHLC4'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Source:',
            style: AppTheme.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _t2,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sources.map((src) {
                final isSel = src.toLowerCase() == currentSource.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildOledChip(
                    label: src,
                    isSelected: isSel,
                    onTap: () => onChanged(src),
                    height: 30,
                    fontSize: 11,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _applySavedIndicatorConfig(IndicatorAlertConfig cfg) {
    _selectedIndicator = cfg.indicatorType;
    switch (cfg.indicatorType) {
      case AlertIndicatorType.rsi:
        _rsiCondition = cfg.condition;
        _rsiPeriod = (cfg.params['period'] as num?)?.toInt() ?? _rsiPeriod;
        _rsiSource = (cfg.params['source'] as String?) ?? _rsiSource;
        _rsiSmoothingType =
            (cfg.params['smoothingType'] as String?) ?? _rsiSmoothingType;
        _rsiLevel = (cfg.params['level'] as num?)?.toDouble() ?? _rsiLevel;
        _rsiOverbought =
            (cfg.params['overbought'] as num?)?.toDouble() ?? _rsiOverbought;
        _rsiOversold =
            (cfg.params['oversold'] as num?)?.toDouble() ?? _rsiOversold;
        _rsiApplySignalMa =
            (cfg.params['applySignalMa'] as bool?) ?? _rsiApplySignalMa;
        _rsiSignalMaType =
            (cfg.params['signalMaType'] as String?) ?? _rsiSignalMaType;
        _rsiSignalMaPeriod =
            (cfg.params['signalMaPeriod'] as num?)?.toInt() ??
            _rsiSignalMaPeriod;
        break;
      case AlertIndicatorType.macd:
        _macdCondition = cfg.condition;
        _macdFast = (cfg.params['fast'] as num?)?.toInt() ?? _macdFast;
        _macdSlow = (cfg.params['slow'] as num?)?.toInt() ?? _macdSlow;
        _macdSignal = (cfg.params['signal'] as num?)?.toInt() ?? _macdSignal;
        _macdSource = (cfg.params['source'] as String?) ?? _macdSource;
        _macdFastMaType =
            (cfg.params['fastMaType'] as String?) ?? _macdFastMaType;
        _macdSlowMaType =
            (cfg.params['slowMaType'] as String?) ?? _macdSlowMaType;
        _macdSignalMaType =
            (cfg.params['signalMaType'] as String?) ?? _macdSignalMaType;
        break;
      case AlertIndicatorType.maCross:
        _maCondition = cfg.condition;
        _maFastPeriod =
            (cfg.params['fastPeriod'] as num?)?.toInt() ?? _maFastPeriod;
        _maSlowPeriod =
            (cfg.params['slowPeriod'] as num?)?.toInt() ?? _maSlowPeriod;
        _maType = (cfg.params['maType'] as String?) ?? _maType;
        _maFastMaType = (cfg.params['fastMaType'] as String?) ?? _maFastMaType;
        _maSlowMaType = (cfg.params['slowMaType'] as String?) ?? _maSlowMaType;
        _maSource = (cfg.params['source'] as String?) ?? _maSource;
        break;
      case AlertIndicatorType.bollingerBands:
        _bbCondition = cfg.condition;
        _bbPeriod = (cfg.params['period'] as num?)?.toInt() ?? _bbPeriod;
        _bbStdDev = (cfg.params['stdDev'] as num?)?.toDouble() ?? _bbStdDev;
        _bbSource = (cfg.params['source'] as String?) ?? _bbSource;
        _bbMaType = (cfg.params['maType'] as String?) ?? _bbMaType;
        _bbSqueezeThreshold =
            (cfg.params['squeezeThreshold'] as num?)?.toDouble() ??
            _bbSqueezeThreshold;
        break;
      case AlertIndicatorType.stochastic:
        _stochCondition = cfg.condition;
        _stochK = (cfg.params['kPeriod'] as num?)?.toInt() ?? _stochK;
        _stochKSlowing =
            (cfg.params['kSlowing'] as num?)?.toInt() ?? _stochKSlowing;
        _stochD = (cfg.params['dPeriod'] as num?)?.toInt() ?? _stochD;
        _stochDMaType = (cfg.params['dMaType'] as String?) ?? _stochDMaType;
        _stochOversold =
            (cfg.params['oversoldLevel'] as num?)?.toDouble() ??
            (cfg.params['oversold'] as num?)?.toDouble() ??
            _stochOversold;
        _stochOverbought =
            (cfg.params['overboughtLevel'] as num?)?.toDouble() ??
            (cfg.params['overbought'] as num?)?.toDouble() ??
            _stochOverbought;
        break;
      case AlertIndicatorType.supertrend:
        _stCondition = cfg.condition;
        _stPeriod = (cfg.params['period'] as num?)?.toInt() ?? _stPeriod;
        _stMultiplier =
            (cfg.params['multiplier'] as num?)?.toDouble() ?? _stMultiplier;
        _stSource = (cfg.params['source'] as String?) ?? _stSource;
        _stAtrSmoothing =
            (cfg.params['atrSmoothing'] as String?) ?? _stAtrSmoothing;
        _stDistanceThreshold =
            (cfg.params['distanceThreshold'] as num?)?.toDouble() ??
            _stDistanceThreshold;
        break;
    }
  }

  List<Widget> _buildParamBadges(IndicatorAlertConfig config) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final badges = <Widget>[];

    void addBadge(String label, String value, {Color? color}) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: (color ?? theme.colorScheme.primary).withValues(
                alpha: 0.3,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$label: ',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color ?? (isDark ? Colors.white : Colors.black),
                ),
              ),
            ],
          ),
        ),
      );
    }

    switch (config.indicatorType) {
      case AlertIndicatorType.rsi:
        addBadge('Length', '${config.params['period'] ?? 14}');
        addBadge('Source', '${config.params['source'] ?? 'Close'}');
        if (config.params['smoothingType'] != null &&
            config.params['smoothingType'] != 'RMA') {
          addBadge(
            'Smooth',
            '${config.params['smoothingType']}',
            color: Colors.cyan,
          );
        }
        addBadge('OS', '${config.params['oversold'] ?? 30}');
        addBadge('OB', '${config.params['overbought'] ?? 70}');
        if (config.params['level'] != null &&
            (config.condition.contains('Level') ||
                config.condition == 'crossesAbove' ||
                config.condition == 'crossesBelow')) {
          addBadge(
            'Lvl',
            '${config.params['level']}',
            color: Colors.deepOrangeAccent,
          );
        }
        if (config.params['applySignalMa'] == true) {
          addBadge(
            'Signal MA',
            '${config.params['signalMaType'] ?? "EMA"}(${config.params['signalMaPeriod'] ?? 9})',
            color: Colors.amber,
          );
        }
        addBadge('Signal', config.condition, color: Colors.green);
        break;
      case AlertIndicatorType.macd:
        addBadge(
          'Fast',
          '${config.params['fastMaType'] ?? "EMA"}(${config.params['fast'] ?? 12})',
        );
        addBadge(
          'Slow',
          '${config.params['slowMaType'] ?? "EMA"}(${config.params['slow'] ?? 26})',
        );
        addBadge(
          'Signal',
          '${config.params['signalMaType'] ?? "EMA"}(${config.params['signal'] ?? 9})',
        );
        addBadge('Source', '${config.params['source'] ?? 'Close'}');
        addBadge('Signal', config.condition, color: Colors.green);
        break;
      case AlertIndicatorType.maCross:
        final fastType =
            config.params['fastMaType'] ?? config.params['maType'] ?? 'EMA';
        final slowType =
            config.params['slowMaType'] ?? config.params['maType'] ?? 'EMA';
        addBadge('Fast', '$fastType(${config.params['fastPeriod'] ?? 50})');
        addBadge('Slow', '$slowType(${config.params['slowPeriod'] ?? 200})');
        addBadge('Source', '${config.params['source'] ?? 'Close'}');
        addBadge('Signal', config.condition, color: Colors.green);
        break;
      case AlertIndicatorType.bollingerBands:
        addBadge('Period', '${config.params['period'] ?? 20}');
        addBadge('StdDev', '${config.params['stdDev'] ?? 2.0}');
        if (config.params['maType'] != null &&
            config.params['maType'] != 'SMA') {
          addBadge('Basis', '${config.params['maType']}', color: Colors.cyan);
        }
        addBadge('Source', '${config.params['source'] ?? 'Close'}');
        if (config.condition == 'squeeze' ||
            config.condition == 'squeezeBreakout') {
          final sqz =
              ((config.params['squeezeThreshold'] ?? 0.015) as num).toDouble() *
              100;
          addBadge(
            'Squeeze',
            '${sqz.toStringAsFixed(1)}%',
            color: Colors.amber,
          );
        }
        addBadge('Signal', config.condition, color: Colors.green);
        break;
      case AlertIndicatorType.stochastic:
        final k = config.params['kPeriod'] ?? 14;
        final kSlowing = config.params['kSlowing'] ?? 3;
        final d = config.params['dPeriod'] ?? 3;
        final dMaType = config.params['dMaType'] ?? 'SMA';
        addBadge('%K', '$k');
        if (kSlowing != 1) addBadge('Smooth', '$kSlowing');
        addBadge('%D', '$d($dMaType)');
        addBadge(
          'OS',
          '${config.params['oversoldLevel'] ?? config.params['oversold'] ?? 20}',
        );
        addBadge(
          'OB',
          '${config.params['overboughtLevel'] ?? config.params['overbought'] ?? 80}',
        );
        addBadge('Signal', config.condition, color: Colors.green);
        break;
      case AlertIndicatorType.supertrend:
        addBadge('ATR', '${config.params['period'] ?? 10}');
        addBadge('Mult', '${config.params['multiplier'] ?? 3.0}');
        if (config.params['atrSmoothing'] != null &&
            config.params['atrSmoothing'] != 'RMA') {
          addBadge(
            'Smooth',
            '${config.params['atrSmoothing']}',
            color: Colors.cyan,
          );
        }
        if (config.params['source'] != null &&
            config.params['source'] != 'HL2') {
          addBadge('Source', '${config.params['source']}');
        }
        if (config.condition.contains('Distance')) {
          addBadge(
            'Dist',
            '${config.params['distanceThreshold'] ?? 1.0}%',
            color: Colors.amber,
          );
        }
        addBadge('Signal', config.condition, color: Colors.green);
        break;
    }

    return badges;
  }

  // _nodeTypeChip definition above at line ~2969 is the canonical one.

  void _addStage() {
    setState(() {
      final newStageIdx = _chainStages.length + 1;
      _chainStages.add(
        ChainStage(
          id: 'stage_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Stage $newStageIdx Confirmation',
          logicOperator: 'AND',
          nodes: [
            ChainNode(
              id: 'node_${DateTime.now().microsecondsSinceEpoch}',
              nodeType: AlertType.priceLevel,
              targetPrice: _selectedPrice,
              condition: AlertCondition.crossesAbove,
            ),
          ],
        ),
      );
    });
  }

  void _removeStage(int stageIdx) {
    if (_chainStages.length > 1) {
      setState(() => _chainStages.removeAt(stageIdx));
    }
  }

  void _addNodeToStage(int stageIdx) {
    setState(() {
      _chainStages[stageIdx].nodes.add(
        ChainNode(
          id: 'node_${DateTime.now().microsecondsSinceEpoch}',
          nodeType: AlertType.technicalIndicator,
          indicatorConfig: IndicatorAlertConfig(
            indicatorType: AlertIndicatorType.rsi,
            condition: 'crossesBelow',
            params: {
              'period': 14,
              'source': 'Close',
              'level': 30.0,
              'overbought': 70.0,
              'oversold': 30.0,
              'applySignalMa': false,
              'signalMaType': 'EMA',
              'signalMaPeriod': 9,
            },
          ),
          timeframe: '15m',
          operatorToPrevious: 'AND',
        ),
      );
    });
  }

  void _removeNodeFromStage(int stageIdx, int nodeIdx) {
    if (_chainStages[stageIdx].nodes.length > 1) {
      setState(() => _chainStages[stageIdx].nodes.removeAt(nodeIdx));
    }
  }

  Widget _buildStrategyTemplateChip(String title, String templateKey) {
    return GestureDetector(
      onTap: () => _applyStrategyTemplate(templateKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 13, color: Color(0xFFBF5AF2)),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyStrategyTemplate(String template) {
    setState(() {
      if (template == 'breakout_retest') {
        final breakoutLevel = _selectedPrice + (_pipValue * 20);
        final retestLevel = _selectedPrice + (_pipValue * 15);
        _chainStages.clear();
        _chainStages.addAll([
          ChainStage(
            id: 'stage_1',
            name: 'Resistance Breakout (Level 1)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_1',
                nodeType: AlertType.priceLevel,
                targetPrice: breakoutLevel,
                condition: AlertCondition.crossesAbove,
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_2',
            name: 'Pullback Retest (Level 2)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_2',
                nodeType: AlertType.priceLevel,
                targetPrice: retestLevel,
                condition: AlertCondition.crossesBelow,
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_3',
            name: 'Rejection / Reversal Confirmation (Level 3)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_3',
                nodeType: AlertType.candlestickPattern,
                candlestickPattern: CandlestickPattern.bullishEngulfing,
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
        ]);
      } else if (template == 'rsi_reversal') {
        _chainStages.clear();
        _chainStages.addAll([
          ChainStage(
            id: 'stage_1',
            name: 'RSI Oversold Touch (Level 1)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_1',
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.rsi,
                  condition: 'crossesBelow',
                  params: {
                    'period': 14,
                    'level': 30.0,
                    'source': 'Close',
                    'smoothingType': 'RMA',
                    'overbought': 70.0,
                    'oversold': 30.0,
                  },
                ),
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_2',
            name: 'Candle Reversal + Price Lift (Level 2)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_2',
                nodeType: AlertType.candlestickPattern,
                candlestickPattern: CandlestickPattern.hammer,
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
              ChainNode(
                id: 'n_3',
                nodeType: AlertType.priceLevel,
                targetPrice: _selectedPrice + (_pipValue * 5),
                condition: AlertCondition.crossesAbove,
                operatorToPrevious: 'AND',
              ),
            ],
          ),
        ]);
      } else if (template == 'trend_pullback') {
        _chainStages.clear();
        _chainStages.addAll([
          ChainStage(
            id: 'stage_1',
            name: 'Golden Cross Trend Filter (Level 1)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_1',
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.maCross,
                  condition: 'goldenCross',
                  params: {
                    'fastPeriod': 50,
                    'slowPeriod': 200,
                    'maType': 'EMA',
                    'fastMaType': 'EMA',
                    'slowMaType': 'EMA',
                    'source': 'Close',
                  },
                ),
                timeframe: '1h',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_2',
            name: 'Trend Pullback (Level 2)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_2',
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.rsi,
                  condition: 'crossesBelow',
                  params: {
                    'period': 14,
                    'level': 45.0,
                    'source': 'Close',
                    'smoothingType': 'RMA',
                    'overbought': 70.0,
                    'oversold': 30.0,
                  },
                ),
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_3',
            name: 'Bullish Reversal Candle (Level 3)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_3',
                nodeType: AlertType.candlestickPattern,
                candlestickPattern: CandlestickPattern.bullishEngulfing,
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
        ]);
      } else if (template == 'bb_squeeze_breakout') {
        _chainStages.clear();
        _chainStages.addAll([
          ChainStage(
            id: 'stage_1',
            name: 'BB Volatility Squeeze (Level 1)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_1',
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.bollingerBands,
                  condition: 'squeeze',
                  params: {
                    'period': 20,
                    'stdDev': 2.0,
                    'source': 'Close',
                    'maType': 'SMA',
                    'squeezeThreshold': 0.015,
                  },
                ),
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
            ],
          ),
          ChainStage(
            id: 'stage_2',
            name: 'Supertrend Flip & Upward Breakout (Level 2)',
            logicOperator: 'AND',
            nodes: [
              ChainNode(
                id: 'n_2',
                nodeType: AlertType.technicalIndicator,
                indicatorConfig: IndicatorAlertConfig(
                  indicatorType: AlertIndicatorType.supertrend,
                  condition: 'bullishFlip',
                  params: {
                    'period': 10,
                    'multiplier': 3.0,
                    'source': 'HL2',
                    'atrSmoothing': 'RMA',
                    'distanceThreshold': 1.0,
                  },
                ),
                timeframe: '15m',
                operatorToPrevious: 'AND',
              ),
              ChainNode(
                id: 'n_3',
                nodeType: AlertType.priceLevel,
                targetPrice: _selectedPrice + (_pipValue * 10),
                condition: AlertCondition.crossesAbove,
                operatorToPrevious: 'AND',
              ),
            ],
          ),
        ]);
      }
    });
  }
}

// ─────────────────────────────────────────────────────────────
// Full-catalog multi-symbol picker  (searchable – no hardcoded chips)
// ─────────────────────────────────────────────────────────────
class _MultiSymbolPickerSheet extends StatefulWidget {
  final List<BiquoteInstrument> allInstruments;
  final Set<String> selected;
  final String currentSymbol;
  final bool singleSelect;
  final ValueChanged<Set<String>> onConfirm;

  const _MultiSymbolPickerSheet({
    required this.allInstruments,
    required this.selected,
    required this.currentSymbol,
    this.singleSelect = false,
    required this.onConfirm,
  });

  @override
  State<_MultiSymbolPickerSheet> createState() =>
      _MultiSymbolPickerSheetState();
}

class _MultiSymbolPickerSheetState extends State<_MultiSymbolPickerSheet> {
  late Set<String> _sel;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _cat = 'All';

  static const _cats = [
    'All',
    'Forex',
    'Metals',
    'Crypto',
    'Indices',
    'Commodities',
    'Stocks',
  ];

  static const _catColors = {
    'Forex': Color(0xFF0A84FF),
    'Metals': Color(0xFFFFB340),
    'Crypto': Color(0xFFBF5AF2),
    'Indices': Color(0xFF30D158),
    'Commodities': Color(0xFFFF9F0A),
    'Stocks': Color(0xFFFF453A),
  };

  @override
  void initState() {
    super.initState();
    _sel = Set.from(widget.selected);
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _catOf(BiquoteInstrument i) {
    final t = i.type.toLowerCase();
    if (t == 'forex') return 'Forex';
    if (t.contains('metal') ||
        i.symbol.startsWith('XAU') ||
        i.symbol.startsWith('XAG')) {
      return 'Metals';
    }
    if (t == 'crypto') return 'Crypto';
    if (t.contains('index') || t.contains('indic')) return 'Indices';
    if (t.contains('commodity') || t.contains('commodit')) return 'Commodities';
    if (t == 'stock') return 'Stocks';
    return 'Forex';
  }

  List<BiquoteInstrument> get _filtered => widget.allInstruments.where((i) {
    final catOk = _cat == 'All' || _catOf(i) == _cat;
    final qOk =
        _query.isEmpty ||
        i.symbol.toLowerCase().contains(_query) ||
        i.description.toLowerCase().contains(_query);
    return catOk && qOk;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final allSel =
        items.isNotEmpty && items.every((i) => _sel.contains(i.symbol));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x57EBEBF5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.singleSelect
                              ? 'Select Instrument'
                              : 'Deploy to Multiple Instruments',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${_sel.length} of ${widget.allInstruments.length} selected',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0x9DEBEBF5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.singleSelect)
                    TextButton(
                      onPressed: () => setState(() {
                        if (allSel) {
                          for (final i in items) {
                            if (i.symbol != widget.currentSymbol) {
                              _sel.remove(i.symbol);
                            }
                          }
                        } else {
                          for (final i in items) {
                            _sel.add(i.symbol);
                          }
                        }
                      }),
                      child: Text(
                        allSel ? 'Deselect All' : 'Select All',
                        style: const TextStyle(
                          color: Color(0xFF0A84FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _search,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search symbol or description…',
                    hintStyle: TextStyle(
                      color: Color(0x57EBEBF5),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Color(0x57EBEBF5),
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _cats.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (ctx, idx) {
                  final c = _cats[idx];
                  final active = _cat == c;
                  return GestureDetector(
                    onTap: () => setState(() => _cat = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? (_catColors[c] ?? const Color(0xFF0A84FF))
                            : const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            const Divider(color: Color(0x17FFFFFF), height: 1),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No instruments found',
                        style: TextStyle(color: Color(0x9DEBEBF5)),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(color: Color(0x0FFFFFFF), height: 1),
                      itemBuilder: (ctx, idx) {
                        final inst = items[idx];
                        final isSel = _sel.contains(inst.symbol);
                        final isCurrent = inst.symbol == widget.currentSymbol;
                        final cat = _catOf(inst);
                        final catColor =
                            _catColors[cat] ?? const Color(0xFF0A84FF);
                        return InkWell(
                          onTap: isCurrent && !widget.singleSelect
                              ? null
                              : () => setState(() {
                                  if (widget.singleSelect) {
                                    _sel
                                      ..clear()
                                      ..add(inst.symbol);
                                  } else if (isSel) {
                                    if (_sel.length > 1) {
                                      _sel.remove(inst.symbol);
                                    }
                                  } else {
                                    _sel.add(inst.symbol);
                                  }
                                }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? const Color(0xFF0A84FF)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSel
                                          ? const Color(0xFF0A84FF)
                                          : const Color(0x57EBEBF5),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: isSel
                                      ? const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            inst.symbol,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? const Color(0xFF0A84FF)
                                                  : Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          if (isCurrent) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0x220A84FF),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'current',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: Color(0xFF0A84FF),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (inst.description.isNotEmpty)
                                        Text(
                                          inst.description,
                                          style: const TextStyle(
                                            color: Color(0x9DEBEBF5),
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    cat.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: catColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: GestureDetector(
                onTap: () {
                  widget.onConfirm(_sel);
                  Navigator.pop(context);
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0A84FF).withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.singleSelect
                        ? 'Use ${_sel.isEmpty ? "instrument" : _sel.first}'
                        : 'Done — ${_sel.length} ${_sel.length == 1 ? "instrument" : "instruments"} selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
