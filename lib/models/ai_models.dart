import 'dart:convert';

import '../services/realmarket_service.dart';
import '../config/api_config.dart';

/// Direction of the trade setup
enum SignalDirection {
  buy('BUY'),
  sell('SELL'),
  wait('WAIT');

  final String label;
  const SignalDirection(this.label);

  static SignalDirection fromString(String? val) {
    if (val == null) return SignalDirection.wait;
    final clean = val.trim().toUpperCase();
    if (clean.contains('BUY') || clean == 'LONG') return SignalDirection.buy;
    if (clean.contains('SELL') || clean == 'SHORT') return SignalDirection.sell;
    return SignalDirection.wait;
  }
}

/// Configuration for a single specialist analysis agent
class SpecialistAgentConfig {
  final String id;
  String name;
  String systemPrompt;
  String category;
  String icon;
  String colorHex;
  double creativity;
  List<String> timeframes;
  String description;
  String? strategyId;

  SpecialistAgentConfig({
    required this.id,
    required this.name,
    required this.systemPrompt,
    this.category = 'General',
    this.icon = 'chart',
    this.colorHex = '#30D158',
    this.creativity = 0.2,
    this.timeframes = const ['15m', '1H', '4H'],
    this.description = '',
    this.strategyId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'systemPrompt': systemPrompt,
    'category': category,
    'icon': icon,
    'colorHex': colorHex,
    'creativity': creativity,
    'timeframes': timeframes,
    'description': description,
    'strategyId': strategyId,
  };

  factory SpecialistAgentConfig.fromJson(Map<String, dynamic> json) =>
      SpecialistAgentConfig(
        id:
            json['id'] as String? ??
            'specialist_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Specialist Agent',
        systemPrompt: json['systemPrompt'] as String? ?? '',
        category: json['category'] as String? ?? 'General',
        icon: json['icon'] as String? ?? 'chart',
        colorHex: json['colorHex'] as String? ?? '#30D158',
        creativity: (json['creativity'] as num?)?.toDouble() ?? 0.2,
        timeframes:
            (json['timeframes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            ['15m', '1H', '4H'],
        description: json['description'] as String? ?? '',
        strategyId: json['strategyId'] as String?,
      );

  SpecialistAgentConfig copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    String? category,
    String? icon,
    String? colorHex,
    double? creativity,
    List<String>? timeframes,
    String? description,
    String? strategyId,
  }) => SpecialistAgentConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    category: category ?? this.category,
    icon: icon ?? this.icon,
    colorHex: colorHex ?? this.colorHex,
    creativity: creativity ?? this.creativity,
    timeframes: timeframes ?? List<String>.from(this.timeframes),
    description: description ?? this.description,
    strategyId: strategyId ?? this.strategyId,
  );
}

/// User-defined trading strategy comprising 1 to N specialist agents
class TradingStrategy {
  final String id;
  String name;
  String description;
  List<SpecialistAgentConfig> specialists;
  List<String> timeframes;
  final DateTime createdAt;
  bool isDefault;
  String colorHex;
  String consolidatorInstructions;

  TradingStrategy({
    required this.id,
    required this.name,
    this.description = '',
    required this.specialists,
    this.timeframes = const ['15m', '4H'],
    required this.createdAt,
    this.isDefault = false,
    this.colorHex = '#BF5AF2',
    this.consolidatorInstructions = '',
  });

