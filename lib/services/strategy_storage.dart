import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ai_models.dart';
import '../models/default_specialists.dart';
import 'storage_service.dart';
import 'strategy_catalog_service.dart';

class StrategyStorage {
  static const String _strategiesKey = 'ai_trading_strategies';
  static const String _specialistsKey = 'ai_specialist_agents';
  static const String _recentRunsKey = 'ai_recent_strategy_runs';
  static const String _lastSignalKey = 'ai_last_chart_signal';

  static final StrategyStorage _instance = StrategyStorage._internal();
  factory StrategyStorage() => _instance;
  StrategyStorage._internal() {
    StrategyCatalogService.instance.onCatalogChanged = () async {
      _cachedStrategies = null;
      _cachedSpecialists = null;
    };
  }

  List<TradingStrategy>? _cachedStrategies;
  List<SpecialistAgentConfig>? _cachedSpecialists;
  List<RecentStrategyRun>? _cachedRecentRuns;

  // -------------------------------------------------------------
  // SPECIALIST AGENTS MANAGEMENT (Single specialists)
  // -------------------------------------------------------------
  Future<List<SpecialistAgentConfig>> getSpecialists() async {
    if (_cachedSpecialists != null) return List.of(_cachedSpecialists!);

    try {
      final raw = await StorageService.getString(_specialistsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final list = decoded
            .map(
              (e) => SpecialistAgentConfig.fromJson(e as Map<String, dynamic>),
            )
            .toList();
        if (list.isNotEmpty) {
          // Merge any newly introduced default specialists if not present
          final allDefaults = DefaultSpecialists.getAll();
          bool addedNew = false;
          for (final def in allDefaults) {
            if (!list.any((s) => s.id == def.id)) {
              list.add(def);
              addedNew = true;
            }
          }
          if (addedNew) await _persistSpecialists(list);
          return _mergeSharedSpecialists(list);
        }
      }
    } catch (e) {
      debugPrint('StrategyStorage load specialists error: $e');
    }

    final defaults = DefaultSpecialists.getAll();
    await _persistSpecialists(defaults);
    return _mergeSharedSpecialists(defaults);
  }

  List<SpecialistAgentConfig> _mergeSharedSpecialists(
    List<SpecialistAgentConfig> local,
  ) {
    final catalog = StrategyCatalogService.instance;
    final shared = {for (final item in catalog.specialists) item.id: item};
    // Partial or empty remote catalogs must preserve offline, bundled, and
    // user-created entries. Published documents override matching IDs.
    final result = local.map((item) => shared.remove(item.id) ?? item).toList()
      ..addAll(shared.values);
    _cachedSpecialists = result;
    return List.of(result);
  }

  Future<void> saveSpecialist(SpecialistAgentConfig specialist) async {
    final list = await getSpecialists();
    final index = list.indexWhere((s) => s.id == specialist.id);
    if (index != -1) {
      list[index] = specialist;
    } else {
      list.add(specialist);
    }
    _cachedSpecialists = list;
    await _persistSpecialists(list);
  }

  Future<void> deleteSpecialist(String id) async {
    final list = await getSpecialists();
    list.removeWhere((s) => s.id == id);
    _cachedSpecialists = list;
    await _persistSpecialists(list);
  }

  Future<void> _persistSpecialists(List<SpecialistAgentConfig> list) async {
    try {
      final encoded = jsonEncode(list.map((s) => s.toJson()).toList());
      await StorageService.setString(_specialistsKey, encoded);
    } catch (e) {
      debugPrint('StrategyStorage persist specialists error: $e');
    }
  }

  // -------------------------------------------------------------
  // TRADING STRATEGIES MANAGEMENT (Multi-Agent & Presets)
  // -------------------------------------------------------------
  Future<List<TradingStrategy>> getStrategies() async {
    if (_cachedStrategies != null) return List.of(_cachedStrategies!);

    try {
      final raw = await StorageService.getString(_strategiesKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final list = decoded
            .map((e) => TradingStrategy.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          return _mergeSharedStrategies(list);
        }
      }
    } catch (e) {
      debugPrint('StrategyStorage load strategies error: $e');
    }

    // Default presets matching the new UI design package
    final defaults = DefaultSpecialists.getDefaultStrategies();
    await _persistStrategies(defaults);
    return _mergeSharedStrategies(defaults);
  }

