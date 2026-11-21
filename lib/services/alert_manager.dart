import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'app_telemetry.dart';

import '../models/market_models.dart';
import 'alarm_service.dart';
import 'candlestick_detector.dart';
import 'indicator_calculator.dart';
import 'settings_provider.dart';
import 'storage_service.dart';

class AlertManager extends ChangeNotifier {
  static const String _keyAlerts = 'saved_alerts';
  static const String _keyHistory = 'saved_history';

  final AlarmService alarmService;
  final List<PriceAlert> _alerts = [];
  final List<PriceAlert> _history = [];
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;
  Timer? _scheduleTimer;
  Duration? _lastPollingDuration;
  bool? _lastPerpetualServiceActive;
  Duration? _lastAlertTtl;

  void Function(PriceAlert alert, double triggerPrice)? onAlertTriggered;

  List<PriceAlert> get alerts => List.unmodifiable(_alerts);
  List<PriceAlert> get activeAlerts =>
      _alerts.where((a) => a.isActive).toList();
  List<PriceAlert> get history => List.unmodifiable(_history);

  Map<String, dynamic> exportBackupData() => {
    'alerts': _alerts.map((alert) => alert.toJson()).toList(),
    'history': _history.map((alert) => alert.toJson()).toList(),
  };

  static void validateBackupData(Map<String, dynamic> data) {
    for (final key in const ['alerts', 'history']) {
      final items = data[key];
      if (items != null && items is! List) {
        throw FormatException('$key must be a list');
      }
      for (final item in (items as List? ?? const [])) {
        PriceAlert.fromJson(Map<String, dynamic>.from(item as Map));
      }
    }
  }