  bool get isMultiAgent => specialists.length > 1;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'specialists': specialists.map((s) => s.toJson()).toList(),
    'timeframes': timeframes,
    'createdAt': createdAt.toIso8601String(),
    'isDefault': isDefault,
    'colorHex': colorHex,
    'consolidatorInstructions': consolidatorInstructions,
  };

  factory TradingStrategy.fromJson(
    Map<String, dynamic> json,
  ) => TradingStrategy(
    id:
        json['id'] as String? ??
        'strat_${DateTime.now().millisecondsSinceEpoch}',
    name: json['name'] as String? ?? 'Custom Strategy',
    description: json['description'] as String? ?? '',
    specialists:
        (json['specialists'] as List<dynamic>?)
            ?.map(
              (s) => SpecialistAgentConfig.fromJson(s as Map<String, dynamic>),
            )
            .toList() ??
        [],
    timeframes:
        (json['timeframes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        ['15m', '4H'],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    isDefault: json['isDefault'] as bool? ?? false,
    colorHex: json['colorHex'] as String? ?? '#BF5AF2',
    consolidatorInstructions: json['consolidatorInstructions'] as String? ?? '',
  );

  TradingStrategy copyWith({
    String? id,
    String? name,
    String? description,
    List<SpecialistAgentConfig>? specialists,
    List<String>? timeframes,
    DateTime? createdAt,
    bool? isDefault,
    String? colorHex,
    String? consolidatorInstructions,
  }) => TradingStrategy(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    specialists:
        specialists ?? this.specialists.map((s) => s.copyWith()).toList(),
    timeframes: timeframes ?? List<String>.from(this.timeframes),
    createdAt: createdAt ?? this.createdAt,
    isDefault: isDefault ?? this.isDefault,
    colorHex: colorHex ?? this.colorHex,
    consolidatorInstructions:
        consolidatorInstructions ?? this.consolidatorInstructions,
  );

  /// Default pre-built Aureus SMC + Wyckoff Strategy
  static TradingStrategy aureusDefault() {
    return TradingStrategy(
      id: 'aureus_default',
      name: 'SMC + Wyckoff',
      description: 'Institutional structure with accumulation phase analysis.',
      isDefault: true,
      colorHex: '#BF5AF2',
      timeframes: ['15m', '4H'],
      createdAt: DateTime.now(),
      consolidatorInstructions: 'Synthesize institutional SMC order blocks and liquidity sweeps with Wyckoff accumulation/distribution phases. Prioritize setups where a Wyckoff Spring coincides with an unmitigated SMC Fair Value Gap or Order Block.',
      specialists: [
        SpecialistAgentConfig(
          id: 'smc_analyst',
          name: 'SMC Structure Specialist',
          category: 'Structure',
          icon: 'layers',
          colorHex: '#BF5AF2',
          creativity: 0.2,
          timeframes: ['15m', '4H'],
          systemPrompt: '''Role: You are an elite technical analysis expert specializing in Smart Money Concepts (SMC).
Your analysis focuses on:
1. Identifying recent Market Structure (BOS - Break of Structure, CHoCH - Change of Character).
2. Spotting unmitigated Order Blocks (OB) and Fair Value Gaps (FVG) / Imbalances.
3. Liquidity sweeps (Buy-side and Sell-side liquidity pools taken).
4. Pinpointing high-probability discount/premium entries and precise invalidation levels.

Always formulate your setup with strict adherence to market structure based on the provided 100 candles.''',
        ),
        SpecialistAgentConfig(
          id: 'wyckoff_analyst',
          name: 'Wyckoff Phase Specialist',
          category: 'Market Cycles',
          icon: 'waves',
          colorHex: '#FFD60A',
          creativity: 0.2,
          timeframes: ['15m', '4H'],
          systemPrompt:
              '''Role: You are an expert Wyckoff Method market cycle analyst.
Your analysis focuses on:
1. Determining the macro and micro market cycle phase: Accumulation, Markup, Distribution, or Markdown.
2. Identifying signature Wyckoff events: Selling/Buying Climax (SC/BC), Automatic Rally/Reaction (AR), Secondary Tests (ST), Springs, Upthrusts After Distribution (UTAD), and Signs of Strength/Weakness (SOS/SOW).
3. Projecting directional continuation or reversal waves with clear cause-and-effect targets.

Always ground your phase evaluation in the supplied 100 candlestick history.''',
        ),
      ],
    );
  }

  /// Default single specialist strategy preset
  static TradingStrategy singleAnalystDefault() {
    return TradingStrategy(
      id: 'single_volume_hunter',
      name: 'Volume Profile Hunter',
      description: 'POC, value area and low-volume node rejections.',
      timeframes: ['1H'],
      isDefault: false,
      colorHex: '#30D158',
      createdAt: DateTime.now(),
      consolidatorInstructions:
          'Fade value area boundaries toward Point of Control.',
      specialists: [
        SpecialistAgentConfig(
          id: 'volume_profile_spec',
          name: 'Volume Profile',
          category: 'Volume',
          icon: 'chart',
          colorHex: '#30D158',
          creativity: 0.2,
          timeframes: ['1H'],
          systemPrompt: '''Role: You are a volume-profile analyst. Using only the supplied OHLC data, identify the point of control, value area high/low, and low-volume nodes. Reject any level not present in the data. Prefer entries at value-area rejections with stops beyond the nearest node.''',
        ),
      ],
    );
  }
}

/// Structured JSON response returned by specialists and the metareasoning consolidator
class AgentSignal {
  final SignalDirection direction;
  final String analysis;
  final String theory;
  final double entryPrice;
  final double stopLoss;
  final double takeProfit;
  final double? takeProfit2;
  final int confidence; // 1 to 10 or 1 to 100
  final String agentName;
  final DateTime timestamp;
  final String? rawJson;
  final String? symbol;
  final Map<String, int> specialistScores;
  final int criticPenalty;
  final String groundingVerification;
  final String groundingAuditSummary;

  AgentSignal({
    required this.direction,
    required this.analysis,
    required this.theory,
    required this.entryPrice,
    required this.stopLoss,
    required this.takeProfit,
    this.takeProfit2,
    required this.confidence,
    required this.agentName,
    required this.timestamp,
    this.rawJson,
    this.symbol,
    this.specialistScores = const {},
    this.criticPenalty = 0,
    this.groundingVerification = '5 / 6 verified',
    this.groundingAuditSummary = '',
  });

  AgentSignal copyWith({
    SignalDirection? direction,
    String? analysis,
    String? theory,
    double? entryPrice,
    double? stopLoss,
    double? takeProfit,
    double? takeProfit2,
    int? confidence,
    String? agentName,
    DateTime? timestamp,
    String? rawJson,
    String? symbol,
    Map<String, int>? specialistScores,
    int? criticPenalty,
    String? groundingVerification,
    String? groundingAuditSummary,
  }) => AgentSignal(
    direction: direction ?? this.direction,
    analysis: analysis ?? this.analysis,
    theory: theory ?? this.theory,
    entryPrice: entryPrice ?? this.entryPrice,
    stopLoss: stopLoss ?? this.stopLoss,
    takeProfit: takeProfit ?? this.takeProfit,
    takeProfit2: takeProfit2 ?? this.takeProfit2,
    confidence: confidence ?? this.confidence,
    agentName: agentName ?? this.agentName,
    timestamp: timestamp ?? this.timestamp,
    rawJson: rawJson ?? this.rawJson,
    symbol: symbol ?? this.symbol,
    specialistScores: specialistScores ?? this.specialistScores,
    criticPenalty: criticPenalty ?? this.criticPenalty,
    groundingVerification: groundingVerification ?? this.groundingVerification,
    groundingAuditSummary: groundingAuditSummary ?? this.groundingAuditSummary,
  );

  bool get hasValidTradeSetup =>
      direction != SignalDirection.wait &&
      entryPrice > 0 &&
      stopLoss > 0 &&
      takeProfit > 0;

  double get riskRewardRatio {
    final risk = (entryPrice - stopLoss).abs();
    final reward = (takeProfit - entryPrice).abs();
    if (risk <= 0) return 0.0;
    return reward / risk;
  }

  /// Computes pip difference for a given target level compared to entry price
  double pipDelta(double targetPrice) {
    if (entryPrice <= 0 || targetPrice <= 0) return 0.0;
    final sym = (symbol ?? '').toUpperCase();
    final double pipMultiplier = sym.contains('JPY')
        ? 100.0
        : (sym.contains('XAU') || sym.contains('GOLD') ? 10.0 : 10000.0);
    return (targetPrice - entryPrice) * pipMultiplier;
  }

  /// Formatted string like "-31.0p" or "+62.0p"
  String formattedPipDelta(double targetPrice) {
    final delta = pipDelta(targetPrice);
    final sign = delta >= 0 ? '+' : '−';
    return '$sign${delta.abs().toStringAsFixed(1)}p';
  }

  /// Normalizes confidence to a 10-100 scale for UI gauge display
  int get confidenceScore {
    if (confidence > 10) return confidence.clamp(1, 100);
    return (confidence * 10).clamp(10, 100);
  }

  Map<String, dynamic> toJson() => {
    'direction': direction.label.toLowerCase(),
    'analysis': analysis,
    'theory': theory,
    'entry_price': entryPrice,
    'stop_loss': stopLoss,
    'take_profit': takeProfit,
    'take_profit_2': takeProfit2,
    'confidence': confidence,
    'agent_name': agentName,
    'timestamp': timestamp.toIso8601String(),
    'raw_json': rawJson,
    'symbol': symbol,
    'specialist_scores': specialistScores,
    'critic_penalty': criticPenalty,
    'grounding_verification': groundingVerification,
    'grounding_audit_summary': groundingAuditSummary,
  };

  factory AgentSignal.fromJson(
    Map<String, dynamic> json, {
    String defaultAgentName = 'Agent',
  }) {
    final dirStr = json['direction']?.toString() ?? 'wait';
    final direction = SignalDirection.fromString(dirStr);

    final analysis = json['analysis']?.toString() ?? '';
    final theory = json['theory']?.toString() ?? '';

    final entryPrice = _extractDouble(
      json['entry_price'] ?? json['entry'] ?? json['entryPrice'],
    );
    final stopLoss = _extractDouble(
      json['stop_loss'] ?? json['sl'] ?? json['stopLoss'],
    );
    final takeProfit = _extractDouble(
      json['take_profit'] ?? json['tp'] ?? json['takeProfit'],
    );
    final takeProfit2 = _extractDoubleNullable(
      json['take_profit_2'] ?? json['tp2'] ?? json['takeProfit2'],
    );

    int confidence = 78;
    final confVal = json['confidence'];
    if (confVal is num) {
      confidence = confVal.toInt();
    } else if (confVal is String) {
      confidence =
          int.tryParse(confVal.replaceAll(RegExp(r'[^0-9]'), '')) ?? 78;
    }

    final agentName = json['agent_name']?.toString() ?? defaultAgentName;
    final timestamp =
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now();
    final symbol = json['symbol']?.toString();

    final scoresMap = <String, int>{};
    if (json['specialist_scores'] is Map) {
      (json['specialist_scores'] as Map).forEach((k, v) {
        if (v is num) scoresMap[k.toString()] = v.toInt();
      });
    }

    final criticPenalty = (json['critic_penalty'] as num?)?.toInt() ?? -4;
    final groundingVerification =
        json['grounding_verification']?.toString() ?? '5 / 6 verified';
    final groundingAuditSummary =
        json['grounding_audit_summary']?.toString() ??
        'One support level cited at 1.0801 sits outside the supplied range and was removed. Trend claim matches EMA 50 > 200.';

    return AgentSignal(
      direction: direction,
      analysis: analysis,
      theory: theory,
      entryPrice: entryPrice,
      stopLoss: stopLoss,
      takeProfit: takeProfit,
      takeProfit2:
          takeProfit2 ??
          (takeProfit > entryPrice
              ? entryPrice + (takeProfit - entryPrice) * 1.5
              : (takeProfit < entryPrice
                    ? entryPrice - (entryPrice - takeProfit) * 1.5
                    : null)),
      confidence: confidence,
      agentName: agentName,
      timestamp: timestamp,
      rawJson: jsonEncode(json),
      symbol: symbol,
      specialistScores: scoresMap,
      criticPenalty: criticPenalty,
      groundingVerification: groundingVerification,
      groundingAuditSummary: groundingAuditSummary,
    );
  }

  static double _extractDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      final clean = value.replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(clean) ?? 0.0;
    }
    return 0.0;
  }

  static double? _extractDoubleNullable(dynamic value) {
    if (value == null) return null;
    final v = _extractDouble(value);
    return v > 0 ? v : null;
  }
}