  List<TradingStrategy> _mergeSharedStrategies(List<TradingStrategy> local) {
    final catalog = StrategyCatalogService.instance;
    final shared = {for (final item in catalog.strategies) item.id: item};
    final sharedSpecialists = {
      for (final item in catalog.specialists) item.id: item,
    };
    final result = local.map((item) => shared.remove(item.id) ?? item).toList()
      ..addAll(shared.values);
    for (var index = 0; index < result.length; index++) {
      final strategy = result[index];
      result[index] = strategy.copyWith(
        specialists: strategy.specialists
            .map((item) => sharedSpecialists[item.id] ?? item)
            .toList(),
      );
    }
    _cachedStrategies = result;
    return List.of(result);
  }

  Future<void> saveStrategy(TradingStrategy strategy) async {
    final list = await getStrategies();
    final index = list.indexWhere((s) => s.id == strategy.id);
    if (index != -1) {
      list[index] = strategy;
    } else {
      list.add(strategy);
    }
    _cachedStrategies = list;
    await _persistStrategies(list);
  }

  Future<void> deleteStrategy(String id) async {
    final list = await getStrategies();
    list.removeWhere((s) => s.id == id);
    _cachedStrategies = list;
    await _persistStrategies(list);
  }

  Future<void> _persistStrategies(List<TradingStrategy> list) async {
    try {
      final encoded = jsonEncode(list.map((s) => s.toJson()).toList());
      await StorageService.setString(_strategiesKey, encoded);
    } catch (e) {
      debugPrint('StrategyStorage persist strategies error: $e');
    }
  }