  Future<void> importBackupData(
    Map<String, dynamic> data, {
    bool strictPersistence = false,
  }) async {
    final restoredAlerts = (data['alerts'] as List? ?? const [])
        .map(
          (item) => PriceAlert.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final restoredHistory = (data['history'] as List? ?? const [])
        .map(
          (item) => PriceAlert.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();

    _alerts
      ..clear()
      ..addAll(restoredAlerts);
    _history
      ..clear()
      ..addAll(restoredHistory);
    notifyListeners();
    if (strictPersistence) {
      final alertsData = jsonEncode(_alerts.map((a) => a.toJson()).toList());
      final historyData = jsonEncode(_history.map((a) => a.toJson()).toList());
      await StorageService.setStringRequired(_keyAlerts, alertsData);
      await StorageService.setStringRequired(_keyHistory, historyData);
    } else {
      await _saveToStorage();
    }
    _syncWithNativeService();
  }

  AlertManager({AlarmService? alarmService})
    : alarmService = alarmService ?? AlarmService() {
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _loadFromStorage();
    _checkAlertTtl();
    // Honor the user's background monitoring preference at startup.
    final monitoringEnabled = SettingsProvider().perpetualServiceActive;
    if (monitoringEnabled) {
      await alarmService.startForegroundService();
    } else {
      await alarmService.stopForegroundService();
    }
    _lastPerpetualServiceActive = monitoringEnabled;
    _lastAlertTtl = SettingsProvider().ttlDuration;
    // Sync current active alerts with Android native service
    _syncWithNativeService();
    // Start recurring timer for scheduled/calendar alerts and session checks
    _setupRecurringTimer();
    SettingsProvider().addListener(_onSettingsChanged);
  }

  bool _lowBatteryWarned = false;

  void _setupRecurringTimer() {
    _scheduleTimer?.cancel();
    final duration = SettingsProvider().pollingDuration;
    _lastPollingDuration = duration;
    _scheduleTimer = Timer.periodic(duration, (_) {
      evaluateScheduledAlerts();
      // The Android monitor owns session alerts while perpetual monitoring is
      // enabled, so the in-app timer only provides the foreground fallback.
      if (!SettingsProvider().perpetualServiceActive) evaluateSessionAlerts();
      _checkAlertTtl();
      _checkBatteryProtection();
    });
  }

  Future<void> _checkBatteryProtection() async {
    if (!SettingsProvider().lowBatteryGuard) {
      _lowBatteryWarned = false;
      await alarmService.setLowBatteryWarning(null);
      return;
    }
    try {
      final telemetry = await alarmService.getSystemTelemetry();
      final battery = telemetry['batteryLevel'] as int?;
      if (battery != null &&
          battery > 0 &&
          battery <= 15 &&
          !_lowBatteryWarned) {
        _lowBatteryWarned = true;
        await alarmService.setLowBatteryWarning(battery);
        final alert = PriceAlert(
          id: 'battery_${DateTime.now().millisecondsSinceEpoch}',
          symbol: 'SYSTEM',
          alertType: AlertType.timeSchedule,
          note:
              'Battery at $battery%. TenX is in Low-Battery Protection mode to conserve power.',
          createdAt: DateTime.now(),
          initialPrice: 0.0,
          ringtoneTitle: SettingsProvider().soundTitle,
          ringtoneUri: SettingsProvider().soundUri,
          triggeredAt: DateTime.now(),
          isActive: false,
        );
        _history.insert(0, alert);
        notifyListeners();
        _saveToStorage();
      } else if (battery != null && battery > 20) {
        _lowBatteryWarned = false;
        await alarmService.setLowBatteryWarning(null);
      }
    } catch (_) {}
  }

  void _onSettingsChanged() {
    final previousPollingDuration = _lastPollingDuration;
    final previousMonitoringEnabled = _lastPerpetualServiceActive;
    _setupRecurringTimer();
    final settings = SettingsProvider();
    _lastPerpetualServiceActive = settings.perpetualServiceActive;
    final ttlChanged = _lastAlertTtl != settings.ttlDuration;
    _lastAlertTtl = settings.ttlDuration;
    if (ttlChanged) _syncWithNativeService();
    if (!settings.lowBatteryGuard) {
      _lowBatteryWarned = false;
      alarmService.setLowBatteryWarning(null);
    }
    if (previousMonitoringEnabled != settings.perpetualServiceActive) {
      if (settings.perpetualServiceActive) {
        alarmService.startForegroundService();
      } else {
        alarmService.stopForegroundService();
      }
      return;
    }
    if (!settings.perpetualServiceActive) {
      return;
    }
    if (previousPollingDuration != null &&
        previousPollingDuration != settings.pollingDuration) {
      // Restart the native scheduler so its fixed-delay interval takes effect.
      alarmService.stopForegroundService().then(
        (_) => alarmService.startForegroundService(),
      );
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final alertsJson = await StorageService.getString(_keyAlerts);
      final historyJson = await StorageService.getString(_keyHistory);

      _alerts.clear();
      _history.clear();

      if (alertsJson != null && alertsJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(alertsJson);
        for (final item in list) {
          final alert = PriceAlert.fromJson(item as Map<String, dynamic>);
          // Remove the three legacy demo alerts that older builds seeded into
          // every new account. These IDs are reserved for that bundled sample.
          if (!_legacyDemoAlertIds.contains(alert.id)) _alerts.add(alert);
        }
        if (_alerts.length != list.length) {
          await StorageService.setString(
            _keyAlerts,
            jsonEncode(_alerts.map((alert) => alert.toJson()).toList()),
          );
        }
      } else {
        // An account with no saved alerts starts empty.
        await StorageService.setString(_keyAlerts, '[]');
      }

      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(historyJson);
        for (final item in list) {
          _history.add(PriceAlert.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // A malformed or missing alert list must never generate sample alerts.
      _alerts.removeWhere((alert) => _legacyDemoAlertIds.contains(alert.id));
      try {
        await StorageService.setString(
          _keyAlerts,
          jsonEncode(_alerts.map((alert) => alert.toJson()).toList()),
        );
      } catch (_) {}
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> reloadFromStorage() async {
    await _loadFromStorage();
    _syncWithNativeService();
  }

  Future<void> _saveToStorage() async {
    try {
      final alertsData = jsonEncode(_alerts.map((a) => a.toJson()).toList());
      final historyData = jsonEncode(_history.map((a) => a.toJson()).toList());

      await StorageService.setString(_keyAlerts, alertsData);
      await StorageService.setString(_keyHistory, historyData);
    } catch (_) {}

    _syncWithNativeService();
  }

  void _syncWithNativeService() {
    try {
      final activeList = activeAlerts.map((a) => a.toJson()).toList();
      final activeJson = jsonEncode(activeList);
      alarmService.syncActiveAlerts(activeJson);
    } catch (_) {}
  }

  /// Stop this account's native monitoring before the authenticated session ends.
  Future<void> stopForAccountSignOut() async {
    _scheduleTimer?.cancel();
    _alerts.clear();
    _syncWithNativeService();
    await alarmService.stopAlarm();
    await alarmService.stopForegroundService();
  }

  static const Set<String> _legacyDemoAlertIds = {
    'alert_1',
    'alert_2',
    'alert_3',
  };

  PriceAlert addAlert({
    required String symbol,
    AlertType alertType = AlertType.priceLevel,
    double targetPrice = 0.0,
    AlertCondition condition = AlertCondition.crossesAbove,
    CandlestickPattern? candlestickPattern,
    IndicatorAlertConfig? indicatorConfig,
    MultiStepConfig? multiStepConfig,
    String timeframe = '15m',
    String note = '',
    required double currentPrice,
    String ringtoneTitle = 'Default Alarm',
    String? ringtoneUri,
    String? drawingId,
    bool triggerOnCandleClose = true,
    int cooldownMinutes = 0,
    List<String>? targetSymbols,
    DateTime? scheduledTime,
  }) {
    final settings = SettingsProvider();
    final effectiveTitle =
        (ringtoneTitle == 'Default Alarm' &&
            (ringtoneUri == null || ringtoneUri.isEmpty))
        ? settings.soundTitle
        : ringtoneTitle;
    final effectiveUri = (ringtoneUri == null || ringtoneUri.isEmpty)
        ? settings.soundUri
        : ringtoneUri;

    final alert = PriceAlert(
      id: 'alert_${DateTime.now().millisecondsSinceEpoch}',
      symbol: symbol,
      alertType: alertType,
      targetPrice: targetPrice,
      condition: condition,
      candlestickPattern: candlestickPattern,
      indicatorConfig: indicatorConfig,
      multiStepConfig: multiStepConfig,
      timeframe: timeframe,
      note: note,
      createdAt: DateTime.now(),
      initialPrice: currentPrice,
      ringtoneTitle: effectiveTitle,
      ringtoneUri: effectiveUri,
      drawingId: drawingId,
      triggerOnCandleClose: triggerOnCandleClose,
      cooldownMinutes: cooldownMinutes,
      targetSymbols: targetSymbols,
      scheduledTime: scheduledTime,
    );
    _alerts.insert(0, alert);
    unawaited(AppTelemetry.logAlertCreated(
      alertType: alert.alertType.name,
      activeCount: _alerts.where((item) => item.isActive).length,
    ));
    notifyListeners();
    _saveToStorage();
    return alert;
  }

  /// Deploys an alert or logic chain strategy across multiple symbols simultaneously
  List<PriceAlert> createMultiSymbolAlerts({
    required List<String> symbols,
    AlertType alertType = AlertType.priceLevel,
    double targetPrice = 0.0,
    AlertCondition condition = AlertCondition.crossesAbove,
    CandlestickPattern? candlestickPattern,
    IndicatorAlertConfig? indicatorConfig,
    MultiStepConfig? multiStepConfig,
    String timeframe = '15m',
    String note = '',
    required double currentPrice,
    Map<String, double>? symbolPrices,
    String ringtoneTitle = 'Default Alarm',
    String? ringtoneUri,
    String? drawingId,
    bool triggerOnCandleClose = true,
    int cooldownMinutes = 0,
  }) {
    final settings = SettingsProvider();
    final effectiveTitle =
        (ringtoneTitle == 'Default Alarm' &&
            (ringtoneUri == null || ringtoneUri.isEmpty))
        ? settings.soundTitle
        : ringtoneTitle;
    final effectiveUri = (ringtoneUri == null || ringtoneUri.isEmpty)
        ? settings.soundUri
        : ringtoneUri;

    final created = <PriceAlert>[];
    for (int i = 0; i < symbols.length; i++) {
      final sym = symbols[i];
      final symPrice = symbolPrices?[sym] ?? (i == 0 ? currentPrice : 0.0);
      final resolvedInitialPrice = symPrice > 0 ? symPrice : currentPrice;

      // Clone multiStepConfig for each symbol so they maintain independent stage state
      MultiStepConfig? symMultiStepConfig;
      if (multiStepConfig != null) {
        final clonedStages = multiStepConfig.stages
            .map(
              (s) => ChainStage(
                id: '${s.id}_$sym',
                name: s.name,
                logicOperator: s.logicOperator,
                timeoutMinutes: s.timeoutMinutes,
                nodes: s.nodes
                    .map(
                      (n) => ChainNode(
                        id: '${n.id}_$sym',
                        nodeType: n.nodeType,
                        targetPrice: n.targetPrice,
                        condition: n.condition,
                        candlestickPattern: n.candlestickPattern,
                        indicatorConfig: n.indicatorConfig != null
                            ? IndicatorAlertConfig(
                                indicatorType: n.indicatorConfig!.indicatorType,
                                condition: n.indicatorConfig!.condition,
                                params: Map.from(n.indicatorConfig!.params),
                              )
                            : null,
                        timeframe: n.timeframe,
                        isNegated: n.isNegated,
                        operatorToPrevious: n.operatorToPrevious,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList();
        symMultiStepConfig = MultiStepConfig(
          stages: clonedStages,
          timeoutMinutes: multiStepConfig.timeoutMinutes,
        );
      }

      final alert = PriceAlert(
        id: 'alert_${DateTime.now().millisecondsSinceEpoch}_$i',
        symbol: sym,
        alertType: alertType,
        targetPrice: targetPrice,
        condition: condition,
        candlestickPattern: candlestickPattern,
        indicatorConfig: indicatorConfig,
        multiStepConfig: symMultiStepConfig,
        timeframe: timeframe,
        note: note,
        createdAt: DateTime.now(),
        initialPrice: resolvedInitialPrice,
        ringtoneTitle: effectiveTitle,
        ringtoneUri: effectiveUri,
        drawingId: drawingId,
        triggerOnCandleClose: triggerOnCandleClose,
        cooldownMinutes: cooldownMinutes,
        targetSymbols: symbols,
      );
      _alerts.insert(0, alert);
      created.add(alert);
    }
    notifyListeners();
    _saveToStorage();
    return created;
  }

  /// Finds an active alert linked to a chart drawing ID.
  PriceAlert? getAlertForDrawing(String drawingId) {
    try {
      return _alerts.firstWhere((a) => a.drawingId == drawingId && a.isActive);
    } catch (_) {
      return null;
    }
  }

  /// Dynamically updates the alert target price when a user moves a drawing line on the chart.
  bool updateAlertForDrawing(
    String drawingId,
    double newTargetPrice, {
    double? currentPrice,
  }) {
    final idx = _alerts.indexWhere(
      (a) => a.drawingId == drawingId && a.isActive,
    );
    if (idx != -1) {
      final alert = _alerts[idx];
      alert.targetPrice = newTargetPrice;
      if (currentPrice != null && currentPrice > 0) {
        alert.condition = newTargetPrice >= currentPrice
            ? AlertCondition.crossesAbove
            : AlertCondition.crossesBelow;
      }
      notifyListeners();
      _saveToStorage();
      return true;
    }
    return false;
  }

  /// Removes alerts linked to a deleted drawing.
  void removeAlertForDrawing(String drawingId) {
    _alerts.removeWhere((a) => a.drawingId == drawingId);
    _history.removeWhere((a) => a.drawingId == drawingId);
    notifyListeners();
    _saveToStorage();
  }

  void toggleAlert(String id) {
    final idx = _alerts.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _alerts[idx].isActive = !_alerts[idx].isActive;
      unawaited(AppTelemetry.logAlertChanged(
        enabled: _alerts[idx].isActive,
        activeCount: _alerts.where((item) => item.isActive).length,
      ));
      notifyListeners();
      _saveToStorage();
    }
  }

  void deleteAlert(String id) {
    final oldLength = _alerts.length;
    _alerts.removeWhere((a) => a.id == id);
    if (_alerts.length != oldLength) {
      unawaited(AppTelemetry.logAlertDeleted(
        activeCount: _alerts.where((item) => item.isActive).length,
      ));
    }
    _history.removeWhere((a) => a.id == id);
    notifyListeners();
    _saveToStorage();
  }

  /// Clears all triggered alert history records without touching active alerts.
  Future<void> clearHistory() async {
    await StorageService.setStringRequired(_keyHistory, '[]');
    _history.clear();
    notifyListeners();
    _syncWithNativeService();
  }

  /// Reactivates and resets a triggered or inactive alert.
  void rearmAlert(String id, {double? currentPrice}) {
    PriceAlert? alert;
    final alertIdx = _alerts.indexWhere((a) => a.id == id);
    if (alertIdx != -1) {
      alert = _alerts[alertIdx];
    } else {
      final histIdx = _history.indexWhere((a) => a.id == id);
      if (histIdx != -1) {
        alert = _history[histIdx];
        _alerts.insert(0, alert);
      }
    }

    if (alert != null) {
      alert.isActive = true;
      alert.triggeredAt = null;
      alert.snoozedUntil = null;
      if (currentPrice != null && currentPrice > 0) {
        alert.initialPrice = currentPrice;
      }
      if (alert.isMultiStepAlert) {
        resetMultiStepAlert(alert.id);
      }
      _history.removeWhere((a) => a.id == id);
      notifyListeners();
      _saveToStorage();
    }
  }

  /// Evaluates incoming ticks against active alerts.
  void checkTick(BiquoteTick tick) {
    evaluatePrice(tick.symbol, tick.mid);
  }

  /// Evaluates price against active alerts
  void evaluatePrice(String symbol, double currentPrice) {
    final matchingAlerts = _alerts
        .where(
          (a) =>
              a.isActive &&
              !a.isSnoozedAt(DateTime.now()) &&
              !a.isPatternAlert &&
              !a.isIndicatorAlert &&
              !a.isMultiStepAlert &&
              !a.isTimeScheduleAlert &&
              a.symbol == symbol,
        )
        .toList();

    for (final alert in matchingAlerts) {
      if (alert.checkTrigger(currentPrice)) {
        if (alert.cooldownMinutes > 0) {
          alert.lastTriggeredAt = DateTime.now();
        } else {
          alert.isActive = false;
        }
        alert.triggeredAt = DateTime.now();
        _history.insert(0, alert);
        notifyListeners();
        _saveToStorage();

        // 1. Play continuous alarm via AlarmService (wakes screen, bypasses DND)
        alarmService.playAlarm(
          ringtoneUri: alert.ringtoneUri,
          isCritical: _isCriticalAlert(alert),
          ttsText:
              'Price alert for ${alert.symbol}. Target reached at ${currentPrice.toStringAsFixed(4)}.',
        );

        // 2. Notify UI callback
        onAlertTriggered?.call(alert, currentPrice);
      }
    }

    // Evaluate active multi-step logic chains on price tick
    evaluateMultiStepAlerts(symbol, currentPrice: currentPrice);
  }

  /// Evaluates completed candles against active candlestick pattern alerts and indicators
  void evaluateCandles(
    String symbol,
    String timeframe,
    List<BiquoteCandle> candles, {
    bool isIntraCandle = false,
  }) {
    if (candles.length < 3) return;

    // Pattern alerts only evaluate on closed/completed candles (never intra-candle)
    if (!isIntraCandle) {
      final matchingAlerts = _alerts
          .where(
            (a) =>
                a.isActive &&
                !a.isSnoozedAt(DateTime.now()) &&
                a.isPatternAlert &&
                a.symbol == symbol &&
                a.timeframe.toLowerCase() == timeframe.toLowerCase() &&
                a.candlestickPattern != null,
          )
          .toList();

      for (final alert in matchingAlerts) {
        if (alert.cooldownMinutes > 0 && alert.lastTriggeredAt != null) {
          if (DateTime.now().difference(alert.lastTriggeredAt!).inMinutes <
              alert.cooldownMinutes) {
            continue;
          }
        }
        final isDetected = CandlestickDetector.matches(
          alert.candlestickPattern!,
          candles,
          requireClosedCandle: alert.triggerOnCandleClose,
        );
        if (isDetected) {
          if (alert.cooldownMinutes > 0) {
            alert.lastTriggeredAt = DateTime.now();
          } else {
            alert.isActive = false;
          }
          alert.triggeredAt = DateTime.now();
          _history.insert(0, alert);
          notifyListeners();
          _saveToStorage();

          // 1. Play continuous alarm via AlarmService
          alarmService.playAlarm(
            ringtoneUri: alert.ringtoneUri,
            ttsText:
                'Candlestick pattern confirmed. ${alert.candlestickPattern} on ${alert.symbol} ${alert.timeframe.toUpperCase()}.',
          );

          // 2. Notify UI callback with the candle close price
          onAlertTriggered?.call(alert, candles.last.close);
        }
      }
    }

    // Evaluate active technical indicator alerts
    final matchingIndicatorAlerts = _alerts
        .where(
          (a) =>
              a.isActive &&
              !a.isSnoozedAt(DateTime.now()) &&
              a.isIndicatorAlert &&
              a.symbol == symbol &&
              a.timeframe.toLowerCase() == timeframe.toLowerCase() &&
              a.indicatorConfig != null,
        )
        .toList();

    for (final alert in matchingIndicatorAlerts) {
      // If triggerOnCandleClose is enabled, only evaluate when candle has closed
      if (alert.triggerOnCandleClose && isIntraCandle) {
        continue;
      }
      if (alert.cooldownMinutes > 0 && alert.lastTriggeredAt != null) {
        if (DateTime.now().difference(alert.lastTriggeredAt!).inMinutes <
            alert.cooldownMinutes) {
          continue;
        }
      }

      final isDetected = IndicatorCalculator.checkTrigger(alert, candles);
      if (isDetected) {
        if (alert.cooldownMinutes > 0) {
          alert.lastTriggeredAt = DateTime.now();
        } else {
          alert.isActive = false;
        }
        alert.triggeredAt = DateTime.now();
        _history.insert(0, alert);
        notifyListeners();
        _saveToStorage();

        // 1. Play continuous alarm via AlarmService
        alarmService.playAlarm(
          ringtoneUri: alert.ringtoneUri,
          ttsText:
              'Indicator condition met on ${alert.symbol} ${alert.timeframe.toUpperCase()}.',
        );

        // 2. Notify UI callback with the candle close price
        onAlertTriggered?.call(alert, candles.last.close);
      }
    }

    // Evaluate active multi-step logic chains on candle update with exact timeframe context
    evaluateMultiStepAlerts(
      symbol,
      timeframe: timeframe,
      currentPrice: candles.last.close,
      candles: candles,
      isIntraCandle: isIntraCandle,
    );
  }

  /// Evaluates active multi-step logic chain alerts.
  /// Each multi-step alarm stays on with the alarms on the current level in the chain running.
  /// If that level completes, we move down the chain and the alarms in that next level become active,
  /// until the root rings or is cancelled by the human.
  void evaluateMultiStepAlerts(
    String symbol, {
    String? timeframe,
    double? currentPrice,
    List<BiquoteCandle>? candles,
    bool isIntraCandle = false,
  }) {
    final matchingChains = _alerts
        .where(
          (a) =>
              a.isActive &&
              !a.isSnoozedAt(DateTime.now()) &&
              a.isMultiStepAlert &&
              a.symbol == symbol,
        )
        .toList();

    for (final alert in matchingChains) {
      final config = alert.multiStepConfig;
      if (config == null || config.isAllCompleted) continue;

      // STEP TIMEOUT ENFORCEMENT:
      // If a step was completed, and the time limit in minutes has expired before reaching the next step,
      // the strategy setup is invalidated and MUST auto-reset back to Stage 1!
      final now = DateTime.now();
      if (config.isTimedOut(now)) {
        config.reset();
        _saveToStorage();
        notifyListeners();
        continue;
      }

      final currentStage = config.activeStage;
      if (currentStage == null || currentStage.isCompleted) continue;

      bool stageUpdated = false;

      // Evaluate ONLY the alarms in the current level of the chain
      for (final node in currentStage.nodes) {
        if (node.isSatisfied) continue; // Already satisfied in this stage

        bool rawSatisfied = false;
        switch (node.nodeType) {
          case AlertType.priceLevel:
            if (currentPrice != null &&
                currentPrice > 0 &&
                node.targetPrice > 0) {
              final baseline = node.previousPrice ?? alert.initialPrice;
              switch (node.condition) {
                case AlertCondition.crossesAbove:
                  rawSatisfied =
                      baseline < node.targetPrice &&
                      currentPrice >= node.targetPrice;
                  break;
                case AlertCondition.crossesBelow:
                  rawSatisfied =
                      baseline > node.targetPrice &&
                      currentPrice <= node.targetPrice;
                  break;
                case AlertCondition.hits:
                  rawSatisfied =
                      (currentPrice - node.targetPrice).abs() <=
                      (node.targetPrice * 0.0002);
                  break;
              }
              node.previousPrice = currentPrice;
            }
            break;

          case AlertType.candlestickPattern:
            // Ensure candle timeframe matches node timeframe and bar is completed
            if (!isIntraCandle &&
                timeframe != null &&
                node.timeframe.toLowerCase() == timeframe.toLowerCase() &&
                candles != null &&
                candles.length >= 3 &&
                node.candlestickPattern != null) {
              rawSatisfied = CandlestickDetector.matches(
                node.candlestickPattern!,
                candles,
              );
            }
            break;

          case AlertType.technicalIndicator:
            // Ensure candle timeframe matches node timeframe
            if (timeframe != null &&
                node.timeframe.toLowerCase() == timeframe.toLowerCase() &&
                candles != null &&
                candles.length >= 15 &&
                node.indicatorConfig != null) {
              final tempAlert = PriceAlert(
                id: 'temp_${node.id}',
                symbol: symbol,
                alertType: AlertType.technicalIndicator,
                indicatorConfig: node.indicatorConfig,
                timeframe: node.timeframe,
                createdAt: DateTime.now(),
                initialPrice:
                    currentPrice ??
                    (candles.isNotEmpty ? candles.last.close : 0.0),
              );
              rawSatisfied = IndicatorCalculator.checkTrigger(
                tempAlert,
                candles,
              );
            }
            break;

          case AlertType.multiStepChain:
            break;

          case AlertType.timeSchedule:
            break;
        }

        final isNodeSatisfied = node.isNegated ? !rawSatisfied : rawSatisfied;
        if (isNodeSatisfied) {
          node.isSatisfied = true;
          node.satisfiedAt = DateTime.now();
          stageUpdated = true;
        }
      }

      // Check if current stage condition is met by evaluating chained sub-alarms
      bool isStageCompleted = false;
      if (currentStage.nodes.isNotEmpty) {
        isStageCompleted = currentStage.nodes.first.isSatisfied;
        for (int i = 1; i < currentStage.nodes.length; i++) {
          final n = currentStage.nodes[i];
          if (n.operatorToPrevious == 'OR') {
            isStageCompleted = isStageCompleted || n.isSatisfied;
          } else {
            isStageCompleted = isStageCompleted && n.isSatisfied;
          }
        }
      }

      if (isStageCompleted) {
        currentStage.isCompleted = true;
        currentStage.completedAt = DateTime.now();
        config.currentStageIndex++;
        stageUpdated = true;

        if (config.isAllCompleted) {
          // ALL LEVELS COMPLETED: ROOT ALARM RINGS!
          alert.isActive = false;
          alert.triggeredAt = DateTime.now();
          _history.insert(0, alert);
          notifyListeners();
          _saveToStorage();

          final triggerP =
              currentPrice ??
              (candles != null && candles.isNotEmpty
                  ? candles.last.close
                  : alert.initialPrice);
          alarmService.playAlarm(
            ringtoneUri: alert.ringtoneUri,
            ttsText:
                'Strategy chain completed for ${alert.symbol}. All execution levels satisfied.',
          );
          onAlertTriggered?.call(alert, triggerP);
          continue;
        }
      }

      if (stageUpdated) {
        notifyListeners();
        _saveToStorage();
      }
    }
  }

  /// Resets a multi-step logic chain alert so it can be re-run from Level 1
  void resetMultiStepAlert(String id) {
    final idx = _alerts.indexWhere((a) => a.id == id);
    if (idx != -1) {
      final alert = _alerts[idx];
      alert.multiStepConfig?.reset();
      alert.isActive = true;
      alert.triggeredAt = null;
      _history.removeWhere((a) => a.id == id);
      notifyListeners();
      _saveToStorage();
    }
  }

  /// Reloads alerts and history from shared storage and re-synchronizes state with native service.
  /// Called when the app returns to foreground from background.
  Future<void> reloadAndSync() async {
    await _loadFromStorage();
  }

  // ── Scheduled / Calendar Alerts ──────────────────────────────────────────

  /// Creates a time-based calendar event alert that fires [minutesBefore] minutes
  /// before the event's scheduled release time.
  PriceAlert addScheduledCalendarAlert({
    required String eventId,
    required String eventName,
    required String currency,
    required DateTime eventTime,
    int minutesBefore = 5,
    String ringtoneTitle = 'Default Alarm',
    String? ringtoneUri,
  }) {
    final scheduledTime = eventTime.subtract(Duration(minutes: minutesBefore));
    final alert = PriceAlert(
      id: 'sched_${DateTime.now().millisecondsSinceEpoch}',
      symbol: currency.toUpperCase(),
      alertType: AlertType.timeSchedule,
      note: '$minutesBefore min before: $eventName ($currency)',
      createdAt: DateTime.now(),
      initialPrice: 0.0,
      ringtoneTitle: ringtoneTitle,
      ringtoneUri: ringtoneUri,
      scheduledTime: scheduledTime,
      eventId: eventId,
      eventName: eventName,
    );
    _alerts.insert(0, alert);
    notifyListeners();
    _saveToStorage();
    return alert;
  }

  /// Returns true if a calendar event with [eventId] already has an active scheduled alert.
  bool isEventAlertScheduled(String eventId) {
    return _alerts.any(
      (a) => a.isActive && a.isTimeScheduleAlert && a.eventId == eventId,
    );
  }

  /// Evaluates all active time-schedule alerts against the current wall-clock time.
  /// Called periodically by the Timer (every 3s) and also by the native foreground service.
  void evaluateScheduledAlerts() {
    final now = DateTime.now();
    final due = _alerts
        .where(
          (a) =>
              a.isActive &&
              !a.isSnoozedAt(now) &&
              a.isTimeScheduleAlert &&
              a.scheduledTime != null,
        )
        .where(
          (a) =>
              now.isAfter(a.scheduledTime!) ||
              now.isAtSameMomentAs(a.scheduledTime!),
        )
        .toList();

    for (final alert in due) {
      alert.isActive = false;
      alert.triggeredAt = now;
      _history.insert(0, alert);

      // Play alarm sound
      alarmService.playAlarm(
        ringtoneUri: alert.ringtoneUri,
        isCritical: _isCriticalAlert(alert),
      );

      // Notify UI
      onAlertTriggered?.call(alert, 0.0);
    }

    if (due.isNotEmpty) {
      notifyListeners();
      _saveToStorage();
    }
  }

  bool _isCriticalAlert(PriceAlert alert) {
    final description = '${alert.eventName ?? ''} ${alert.note}'.toLowerCase();
    return description.contains('high impact') ||
        description.contains('stop loss') ||
        description.contains('stop-loss');
  }

  final Set<String> _triggeredSessionsToday = {};

  /// Evaluates active trading sessions and triggers alert at the configured offset
  void evaluateSessionAlerts() {
    final settings = SettingsProvider();
    final selectedSessions = settings.selectedSessions;
    if (selectedSessions.isEmpty) return;

    final nowUtc = DateTime.now().toUtc();
    final todayStr =
        '${nowUtc.year}-${nowUtc.month.toString().padLeft(2, '0')}-${nowUtc.day.toString().padLeft(2, '0')}';

    int offsetMinutes = 0;
    if (settings.sessionAlertTiming.contains('5')) {
      offsetMinutes = 5;
    } else if (settings.sessionAlertTiming.contains('15')) {
      offsetMinutes = 15;
    }

    final sessionSchedules = [
      {
        'name': 'Sydney Open',
        'hour': 21,
        'min': 0,
        'desc': 'AUD, NZD pairs active',
      },
      {
        'name': 'Tokyo / Asian Open',
        'hour': 0,
        'min': 0,
        'desc': 'JPY pairs, Nikkei active',
      },
      {
        'name': 'London / European Open',
        'hour': 7,
        'min': 0,
        'desc': 'GBP, EUR pairs, DAX active',
      },
      {
        'name': 'New York / US Open',
        'hour': 12,
        'min': 0,
        'desc': 'USD pairs, Gold XAU, Indices active',
      },
      {
        'name': 'London / NY Overlap',
        'hour': 12,
        'min': 0,
        'desc': 'Peak daily global liquidity window',
      },
    ];

    for (final session in sessionSchedules) {
      final sessionName = session['name'] as String;
      final isEnabled = selectedSessions.any(
        (s) =>
            s.toLowerCase().contains(sessionName.toLowerCase().split(' ')[0]),
      );
      if (!isEnabled) continue;

      final sessionHour = session['hour'] as int;
      final sessionMin = session['min'] as int;

      var targetMinutes = sessionHour * 60 + sessionMin - offsetMinutes;
      if (targetMinutes < 0) targetMinutes += 1440;

      final currentMinutes = nowUtc.hour * 60 + nowUtc.minute;
      final triggerKey = '${todayStr}_$sessionName';

      if (currentMinutes == targetMinutes &&
          !_triggeredSessionsToday.contains(triggerKey)) {
        _triggeredSessionsToday.add(triggerKey);

        final alert = PriceAlert(
          id: 'session_${DateTime.now().millisecondsSinceEpoch}',
          symbol: 'SESSION',
          alertType: AlertType.timeSchedule,
          note: '$sessionName (${session["desc"]})',
          createdAt: DateTime.now(),
          initialPrice: 0.0,
          ringtoneTitle: settings.soundTitle,
          ringtoneUri: settings.soundUri,
          triggeredAt: DateTime.now(),
          isActive: false,
        );

        _history.insert(0, alert);
        notifyListeners();
        _saveToStorage();

        final tts = '$sessionName is now open. ${session["desc"]}.';
        alarmService.playAlarm(ringtoneUri: settings.soundUri, ttsText: tts);
        onAlertTriggered?.call(alert, 0.0);
      }
    }
  }

  /// Automatically deactivates unhit price alerts that have exceeded configured TTL
  void _checkAlertTtl() {
    final ttl = SettingsProvider().ttlDuration;
    final now = DateTime.now();
    bool changed = false;
    for (final alert in _alerts) {
      if (alert.snoozedUntil != null && !now.isBefore(alert.snoozedUntil!)) {
        alert.snoozedUntil = null;
        changed = true;
      }
      if (ttl != null &&
          alert.isActive &&
          now.difference(alert.createdAt) >= ttl) {
        alert.isActive = false;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _saveToStorage();
    }
  }

  /// Snoozes an alert for the configured duration (reads setting_default_snooze)
  void snoozeAlert(String alertId, {Duration? duration}) {
    alarmService.stopAlarm();
    final snoozeDuration =
        duration ?? Duration(minutes: SettingsProvider().defaultSnoozeMinutes);
    PriceAlert? alert;
    final activeIndex = _alerts.indexWhere((item) => item.id == alertId);
    if (activeIndex >= 0) {
      alert = _alerts[activeIndex];
    } else {
      final historyIndex = _history.indexWhere((item) => item.id == alertId);
      if (historyIndex >= 0) {
        alert = _history.removeAt(historyIndex);
        _alerts.insert(0, alert);
      }
    }
    if (alert == null) return;
    alert
      ..isActive = true
      ..triggeredAt = null
      ..snoozedUntil = DateTime.now().add(snoozeDuration);
    _history.removeWhere((item) => item.id == alertId);
    if (alert.isMultiStepAlert) resetMultiStepAlert(alert.id);
    notifyListeners();
    _saveToStorage();
  }

  @override
  void dispose() {
    SettingsProvider().removeListener(_onSettingsChanged);
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