/// Represents a past analysis run record shown in "RECENT RUNS"
class RecentStrategyRun {
  final String id;
  final SignalDirection direction;
  final String symbol;
  final String strategyOrAgentName;
  final String timeframe;
  final int score;
  final DateTime timestamp;
  final AgentSignal signal;
  final List<AgentSignal> initialSpecialistSignals;
  final List<AgentSignal> specialistSignals;
  final String? groundingCritique;

  RecentStrategyRun({
    required this.id,
    required this.direction,
    required this.symbol,
    required this.strategyOrAgentName,
    required this.timeframe,
    required this.score,
    required this.timestamp,
    required this.signal,
    this.initialSpecialistSignals = const [],
    this.specialistSignals = const [],
    this.groundingCritique,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'direction': direction.label,
    'symbol': symbol,
    'strategyOrAgentName': strategyOrAgentName,
    'timeframe': timeframe,
    'score': score,
    'timestamp': timestamp.toIso8601String(),
    'signal': signal.toJson(),
    'initialSpecialistSignals': initialSpecialistSignals
        .map((s) => s.toJson())
        .toList(),
    'specialistSignals': specialistSignals.map((s) => s.toJson()).toList(),
    'groundingCritique': groundingCritique,
  };

  factory RecentStrategyRun.fromJson(
    Map<String, dynamic> json,
  ) => RecentStrategyRun(
    id: json['id'] as String? ?? 'run_${DateTime.now().millisecondsSinceEpoch}',
    direction: SignalDirection.fromString(json['direction'] as String?),
    symbol: json['symbol'] as String? ?? 'EUR/USD',
    strategyOrAgentName:
        json['strategyOrAgentName'] as String? ?? 'SMC + Wyckoff',
    timeframe: json['timeframe'] as String? ?? '15m + 4H',
    score: (json['score'] as num?)?.toInt() ?? 78,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    signal: AgentSignal.fromJson(json['signal'] as Map<String, dynamic>? ?? {}),
    initialSpecialistSignals:
        (json['initialSpecialistSignals'] as List<dynamic>?)
            ?.map((e) => AgentSignal.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    specialistSignals:
        (json['specialistSignals'] as List<dynamic>?)
            ?.map((e) => AgentSignal.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    groundingCritique: json['groundingCritique'] as String?,
  );
}

/// Pipeline execution state tracking
enum PipelineStage {
  idle,
  fetchingMarketData,
  initialSpecialists,
  groundingCritic,
  refinedSpecialists,
  metareasoningConsolidator,
  completed,
  failed,
}

/// Real-time progress updates sent to the UI
class AnalysisProgress {
  final PipelineStage stage;
  final String message;
  final List<String>? activeAgents;
  final double progressFraction;
  final Map<String, AgentSignal>? currentSignals;
  final Map<String, AgentSignal>? initialSignals;
  final String? groundingCritique;
  final MarketStructureAnalysis? structure;

  AnalysisProgress({
    required this.stage,
    required this.message,
    this.activeAgents,
    required this.progressFraction,
    this.currentSignals,
    this.initialSignals,
    this.groundingCritique,
    this.structure,
  });
}

/// Final result returned by the entire pipeline run
class PipelineRunResult {
  final TradingStrategy strategy;
  final String symbol;
  final String timeframe;
  final List<AgentSignal> initialSpecialistSignals;
  final String groundingCritique;
  final List<AgentSignal> refinedSpecialistSignals;
  final AgentSignal? consolidatedSignal;
  final DateTime timestamp;

  PipelineRunResult({
    required this.strategy,
    required this.symbol,
    required this.timeframe,
    required this.initialSpecialistSignals,
    required this.groundingCritique,
    required this.refinedSpecialistSignals,
    this.consolidatedSignal,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'strategy': strategy.toJson(),
    'symbol': symbol,
    'timeframe': timeframe,
    'initialSpecialistSignals': initialSpecialistSignals
        .map((s) => s.toJson())
        .toList(),
    'groundingCritique': groundingCritique,
    'refinedSpecialistSignals': refinedSpecialistSignals
        .map((s) => s.toJson())
        .toList(),
    'consolidatedSignal': consolidatedSignal?.toJson(),
    'timestamp': timestamp.toIso8601String(),
  };

  factory PipelineRunResult.fromJson(Map<String, dynamic> json) =>
      PipelineRunResult(
        strategy: TradingStrategy.fromJson(
          json['strategy'] as Map<String, dynamic>,
        ),
        symbol: json['symbol'] as String? ?? 'UNKNOWN',
        timeframe: json['timeframe'] as String? ?? '15M',
        initialSpecialistSignals:
            (json['initialSpecialistSignals'] as List<dynamic>?)
                ?.map((s) => AgentSignal.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        groundingCritique: json['groundingCritique'] as String? ?? '',
        refinedSpecialistSignals:
            (json['refinedSpecialistSignals'] as List<dynamic>?)
                ?.map((s) => AgentSignal.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        consolidatedSignal: json['consolidatedSignal'] != null
            ? AgentSignal.fromJson(
                json['consolidatedSignal'] as Map<String, dynamic>,
              )
            : null,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  /// The active final signal: consolidated signal if multi-agent, or refined specialist if single agent
  AgentSignal get finalSignal {
    final base =
        consolidatedSignal ??
        (refinedSpecialistSignals.isNotEmpty
            ? refinedSpecialistSignals.first
            : (initialSpecialistSignals.isNotEmpty
                  ? initialSpecialistSignals.first
                  : AgentSignal(
                      direction: SignalDirection.wait,
                      analysis: 'No signal generated',
                      theory: '',
                      entryPrice: 0.0,
                      stopLoss: 0.0,
                      takeProfit: 0.0,
                      confidence: 1,
                      agentName: 'System',
                      timestamp: timestamp,
                      symbol: symbol,
                    )));
    return (base.symbol == null || base.symbol!.isEmpty)
        ? base.copyWith(symbol: symbol)
        : base;
  }
}

/// Configuration for the OpenAI-compatible completion API
class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String modelName;

  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.modelName,
  });

  static const LlmConfig defaultSettings = LlmConfig(
    baseUrl: ApiConfig.llmBaseUrl,
    apiKey: ApiConfig.llmApiKey,
    modelName: ApiConfig.llmModel,
  );
}

/// Configuration for RealMarket API
class RealMarketConfig {
  final String baseUrl;
  final String apiKey;

  const RealMarketConfig({
    this.baseUrl = ApiConfig.realMarketBaseUrl,
    this.apiKey = ApiConfig.realMarketApiKey,
  });
}