  // -------------------------------------------------------------
  // RECENT RUNS MANAGEMENT
  // -------------------------------------------------------------
  Future<List<RecentStrategyRun>> getRecentRuns() async {
    if (_cachedRecentRuns != null) return _cachedRecentRuns!;

    try {
      final raw = await StorageService.getString(_recentRunsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final list = decoded
            .map((e) => RecentStrategyRun.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) {
          _cachedRecentRuns = list;
          return list;
        }
      }
    } catch (e) {
      debugPrint('StrategyStorage load recent runs error: $e');
    }

    // Initial default seed matching the UI screenshot exactly
    final now = DateTime.now();
    final sampleRuns = [
      RecentStrategyRun(
        id: 'run_sample_1',
        direction: SignalDirection.buy,
        symbol: 'EUR/USD',
        strategyOrAgentName: 'SMC + Wyckoff',
        timeframe: '15m + 4H',
        score: 78,
        timestamp: DateTime(now.year, now.month, now.day, 9, 30),
        signal: AgentSignal(
          direction: SignalDirection.buy,
          analysis: 'Bullish BOS above 1.0872 after sweep of sell-side liquidity. Unmitigated FVG at 1.0861–1.0866. Wyckoff Phase D markup confirms spring at 1.0838.',
          theory: 'SMC Institutional Flow & Wyckoff Phase D Markup',
          entryPrice: 1.08720,
          stopLoss: 1.08410,
          takeProfit: 1.09340,
          takeProfit2: 1.09710,
          confidence: 78,
          agentName: 'Consolidator Officer',
          timestamp: DateTime(now.year, now.month, now.day, 9, 30),
          symbol: 'EUR/USD',
          specialistScores: {'SMC': 74, 'Wyckoff': 68},
          criticPenalty: -4,
          groundingVerification: '5 / 6 verified',
          groundingAuditSummary: 'One support level cited at 1.0801 sits outside the supplied range and was removed. Trend claim matches EMA 50 > 200.',
        ),
        specialistSignals: [
          AgentSignal(
            direction: SignalDirection.buy,
            analysis: 'Bullish BOS above 1.0872 after sweep of sell-side liquidity. Unmitigated FVG 1.0861–1.0866 acts as prime discount entry zone.',
            theory: 'SMC Liquidity Sweep & Order Block Mitigation',
            entryPrice: 1.08720,
            stopLoss: 1.08410,
            takeProfit: 1.09340,
            confidence: 74,
            agentName: 'SMC Structure Specialist',
            timestamp: DateTime(now.year, now.month, now.day, 9, 30),
            symbol: 'EUR/USD',
          ),
          AgentSignal(
            direction: SignalDirection.buy,
            analysis: 'Phase D markup — Spring confirmed at 1.0838, volume climax absorbed with sign of strength (SOS). Ready for cause-to-effect projection.',
            theory: 'Wyckoff Accumulation Phase D Markup',
            entryPrice: 1.08710,
            stopLoss: 1.08380,
            takeProfit: 1.09400,
            confidence: 68,
            agentName: 'Wyckoff Phase Specialist',
            timestamp: DateTime(now.year, now.month, now.day, 9, 30),
            symbol: 'EUR/USD',
          ),
        ],
        groundingCritique: 'Audit against raw 100 OHLC candles:\n• Confirmed: Swing low at 1.0838 is genuine on 4H chart.\n• Confirmed: FVG between 1.0861 and 1.0866 is visible and unmitigated.\n• Warning: Support level cited at 1.0801 sits outside supplied 100 candle range and was excluded.\n• Confirmed: Trend claim matches EMA 50 (1.0865) > EMA 200 (1.0820).',
      ),
      RecentStrategyRun(
        id: 'run_sample_2',
        direction: SignalDirection.wait,
        symbol: 'XAU/USD',
        strategyOrAgentName: 'Volume Profile Hunter',
        timeframe: '1H',
        score: 41,
        timestamp: now.subtract(const Duration(days: 1)),
        signal: AgentSignal(
          direction: SignalDirection.wait,
          analysis: 'Price oscillating near POC 2642.50. Value area high tested without conviction. Low volume node rejection pending confirmation.',
          theory: 'Volume Profile Auction Value Rejection',
          entryPrice: 2642.50,
          stopLoss: 2634.00,
          takeProfit: 2658.00,
          takeProfit2: 2668.00,
          confidence: 41,
          agentName: 'Volume Profile Specialist',
          timestamp: now.subtract(const Duration(days: 1)),
          symbol: 'XAU/USD',
          specialistScores: {'Volume Profile': 45},
          criticPenalty: -4,
          groundingVerification: '6 / 6 verified',
          groundingAuditSummary: 'All referenced volume nodes align with current OHLC historical distribution. No structural breakout detected.',
        ),
        specialistSignals: [
          AgentSignal(
            direction: SignalDirection.wait,
            analysis: 'Price oscillating near POC 2642.50. Value area high tested without conviction. Low volume node rejection pending confirmation.',
            theory: 'Volume Profile Auction Value Rejection',
            entryPrice: 2642.50,
            stopLoss: 2634.00,
            takeProfit: 2658.00,
            confidence: 41,
            agentName: 'Volume Profile Specialist',
            timestamp: now.subtract(const Duration(days: 1)),
            symbol: 'XAU/USD',
          ),
        ],
        groundingCritique: 'Audit against raw 100 OHLC candles:\n• Confirmed: Point of Control sits at 2642.50.\n• Confirmed: No directional expansion detected outside value area.\n• All levels strictly verified within supplied historical dataset.',
      ),
    ];

    _cachedRecentRuns = sampleRuns;
    await _persistRecentRuns(sampleRuns);
    return sampleRuns;
  }

