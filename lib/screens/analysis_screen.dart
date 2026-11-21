import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_telemetry.dart';

import '../models/ai_models.dart';
import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/analysis_orchestrator.dart';
import '../services/biquote_service.dart';
import '../services/history_storage.dart';
import '../services/strategy_storage.dart';
import '../widgets/tenx_toast.dart';

class AnalysisScreen extends StatefulWidget {
  final TradingStrategy strategy;
  final String initialSymbol;
  final String initialTimeframe;
  final List<String>? initialTimeframes;
  final AgentSignal? initialSignalResult;
  final List<AgentSignal> initialRoundSpecialistSignals;
  final List<AgentSignal> initialSpecialistSignals;
  final String? initialGroundingCritique;
  final VoidCallback? onNavigateToChart;
  final ValueChanged<String>? onSelectSymbolForChart;
  final ValueChanged<AgentSignal>? onSelectSignalForChart;
  final BiquoteService? biquoteService;
  final AlertManager? alertManager;

  const AnalysisScreen({
    super.key,
    required this.strategy,
    this.initialSymbol = 'EURUSD',
    this.initialTimeframe = '15m',
    this.initialTimeframes,
    this.initialSignalResult,
    this.initialRoundSpecialistSignals = const [],
    this.initialSpecialistSignals = const [],
    this.initialGroundingCritique,
    this.onNavigateToChart,
    this.onSelectSymbolForChart,
    this.onSelectSignalForChart,
    this.biquoteService,
    this.alertManager,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late AnalysisOrchestrator _orchestrator;
  late TradingStrategy _strategy;
  late String _symbol;
  late List<String> _timeframes;

  bool _isRunning = false;
  bool _isCancelled = false;
  AnalysisProgress? _currentProgress;
  PipelineRunResult? _result;
  AgentSignal? _activeSignal;
  List<AgentSignal> _initialRoundSignals = [];
  List<AgentSignal> _specialistSignals = [];
  String? _groundingCritique;
  String? _errorMessage;
  StreamSubscription<AnalysisProgress>? _progressSub;

  int? _expandedSpecialistIndex;
  final Set<int> _expandedDraftIndices = {};
  final Set<String> _expandedLiveSpecialists = {};

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _strategy = widget.strategy;
    _symbol = _formatDisplaySymbol(widget.initialSymbol);

    if (widget.initialTimeframes != null &&
        widget.initialTimeframes!.isNotEmpty) {
      _timeframes = widget.initialTimeframes!;
    } else if (_strategy.timeframes.isNotEmpty) {
      _timeframes = _strategy.timeframes;
    } else {
      _timeframes = [widget.initialTimeframe];
    }

    _initialRoundSignals = List.from(widget.initialRoundSpecialistSignals);
    _specialistSignals = List.from(widget.initialSpecialistSignals);
    _groundingCritique = widget.initialGroundingCritique;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _orchestrator = AnalysisOrchestrator(
      biquoteFallback: widget.biquoteService,
    );

    _progressSub = _orchestrator.progressStream.listen((prog) {
      if (mounted && !_isCancelled) {
        setState(() {
          _currentProgress = prog;
          if (prog.initialSignals != null && prog.initialSignals!.isNotEmpty) {
            _initialRoundSignals = prog.initialSignals!.values.toList();
          }
          if (prog.currentSignals != null && prog.currentSignals!.isNotEmpty) {
            _specialistSignals = prog.currentSignals!.values.toList();
          }
        });
      }
    });

    if (widget.initialSignalResult != null) {
      _activeSignal = widget.initialSignalResult;
      _isRunning = false;
    } else {
      _startAnalysis();
    }
  }

  @override
  void dispose() {
    _isCancelled = true;
    _progressSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDisplaySymbol(String sym) {
    final clean = sym.replaceAll('/', '').trim().toUpperCase();
    if (clean.length == 6) {
      return '${clean.substring(0, 3)}/${clean.substring(3)}';
    }
    return sym;
  }

  String _rawSymbol(String sym) {
    return sym.replaceAll('/', '').trim().toUpperCase();
  }

  void _stopAnalysis() {
    setState(() {
      _isCancelled = true;
      _isRunning = false;
      _errorMessage = 'Analysis stopped by user.';
    });
  }

  Future<void> _startAnalysis() async {
    final startedAt = DateTime.now();
    unawaited(
      AppTelemetry.logAnalysisStarted(
        strategyId: _strategy.id,
        specialistCount: _strategy.specialists.length,
        timeframeCount: _timeframes.length,
      ),
    );
    setState(() {
      _isRunning = true;
      _isCancelled = false;
      _errorMessage = null;
      _activeSignal = null;
      _result = null;
    });

    try {
      final res = await _orchestrator.runPipeline(
        strategy: _strategy,
        symbol: _rawSymbol(_symbol),
        timeframes: _timeframes,
      );

      if (mounted && !_isCancelled) {
        unawaited(
          AppTelemetry.logAnalysisCompleted(
            strategyId: _strategy.id,
            elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
          ),
        );
        setState(() {
          _result = res;
          _activeSignal = res.finalSignal;
          _initialRoundSignals = res.initialSpecialistSignals;
          _specialistSignals = res.refinedSpecialistSignals.isNotEmpty
              ? res.refinedSpecialistSignals
              : res.initialSpecialistSignals;
          _groundingCritique = res.groundingCritique;
          _isRunning = false;
        });
      }
    } catch (e) {
      unawaited(
        AppTelemetry.logAnalysisFailed(
          strategyId: _strategy.id,
          errorCategory: 'pipeline_error',
          stackTrace: StackTrace.current,
        ),
      );
      if (mounted && !_isCancelled) {
        setState(() {
          _isRunning = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _saveSignal() async {
    if (_activeSignal == null) return;
    if (_result != null) {
      await HistoryStorage().saveAnalysis(_result!);
    }
    await StrategyStorage().saveLastChartSignal(_activeSignal);
    if (mounted) {
      TenXToast.show(
        context,
        title: 'Signal Saved',
        subtitle:
            'Saved to Deliberation History · ${_activeSignal?.agentName ?? "Specialist"}',
        icon: Icons.bookmark_added_rounded,
        iconColor: const Color(0xFF43E06A),
        iconBgColor: const Color(0x3330D158),
      );
    }
  }

  void _setAlertsAtLevels() async {
    final sig = _activeSignal;
    if (sig == null || widget.alertManager == null) {
      TenXToast.show(
        context,
        title: 'Cannot Configure Alerts',
        subtitle: 'No active levels found for this signal.',
        icon: Icons.info_outline_rounded,
        iconColor: const Color(0xFFFF9F0A),
        iconBgColor: const Color(0x33FF9F0A),
      );
      return;
    }

    final rawSym = _rawSymbol(_symbol);

    // 1. Entry alert
    if (sig.entryPrice > 0) {
      widget.alertManager!.addAlert(
        symbol: rawSym,
        targetPrice: sig.entryPrice,
        currentPrice: sig.entryPrice,
        condition: sig.direction == SignalDirection.buy
            ? AlertCondition.crossesAbove
            : AlertCondition.crossesBelow,
        note: 'AI Signal: Entry level for ${sig.agentName}',
      );
    }

    // 2. Stop loss alert
    if (sig.stopLoss > 0) {
      widget.alertManager!.addAlert(
        symbol: rawSym,
        targetPrice: sig.stopLoss,
        currentPrice: sig.entryPrice,
        condition: AlertCondition.crossesBelow,
        note: 'AI Signal: Stop Loss protection level',
      );
    }

    // 3. Take profit 1 alert
    if (sig.takeProfit > 0) {
      widget.alertManager!.addAlert(
        symbol: rawSym,
        targetPrice: sig.takeProfit,
        currentPrice: sig.entryPrice,
        condition: AlertCondition.crossesAbove,
        note: 'AI Signal: Take Profit target 1',
      );
    }

    if (mounted) {
      TenXToast.show(
        context,
        title: '3 Alerts Configured',
        subtitle:
            '$rawSym · Entry (${sig.entryPrice}) · SL (${sig.stopLoss}) · TP (${sig.takeProfit})',
        icon: Icons.notifications_active_rounded,
        iconColor: const Color(0xFF0A84FF),
        iconBgColor: const Color(0x330A84FF),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSignal != null && !_isRunning) {
      return _buildSignalView(_activeSignal!);
    }
    return _buildLiveView();
  }

  // =========================================================================
  // 1. LIVE VIEW (Exact replica of Analysis.dc.html + Expandable full cards)
  // =========================================================================
  Widget _buildLiveView() {
    final stage = _currentProgress?.stage ?? PipelineStage.idle;
    final double progress =
        _currentProgress?.progressFraction ?? (_isRunning ? 0.25 : 0.0);
    final struct = _currentProgress?.structure;

    final isIngestionDone =
        stage.index > PipelineStage.fetchingMarketData.index;
    final isRound1Running = stage == PipelineStage.initialSpecialists;
    final isRound1Done = stage.index > PipelineStage.initialSpecialists.index;
    final isCriticRunning = stage == PipelineStage.groundingCritic;
    final isCriticDone = stage.index > PipelineStage.groundingCritic.index;
    final isRefinementRunning = stage == PipelineStage.refinedSpecialists;
    final isRefinementDone =
        stage.index > PipelineStage.refinedSpecialists.index;
    final isConsolidatorRunning =
        stage == PipelineStage.metareasoningConsolidator;
    final isConsolidatorDone = stage == PipelineStage.completed;
    final groundingCriticText =
        _currentProgress?.groundingCritique?.isNotEmpty == true
        ? _currentProgress!.groundingCritique!.trim()
        : (_groundingCritique ?? '').trim();
    final isGroundingExpanded = _expandedLiveSpecialists.contains(
      'grounding_critic',
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Header: "AI Analysis" + Stop button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'AI Analysis',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.03 * 34,
                        color: Colors.white,
                      ),
                    ),
                    if (_isRunning)
                      GestureDetector(
                        onTap: _stopAnalysis,
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x29FF453A),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Center(
                            child: Text(
                              'Stop',
                              style: TextStyle(
                                color: Color(0xFFFF6961),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _startAnalysis,
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0x290A84FF),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Center(
                            child: Text(
                              'Restart',
                              style: TextStyle(
                                color: Color(0xFF4DA3FF),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Chips Row: EUR/USD, 15m, 4H, Strategy Name
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip(_symbol, isBold: true),
                    const SizedBox(width: 6),
                    ..._timeframes.map(
                      (tf) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _chip(tf, isOn: true),
                      ),
                    ),
                    _chip(_strategy.name),
                  ],
                ),
              ),
            ),

            // Error Message Banner (if any)
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x29FF453A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x55FF453A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFF6961),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Stepper Timeline
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  // STAGE 1: Market ingestion
                  _buildTimelineStage(
                    stageNumber: 1,
                    title: '1 · Market ingestion',
                    isDone: isIngestionDone,
                    isRunning: stage == PipelineStage.fetchingMarketData,
                    statusBadge: isIngestionDone
                        ? _badge(
                            'Done',
                            const Color(0x2930D158),
                            const Color(0xFF43E06A),
                          )
                        : (stage == PipelineStage.fetchingMarketData
                              ? _badge(
                                  'Fetching',
                                  const Color(0x290A84FF),
                                  const Color(0xFF4DA3FF),
                                )
                              : _badge(
                                  'Queued',
                                  const Color(0xFF2C2C2E),
                                  const Color(0x9EEBEBF5),
                                )),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isIngestionDone) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _badge(
                                struct != null
                                    ? 'EMA 50 ${struct.ema50 > struct.ema200 ? ">" : "<"} 200'
                                    : 'EMA 50 > 200',
                                const Color(0x2930D158),
                                const Color(0xFF43E06A),
                              ),
                              _badge(
                                struct != null
                                    ? 'ATR ${struct.atr.toStringAsFixed(5)}'
                                    : 'ATR 0.00082',
                                const Color(0xFF2C2C2E),
                                const Color(0x9EEBEBF5),
                                isMonospace: true,
                              ),
                              _badge(
                                struct != null
                                    ? 'BBW ${(struct.bollingerWidth * 100).toStringAsFixed(1)}%'
                                    : 'BBW 0.012',
                                const Color(0xFF2C2C2E),
                                const Color(0x9EEBEBF5),
                                isMonospace: true,
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            _currentProgress?.message ??
                                'Awaiting market data ingestion...',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0x57EBEBF5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // STAGE 2: Specialists Initial Deliberation (Round 1)
                  _buildTimelineStage(
                    stageNumber: 2,
                    title: _strategy.isMultiAgent
                        ? '2 · Specialists · Initial Drafts'
                        : '2 · Specialist · Initial Draft',
                    isDone: isRound1Done,
                    isRunning: isRound1Running,
                    dotColor: const Color(0xFFBF5AF2),
                    statusBadge: isRound1Done
                        ? _badge(
                            'Draft Ready',
                            const Color(0x2930D158),
                            const Color(0xFF43E06A),
                          )
                        : (isRound1Running
                              ? _badge(
                                  'Deliberating',
                                  const Color(0x2EBF5AF2),
                                  const Color(0xFFD58CF7),
                                )
                              : _badge(
                                  'Queued',
                                  const Color(0xFF2C2C2E),
                                  const Color(0x9EEBEBF5),
                                )),
                    content: Column(
                      children: _strategy.specialists.map((spec) {
                        return _buildSpecialistLiveCard(
                          spec,
                          isRunning: isRound1Running,
                          isDone: isRound1Done,
                          isRefined: false,
                        );
                      }).toList(),
                    ),
                  ),

                  // STAGE 3: Adversarial Grounding Critic Audit
                  _buildTimelineStage(
                    stageNumber: 3,
                    title: '3 · Grounding Critic Audit',
                    isDone: isCriticDone,
                    isRunning: isCriticRunning,
                    dotColor: const Color(0xFF64D2FF),
                    statusBadge: isCriticDone
                        ? _badge(
                            'Audited',
                            const Color(0x2930D158),
                            const Color(0xFF43E06A),
                          )
                        : (isCriticRunning
                              ? _badge(
                                  'Auditing OHLC',
                                  const Color(0x2964D2FF),
                                  const Color(0xFF64D2FF),
                                )
                              : _badge(
                                  'Queued',
                                  const Color(0xFF2C2C2E),
                                  const Color(0x9EEBEBF5),
                                )),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Adversarially audits price levels and structural claims against 100 historical bars.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0x57EBEBF5),
                          ),
                        ),
                        if ((_currentProgress?.groundingCritique != null &&
                                _currentProgress!
                                    .groundingCritique!
                                    .isNotEmpty) ||
                            (_groundingCritique != null &&
                                _groundingCritique!.isNotEmpty)) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0x3364D2FF),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isGroundingExpanded ||
                                          groundingCriticText.length <= 140
                                      ? groundingCriticText
                                      : '${groundingCriticText.substring(0, 137)}...',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xE0FFFFFF),
                                    height: 1.4,
                                  ),
                                ),
                                if (groundingCriticText.length > 140) ...[
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (isGroundingExpanded) {
                                        _expandedLiveSpecialists.remove(
                                          'grounding_critic',
                                        );
                                      } else {
                                        _expandedLiveSpecialists.add(
                                          'grounding_critic',
                                        );
                                      }
                                    }),
                                    child: Text(
                                      isGroundingExpanded
                                          ? 'See less'
                                          : 'See more',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF4DA3FF),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // STAGE 4: Specialist Refinement Loop (Round 2)
                  _buildTimelineStage(
                    stageNumber: 4,
                    title: _strategy.isMultiAgent
                        ? '4 · Specialists · Refinement'
                        : '4 · Specialist · Refinement',
                    isDone: isRefinementDone,
                    isRunning: isRefinementRunning,
                    dotColor: const Color(0xFFFFD60A),
                    statusBadge: isRefinementDone
                        ? _badge(
                            'Refined',
                            const Color(0x2930D158),
                            const Color(0xFF43E06A),
                          )
                        : (isRefinementRunning
                              ? _badge(
                                  'Refining Setups',
                                  const Color(0x33FFD60A),
                                  const Color(0xFFFFD60A),
                                )
                              : _badge(
                                  'Queued',
                                  const Color(0xFF2C2C2E),
                                  const Color(0x9EEBEBF5),
                                )),
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isRefinementRunning && !isRefinementDone)
                          const Text(
                            'Specialists will calibrate their parameters based on Grounding Critic audit.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0x57EBEBF5),
                            ),
                          )
                        else
                          Column(
                            children: _strategy.specialists.map((spec) {
                              return _buildSpecialistLiveCard(
                                spec,
                                isRunning: isRefinementRunning,
                                isDone: isRefinementDone,
                                isRefined: true,
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),

                  // STAGE 5: Consolidator officer / Final Execution Plan
                  _buildTimelineStage(
                    stageNumber: 5,
                    title: _strategy.isMultiAgent
                        ? '5 · Consolidator Officer'
                        : '5 · Final Execution Setup',
                    isDone: isConsolidatorDone,
                    isRunning: isConsolidatorRunning,
                    isLast: true,
                    dotColor: const Color(0xFF30D158),
                    statusBadge: isConsolidatorDone
                        ? _badge(
                            'Ready',
                            const Color(0x2930D158),
                            const Color(0xFF43E06A),
                          )
                        : (isConsolidatorRunning
                              ? _badge(
                                  'Synthesizing',
                                  const Color(0x2EBF5AF2),
                                  const Color(0xFFD58CF7),
                                )
                              : _badge(
                                  'Queued',
                                  const Color(0xFF2C2C2E),
                                  const Color(0x9EEBEBF5),
                                )),
                    content: Text(
                      _strategy.isMultiAgent
                          ? 'Synthesizing refined specialist setups into unified consensus execution plan.'
                          : 'Validating refined risk-reward metrics and compiling trade alert levels.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0x57EBEBF5),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Progress Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: constraints.maxWidth * progress.clamp(0.05, 1.0),
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFBF5AF2), Color(0xFF0A84FF)],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialistLiveCard(
    SpecialistAgentConfig spec, {
    required bool isRunning,
    required bool isDone,
    bool isRefined = false,
  }) {
    AgentSignal? signal;
    if (isRefined) {
      signal =
          _currentProgress?.currentSignals?[spec.id] ??
          _specialistSignals.cast<AgentSignal?>().firstWhere(
            (s) => s?.agentName == spec.name,
            orElse: () => null,
          );
    } else {
      signal =
          _currentProgress?.initialSignals?[spec.id] ??
          _initialRoundSignals.cast<AgentSignal?>().firstWhere(
            (s) => s?.agentName == spec.name,
            orElse: () => null,
          );
      if (signal == null && !isDone && !isRefined) {
        signal = _currentProgress?.currentSignals?[spec.id];
      }
    }

    final color = Color(int.parse('0xFF${spec.colorHex.replaceAll('#', '')}'));
    final isExpanded = _expandedLiveSpecialists.contains(
      '${spec.id}_${isRefined ? "ref" : "init"}',
    );

    String displayText = '';
    if (signal != null && signal.analysis.isNotEmpty) {
      displayText = signal.analysis;
    } else if (isRunning) {
      displayText = isRefined
          ? 'Refining setup and resolving Grounding Critic audit feedback...'
          : 'Analyzing order structure, liquidity levels, and market momentum...';
    } else {
      displayText = isRefined
          ? 'Awaiting Grounding Critic audit output...'
          : 'Standing by for candlestick ingestion...';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    spec.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (signal != null)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      final key = '${spec.id}_${isRefined ? "ref" : "init"}';
                      if (isExpanded) {
                        _expandedLiveSpecialists.remove(key);
                      } else {
                        _expandedLiveSpecialists.add(key);
                      }
                    });
                  },
                  child: _badge(
                    isRefined
                        ? (isExpanded
                              ? 'Refined · ${signal.confidenceScore}'
                              : 'Refined · ${signal.confidenceScore}')
                        : (isExpanded
                              ? 'Draft · ${signal.confidenceScore}'
                              : 'Draft · ${signal.confidenceScore}'),
                    isRefined
                        ? const Color(0x33FFD60A)
                        : const Color(0x2930D158),
                    isRefined
                        ? const Color(0xFFFFD60A)
                        : const Color(0xFF43E06A),
                  ),
                )
              else if (isRunning)
                Text(
                  '${(spec.creativity * 100).toInt()}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0x9EEBEBF5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Streamed text with purple typing cursor
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13,
                color: Color(0x9EEBEBF5),
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: (!isExpanded && displayText.length > 140)
                      ? '${displayText.substring(0, 137)}...'
                      : displayText,
                ),
                if (isRunning && signal == null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: FadeTransition(
                      opacity: _pulseController,
                      child: Container(
                        margin: const EdgeInsets.only(left: 3),
                        width: 2,
                        height: 13,
                        color: const Color(0xFFD58CF7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (displayText.length > 140 && signal != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                setState(() {
                  final key = '${spec.id}_${isRefined ? "ref" : "init"}';
                  if (isExpanded) {
                    _expandedLiveSpecialists.remove(key);
                  } else {
                    _expandedLiveSpecialists.add(key);
                  }
                });
              },
              child: Text(
                isExpanded ? 'Show less' : 'Show full output',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4DA3FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineStage({
    required int stageNumber,
    required String title,
    required bool isDone,
    required bool isRunning,
    required Widget statusBadge,
    required Widget content,
    Color dotColor = const Color(0xFF30D158),
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot and Connecting Line
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? dotColor : Colors.transparent,
                  border: isDone
                      ? null
                      : Border.all(
                          color: isRunning ? dotColor : const Color(0xFF3A3A3C),
                          width: 2,
                        ),
                  boxShadow: isRunning
                      ? [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.25),
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 15, color: Colors.black)
                      : (isRunning
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFF3A3A3C),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDone || isRunning
                              ? Colors.white
                              : const Color(0x9EEBEBF5),
                        ),
                      ),
                      statusBadge,
                    ],
                  ),
                  const SizedBox(height: 6),
                  content,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. SIGNAL VIEW (Signal.dc.html + Consolidator Intent + Full Specialists)
  // =========================================================================
  Widget _buildSignalView(AgentSignal signal) {
    final isBuy = signal.direction == SignalDirection.buy;
    final isSell = signal.direction == SignalDirection.sell;
    final signalColor = isBuy
        ? const Color(0xFF43E06A)
        : (isSell ? const Color(0xFFFF6961) : const Color(0xFFE0E0E0));

    final glowColor = isBuy
        ? const Color(0x3830D158)
        : (isSell ? const Color(0x38FF453A) : Colors.transparent);

    final score = signal.confidenceScore;
    final rrStr = signal.riskRewardRatio > 0
        ? 'Risk : Reward 1 : ${signal.riskRewardRatio.toStringAsFixed(1)}'
        : 'Risk : Reward 1 : 2.0';

    final tp1 = signal.takeProfit;
    final tp2 =
        signal.takeProfit2 ??
        (isBuy
            ? signal.entryPrice + (tp1 - signal.entryPrice) * 1.55
            : signal.entryPrice - (signal.entryPrice - tp1) * 1.55);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Top ambient radial glow
          Positioned(
            left: -60,
            right: -60,
            top: -140,
            height: 420,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.8,
                  colors: [glowColor, Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            top: true,
            bottom: true,
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Header: Back button + EUR/USD · 15m + 4H + Strategy pill
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xAA2C2C2E),
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: const Icon(
                                  Icons.chevron_left_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '$_symbol · ${_timeframes.join(" + ")}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        _badge(
                          _strategy.name,
                          const Color(0x2EBF5AF2),
                          const Color(0xFFD58CF7),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Main Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                    children: [
                      // HERO CARD: Confidence Radial Gauge + SIGNAL BUY
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            // 104x104 Radial Conic Gauge
                            CustomPaint(
                              size: const Size(104, 104),
                              painter: _RadialGaugePainter(
                                score: score,
                                activeColor: signalColor,
                              ),
                              child: SizedBox(
                                width: 104,
                                height: 104,
                                child: Center(
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1C1C1E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          score.toString(),
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 30,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.04 * 30,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const Text(
                                          'CONFIDENCE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.0,
                                            color: Color(0x9EEBEBF5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),

                            // Signal Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SIGNAL',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                      color: Color(0x9EEBEBF5),
                                    ),
                                  ),
                                  Text(
                                    signal.direction.label,
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.04 * 44,
                                      color: signalColor,
                                      height: 1.05,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    rrStr,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: Color(0x9EEBEBF5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // LEVELS CARD: Entry, Stop loss, Take profit 1, Take profit 2
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            _buildLevelRow(
                              dotColor: const Color(0xFF0A84FF),
                              label: 'Entry',
                              price: signal.entryPrice.toStringAsFixed(5),
                            ),
                            const Divider(color: Color(0x17FFFFFF), height: 1),
                            _buildLevelRow(
                              dotColor: const Color(0xFFFF453A),
                              label: 'Stop loss',
                              price: signal.stopLoss.toStringAsFixed(5),
                              priceColor: const Color(0xFFFF6961),
                              pipDelta: signal.formattedPipDelta(
                                signal.stopLoss,
                              ),
                            ),
                            const Divider(color: Color(0x17FFFFFF), height: 1),
                            _buildLevelRow(
                              dotColor: const Color(0xFF30D158),
                              label: 'Take profit 1',
                              price: tp1.toStringAsFixed(5),
                              priceColor: const Color(0xFF43E06A),
                              pipDelta: signal.formattedPipDelta(tp1),
                            ),
                            const Divider(color: Color(0x17FFFFFF), height: 1),
                            _buildLevelRow(
                              dotColor: const Color(0x8030D158),
                              label: 'Take profit 2',
                              price: tp2.toStringAsFixed(5),
                              priceColor: const Color(0xFF43E06A),
                              pipDelta: signal.formattedPipDelta(tp2),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // HERO INTENT & REFINED ANALYSIS CARD
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _strategy.isMultiAgent
                                ? const Color(0x33BF5AF2)
                                : const Color(0x3330D158),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _strategy.isMultiAgent
                                      ? Icons.psychology_rounded
                                      : Icons.auto_awesome_rounded,
                                  color: _strategy.isMultiAgent
                                      ? const Color(0xFFD58CF7)
                                      : const Color(0xFF43E06A),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _strategy.isMultiAgent
                                        ? 'Consolidator Intent & Synthesis'
                                        : '${signal.agentName} · Refined Analysis & Intent',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                _badge(
                                  _strategy.isMultiAgent
                                      ? 'Consensus'
                                      : 'Refined · Round 2',
                                  _strategy.isMultiAgent
                                      ? const Color(0x2EBF5AF2)
                                      : const Color(0x2930D158),
                                  _strategy.isMultiAgent
                                      ? const Color(0xFFD58CF7)
                                      : const Color(0xFF43E06A),
                                ),
                              ],
                            ),
                            if (signal.theory.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  signal.theory,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD58CF7),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              signal.analysis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xEBEBF5EE),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // SPECIALIST SCORE BREAKDOWN — dynamic from actual specialist signals
                      if (_specialistSignals.isNotEmpty) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ..._specialistSignals.asMap().entries.map((
                                entry,
                              ) {
                                final idx = entry.key;
                                final specSig = entry.value;
                                final colors = [
                                  const Color(0xFFBF5AF2),
                                  const Color(0xFFFFD60A),
                                  const Color(0xFF30D158),
                                  const Color(0xFF64D2FF),
                                  const Color(0xFFFF9F0A),
                                  const Color(0xFFFF6961),
                                ];
                                final dotColor = colors[idx % colors.length];
                                final shortName = specSig.agentName.length > 12
                                    ? '${specSig.agentName.substring(0, 10).trim()}…'
                                    : specSig.agentName;
                                final dirColor =
                                    specSig.direction == SignalDirection.buy
                                    ? const Color(0xFF43E06A)
                                    : (specSig.direction == SignalDirection.sell
                                          ? const Color(0xFFFF6961)
                                          : const Color(0x9EEBEBF5));
                                return Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: SizedBox(
                                    width: 110,
                                    child: _buildBreakdownCard(
                                      title: shortName,
                                      dotColor: dotColor,
                                      score:
                                          '${specSig.direction.label} ${specSig.confidenceScore}',
                                      scoreColor: dirColor,
                                      scoreFontSize: 14,
                                    ),
                                  ),
                                );
                              }),
                              // Critic card
                              SizedBox(
                                width: 110,
                                child: _buildBreakdownCard(
                                  title: 'Grounding',
                                  dotColor: const Color(0xFF64D2FF),
                                  score: signal.criticPenalty < 0
                                      ? '−${signal.criticPenalty.abs()}pts'
                                      : signal.groundingVerification,
                                  scoreColor: const Color(0xFFFFB340),
                                  scoreFontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Fallback 3-card static breakdown using specialistScores map
                        if (signal.specialistScores.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ...signal.specialistScores.entries.map((e) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: SizedBox(
                                      width: 110,
                                      child: _buildBreakdownCard(
                                        title: e.key,
                                        dotColor: const Color(0xFFBF5AF2),
                                        score: e.value.toString(),
                                      ),
                                    ),
                                  );
                                }),
                                SizedBox(
                                  width: 110,
                                  child: _buildBreakdownCard(
                                    title: 'Grounding',
                                    dotColor: const Color(0xFF64D2FF),
                                    score: signal.criticPenalty < 0
                                        ? '−${signal.criticPenalty.abs()}pts'
                                        : '-4pts',
                                    scoreColor: const Color(0xFFFFB340),
                                    scoreFontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 10),

                      // REFINED SPECIALIST DELIBERATIONS (ROUND 2)
                      if (_specialistSignals.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.assignment_turned_in_rounded,
                                size: 16,
                                color: Color(0xFFFFD60A),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'REFINED SPECIALIST DELIBERATIONS (${_specialistSignals.length})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.99,
                                  color: Color(0xFFFFD60A),
                                ),
                              ),
                              const Spacer(),
                              _badge(
                                'Grounded & Refined',
                                const Color(0x33FFD60A),
                                const Color(0xFFFFD60A),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...List.generate(_specialistSignals.length, (idx) {
                          final specSig = _specialistSignals[idx];
                          final isExpanded = _expandedSpecialistIndex == idx;
                          final isSpecBuy =
                              specSig.direction == SignalDirection.buy;
                          final isSpecSell =
                              specSig.direction == SignalDirection.sell;
                          final dirColor = isSpecBuy
                              ? const Color(0xFF43E06A)
                              : (isSpecSell
                                    ? const Color(0xFFFF6961)
                                    : const Color(0x9EEBEBF5));

                          // Look up corresponding initial draft if present
                          final initSig = _initialRoundSignals
                              .cast<AgentSignal?>()
                              .firstWhere(
                                (s) => s?.agentName == specSig.agentName,
                                orElse: () => null,
                              );

                          final isDraftExpanded = _expandedDraftIndices
                              .contains(idx);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0x22FFD60A),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(
                                              specSig.agentName,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            _badge(
                                              'Refined',
                                              const Color(0x33FFD60A),
                                              const Color(0xFFFFD60A),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _badge(
                                        '${specSig.direction.label} · ${specSig.confidenceScore}',
                                        dirColor.withValues(alpha: 0.18),
                                        dirColor,
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _expandedSpecialistIndex =
                                                isExpanded ? null : idx;
                                          });
                                        },
                                        child: Icon(
                                          isExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                    .keyboard_arrow_down_rounded,
                                          color: const Color(0x9EEBEBF5),
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isExpanded
                                        ? specSig.analysis
                                        : (specSig.analysis.length > 120
                                              ? '${specSig.analysis.substring(0, 117)}...'
                                              : specSig.analysis),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0x9EEBEBF5),
                                      height: 1.4,
                                    ),
                                  ),
                                  if (isExpanded) ...[
                                    const SizedBox(height: 10),
                                    if (specSig.theory.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2C2C2E),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          'Theory: ${specSig.theory}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64D2FF),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Entry: ${specSig.entryPrice.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          'SL: ${specSig.stopLoss.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: Color(0xFFFF6961),
                                          ),
                                        ),
                                        Text(
                                          'TP: ${specSig.takeProfit.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            color: Color(0xFF43E06A),
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Side-by-side or collapsible comparison with Round 1 Draft
                                    if (initSig != null) ...[
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (isDraftExpanded) {
                                              _expandedDraftIndices.remove(idx);
                                            } else {
                                              _expandedDraftIndices.add(idx);
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2C2C2E),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isDraftExpanded
                                                    ? Icons
                                                          .arrow_drop_up_rounded
                                                    : Icons
                                                          .arrow_drop_down_rounded,
                                                color: const Color(0xFF64D2FF),
                                                size: 18,
                                              ),
                                              Text(
                                                isDraftExpanded
                                                    ? 'Hide Pre-Grounding Draft'
                                                    : 'Compare Initial Draft (Pre-Grounding)',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF64D2FF),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (isDraftExpanded) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF141416),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(0x2264D2FF),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  const Text(
                                                    'ROUND 1 DRAFT (PRE-GROUNDING)',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: 0.8,
                                                      color: Color(0x80EBEBF5),
                                                    ),
                                                  ),
                                                  _badge(
                                                    '${initSig.direction.label} · ${initSig.confidenceScore}',
                                                    const Color(0x1FFFFFFF),
                                                    const Color(0x9EEBEBF5),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                initSig.analysis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0x80EBEBF5),
                                                  height: 1.35,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    'Entry: ${initSig.entryPrice.toStringAsFixed(5)}',
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 11,
                                                      color: Color(0x80EBEBF5),
                                                    ),
                                                  ),
                                                  Text(
                                                    'SL: ${initSig.stopLoss.toStringAsFixed(5)}',
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 11,
                                                      color: Color(0x80FF6961),
                                                    ),
                                                  ),
                                                  Text(
                                                    'TP: ${initSig.takeProfit.toStringAsFixed(5)}',
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 11,
                                                      color: Color(0x8043E06A),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                      ],
                      // Action Buttons Row: Save + Set alerts at levels
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _saveSignal,
                            child: Container(
                              height: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Center(
                                child: Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _setAlertsAtLevels,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A84FF),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.notifications_none_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Set alerts at levels',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelRow({
    required Color dotColor,
    required String label,
    required String price,
    Color? priceColor,
    String? pipDelta,
  }) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Colors.white),
            ),
          ),
          Text(
            price,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: priceColor ?? Colors.white,
            ),
          ),
          if (pipDelta != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: Text(
                pipDelta,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0x9EEBEBF5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownCard({
    required String title,
    required Color dotColor,
    required String score,
    Color scoreColor = Colors.white,
    double scoreFontSize = 22,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0x9EEBEBF5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            score,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: scoreFontSize,
              fontWeight: FontWeight.w600,
              color: scoreColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {bool isOn = false, bool isBold = false}) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isOn ? const Color(0x38BF5AF2) : const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold || isOn ? FontWeight.w600 : FontWeight.normal,
            color: isOn ? const Color(0xFFD58CF7) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg, {bool isMonospace = false}) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: isMonospace ? 'monospace' : null,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the conic confidence gauge ring matching Signal.dc.html
class _RadialGaugePainter extends CustomPainter {
  final int score;
  final Color activeColor;

  _RadialGaugePainter({required this.score, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle track
    final bgPaint = Paint()
      ..color = const Color(0xFF2C2C2E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Active conic progress wedge
    final progressPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final sweepAngle = (score.clamp(0, 100) / 100.0) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      true,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadialGaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.activeColor != activeColor;
  }
}