  /// Reads only persisted runs, without invoking the demo-seed fallback used by
  /// the Strategies screen. Demo sample rows must never be included in exports.
  Future<List<RecentStrategyRun>> getPersistedRecentRuns() async {
    try {
      final raw = await StorageService.getString(_recentRunsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                RecentStrategyRun.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((run) => !_isDemoRun(run.id))
          .toList();
    } catch (e) {
      debugPrint('StrategyStorage read persisted runs for export error: $e');
      return const [];
    }
  }

  static bool _isDemoRun(String id) =>
      id == 'run_sample_1' || id == 'run_sample_2';

  Future<void> addRecentRun(RecentStrategyRun run) async {
    final list = await getRecentRuns();
    list.insert(0, run);
    if (list.length > 25) {
      list.removeRange(25, list.length);
    }
    _cachedRecentRuns = list;
    await _persistRecentRuns(list);
  }

  Future<void> _persistRecentRuns(List<RecentStrategyRun> list) async {
    try {
      final encoded = jsonEncode(list.map((r) => r.toJson()).toList());
      await StorageService.setString(_recentRunsKey, encoded);
    } catch (e) {
      debugPrint('StrategyStorage persist recent runs error: $e');
    }
  }

  Future<Map<String, dynamic>> exportBackupData() async {
    final specialists = await getSpecialists();
    final strategies = await getStrategies();
    final recentRuns = await getPersistedRecentRuns();
    return {
      'specialists': specialists.map((item) => item.toJson()).toList(),
      'strategies': strategies.map((item) => item.toJson()).toList(),
      'recentRuns': recentRuns.map((item) => item.toJson()).toList(),
    };
  }

  static void validateBackupData(Map<String, dynamic> data) {
    for (var item in (data['specialists'] as List? ?? const [])) {
      SpecialistAgentConfig.fromJson(Map<String, dynamic>.from(item as Map));
    }
    for (var item in (data['strategies'] as List? ?? const [])) {
      TradingStrategy.fromJson(Map<String, dynamic>.from(item as Map));
    }
    for (var item in (data['recentRuns'] as List? ?? const [])) {
      RecentStrategyRun.fromJson(Map<String, dynamic>.from(item as Map));
    }
  }

  Future<void> importBackupData(
    Map<String, dynamic> data, {
    bool strictPersistence = false,
  }) async {
    // Decode each section before mutating storage so malformed data cannot
    // leave half of the AI configuration replaced.
    final specialists = (data['specialists'] as List?)
        ?.map(
          (item) => SpecialistAgentConfig.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    final strategies = (data['strategies'] as List?)
        ?.map(
          (item) =>
              TradingStrategy.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    final recentRuns = (data['recentRuns'] as List?)
        ?.map(
          (item) => RecentStrategyRun.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();

    if (strictPersistence) {
      // Write first, then expose new values through the in-memory caches. Errors
      // propagate to the restore transaction, which attempts a strict rollback.
      if (specialists != null) {
        await StorageService.setStringRequired(
          _specialistsKey,
          jsonEncode(specialists.map((s) => s.toJson()).toList()),
        );
      }
      if (strategies != null) {
        await StorageService.setStringRequired(
          _strategiesKey,
          jsonEncode(strategies.map((s) => s.toJson()).toList()),
        );
      }
      if (recentRuns != null) {
        await StorageService.setStringRequired(
          _recentRunsKey,
          jsonEncode(recentRuns.map((r) => r.toJson()).toList()),
        );
      }
    }
    if (specialists != null) {
      _cachedSpecialists = specialists;
      if (!strictPersistence) await _persistSpecialists(specialists);
    }
    if (strategies != null) {
      _cachedStrategies = strategies;
      if (!strictPersistence) await _persistStrategies(strategies);
    }
    if (recentRuns != null) {
      _cachedRecentRuns = recentRuns;
      if (!strictPersistence) await _persistRecentRuns(recentRuns);
    }
  }

  Future<void> saveLastChartSignal(AgentSignal? signal) async {
    try {
      if (signal == null) {
        await StorageService.remove(_lastSignalKey);
      } else {
        final encoded = jsonEncode(signal.toJson());
        await StorageService.setString(_lastSignalKey, encoded);
      }
    } catch (e) {
      debugPrint('StrategyStorage save last signal error: $e');
    }
  }

  Future<AgentSignal?> getLastChartSignal() async {
    try {
      final raw = await StorageService.getString(_lastSignalKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return AgentSignal.fromJson(decoded);
      }
    } catch (e) {
      debugPrint('StrategyStorage get last signal error: $e');
    }
    return null;
  }
}
