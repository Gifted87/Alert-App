import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/ai_models.dart';
import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/history_storage.dart';
import '../services/strategy_storage.dart';
import '../theme/app_theme.dart';
import 'analysis_screen.dart';
import 'create_alert_sheet.dart';

const _s1 = Color(0xFF1C1C1E);
const _s2 = Color(0xFF2C2C2E);
const _s3 = Color(0xFF3A3A3C);
const _t2 = Color(0x9DEBEBF5);
const _bl = Color(0xFF0A84FF);
const _up = Color(0xFF30D158);

class HistoryScreen extends StatefulWidget {
  final VoidCallback? onNavigateToChart;
  final ValueChanged<String>? onSelectSymbolForChart;
  final ValueChanged<AgentSignal>? onSelectSignalForChart;
  final AlertManager? alertManager;
  final BiquoteService? biquoteService;
  final String initialAlertSymbol;
  final double initialAlertPrice;
  final int initialAlertPrecision;

  const HistoryScreen({
    super.key,
    this.onNavigateToChart,
    this.onSelectSymbolForChart,
    this.onSelectSignalForChart,
    this.alertManager,
    this.biquoteService,
    this.initialAlertSymbol = 'EURUSD',
    this.initialAlertPrice = 0,
    this.initialAlertPrecision = 5,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final _historyStorage = HistoryStorage();
  final _strategyStorage = StrategyStorage();
  List<PipelineRunResult>? _history;
  late final TabController _tabController;
  String _activeFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
    widget.alertManager?.addListener(_onChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    widget.alertManager?.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final h = await _historyStorage.getHistory();
    if (mounted) setState(() => _history = h);
  }

  void _clearHistory() async {
    await _historyStorage.clearHistory();
    _loadHistory();
  }

  void _navigateToChart(String symbol, [AgentSignal? signal]) async {
    if (signal != null) {
      await _strategyStorage.saveLastChartSignal(signal);
      if (widget.onSelectSignalForChart != null) {
        widget.onSelectSignalForChart!(signal);
        return;
      }
    }
    if (widget.onSelectSymbolForChart != null) {
      widget.onSelectSymbolForChart!(symbol);
    } else {
      widget.onNavigateToChart?.call();
    }
  }

  void _reRunStrategy(PipelineRunResult item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          strategy: item.strategy,
          initialSymbol: item.symbol,
          initialTimeframe: item.timeframe,
          onNavigateToChart: widget.onNavigateToChart,
          onSelectSymbolForChart: widget.onSelectSymbolForChart,
          onSelectSignalForChart: widget.onSelectSignalForChart,
          biquoteService: widget.biquoteService,
          alertManager: widget.alertManager,
        ),
      ),
    );
  }

  void _openCreateAlert(
    String symbol,
    double targetPrice, {
    String note = '',
    AlertCondition condition = AlertCondition.crossesAbove,
  }) {
    if (widget.alertManager == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateAlertSheet(
        symbol: symbol,
        currentPrice: widget.biquoteService?.livePriceFor(symbol) ?? 0,
        biquoteService: widget.biquoteService,
        initialTargetPrice: targetPrice > 0 ? targetPrice : null,
        initialCondition: condition,
        initialNote: note,
        precision: targetPrice > 100 ? 2 : 4,
        alarmService: widget.alertManager!.alarmService,
        onAlertCreated: _buildHandler(),
      ),
    );
  }

  void _openNewAlertSheet() {
    if (widget.alertManager == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateAlertSheet(
        symbol: widget.initialAlertSymbol,
        currentPrice:
            widget.biquoteService?.livePriceFor(widget.initialAlertSymbol) ??
            widget.initialAlertPrice,
        precision: widget.initialAlertPrecision,
        biquoteService: widget.biquoteService,
        alarmService: widget.alertManager!.alarmService,
        onAlertCreated: _buildHandler(),
      ),
    );
  }

  // Builds the onAlertCreated callback — identical logic to original
  dynamic Function({
    required String symbol,
    AlertType alertType,
    double targetPrice,
    AlertCondition condition,
    CandlestickPattern? candlestickPattern,
    IndicatorAlertConfig? indicatorConfig,
    MultiStepConfig? multiStepConfig,
    String timeframe,
    String note,
    String ringtoneTitle,
    String? ringtoneUri,
    String? drawingId,
    List<String>? targetSymbols,
    bool? triggerOnCandleClose,
    int? cooldownMinutes,
    DateTime? scheduledTime,
  })
  _buildHandler() {
    return ({
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
      DateTime? scheduledTime,
    }) async {
      double currentPrice =
          widget.biquoteService?.livePriceFor(symbol) ??
          (symbol == widget.initialAlertSymbol ? widget.initialAlertPrice : 0);
      Map<String, double>? latestPrices;
      try {
        if (targetSymbols != null && targetSymbols.length > 1) {
          final quotes = await widget.biquoteService?.getLatestQuotes(
            targetSymbols,
          );
          latestPrices = quotes?.map((key, value) => MapEntry(key, value.mid));
          currentPrice = latestPrices?[symbol] ?? currentPrice;
        } else {
          final quote = await widget.biquoteService?.getSingleQuote(symbol);
          if (quote != null) currentPrice = quote.mid;
        }
      } catch (_) {}
      if (!mounted) return;
      if (targetSymbols != null && targetSymbols.length > 1) {
        widget.alertManager!.createMultiSymbolAlerts(
          symbols: targetSymbols,
          alertType: alertType,
          targetPrice: targetPrice,
          condition: condition,
          candlestickPattern: candlestickPattern,
          indicatorConfig: indicatorConfig,
          multiStepConfig: multiStepConfig,
          timeframe: timeframe,
          note: note,
          currentPrice: currentPrice,
          symbolPrices: latestPrices,
          ringtoneTitle: ringtoneTitle,
          ringtoneUri: ringtoneUri,
          drawingId: drawingId,
          triggerOnCandleClose: triggerOnCandleClose ?? true,
          cooldownMinutes: cooldownMinutes ?? 0,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Strategy deployed to ${targetSymbols.length} pairs'),
          ),
        );
      } else {
        widget.alertManager!.addAlert(
          symbol: symbol,
          alertType: alertType,
          targetPrice: targetPrice,
          condition: condition,
          candlestickPattern: candlestickPattern,
          indicatorConfig: indicatorConfig,
          multiStepConfig: multiStepConfig,
          timeframe: timeframe,
          note: note,
          currentPrice: currentPrice,
          ringtoneTitle: ringtoneTitle,
          ringtoneUri: ringtoneUri,
          drawingId: drawingId,
          triggerOnCandleClose: triggerOnCandleClose ?? true,
          cooldownMinutes: cooldownMinutes ?? 0,
          targetSymbols: targetSymbols,
          scheduledTime: scheduledTime,
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Created alert for $symbol')));
      }
    };
  }

  void _buildLogicChain(PipelineRunResult item) {
    if (widget.alertManager == null) return;
    final sig = item.finalSignal;
    if (sig.entryPrice <= 0) return;
    final isBuy = sig.direction == SignalDirection.buy;
    final cond = isBuy
        ? AlertCondition.crossesAbove
        : AlertCondition.crossesBelow;
    final stages = [
      ChainStage(
        id: 'stage_${DateTime.now().millisecondsSinceEpoch}_1',
        name: 'Stage 1: ${item.symbol} Entry Level',
        nodes: [
          ChainNode(
            id: 'node_${DateTime.now().millisecondsSinceEpoch}_entry',
            nodeType: AlertType.priceLevel,
            operatorToPrevious: 'AND',
            timeframe: item.timeframe,
            targetPrice: sig.entryPrice,
            condition: cond,
          ),
        ],
      ),
      if (sig.takeProfit > 0)
        ChainStage(
          id: 'stage_${DateTime.now().millisecondsSinceEpoch}_2',
          name: 'Stage 2: ${item.symbol} Take Profit',
          nodes: [
            ChainNode(
              id: 'node_${DateTime.now().millisecondsSinceEpoch}_tp',
              nodeType: AlertType.priceLevel,
              operatorToPrevious: 'AND',
              timeframe: item.timeframe,
              targetPrice: sig.takeProfit,
              condition: cond,
            ),
          ],
        ),
    ];
    widget.alertManager!.addAlert(
      symbol: item.symbol,
      alertType: AlertType.multiStepChain,
      targetPrice: sig.entryPrice,
      condition: cond,
      multiStepConfig: MultiStepConfig(stages: stages),
      timeframe: item.timeframe,
      note:
          'AI Logic Chain for ${item.strategy.name} (${sig.direction.name.toUpperCase()})',
      currentPrice: sig.entryPrice,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Built 2-Stage Logic Chain Alert!'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final am = widget.alertManager;
    final activeCount = am?.activeAlerts.length ?? 0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Alerts',
                    style: AppTheme.sans(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0,
                      color: Colors.white,
                    ),
                  ),
                  _tabController.index == 1
                      ? GestureDetector(
                          onTap: () => _showClearDialog(context),
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _s2,
                              borderRadius: BorderRadius.circular(17),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Clear',
                              style: AppTheme.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFFF6961),
                              ),
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            _IconBtn(
                              onTap: () {},
                              child: CustomPaint(
                                size: const Size(22, 22),
                                painter: _FilterIconPainter(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _openNewAlertSheet,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: _bl,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
            // ── Segmented control ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _SegmentedControl(
                labels: ['Active · $activeCount', 'History'],
                selectedIndex: _tabController.index,
                onChanged: (i) {
                  _tabController.animateTo(i);
                  setState(() {});
                },
              ),
            ),
            // ── Body ─────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildActiveTab(am), _buildHistoryTab(am)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Active tab ──────────────────────────────────────────────────────────
  Widget _buildActiveTab(AlertManager? am) {
    final alerts = am?.alerts ?? [];
    final filtered = _filterAlerts(alerts);
    return Column(
      children: [
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              for (final lbl in [
                'All',
                'Price',
                'Pattern',
                'Indicator',
                'Chains',
                'Scheduled',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: lbl,
                    selected: _activeFilter == lbl,
                    onTap: () => setState(() => _activeFilter = lbl),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState(
                  icon: Icons.notifications_none_rounded,
                  message: 'No alerts set',
                  sub: 'Tap + to create your first alert',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) =>
                      _buildAlertCard(ctx, filtered[i], am!),
                ),
        ),
      ],
    );
  }

  List<PriceAlert> _filterAlerts(List<PriceAlert> alerts) {
    switch (_activeFilter) {
      case 'Price':
        return alerts
            .where(
              (a) =>
                  !a.isPatternAlert &&
                  !a.isIndicatorAlert &&
                  !a.isMultiStepAlert &&
                  !a.isTimeScheduleAlert,
            )
            .toList();
      case 'Pattern':
        return alerts.where((a) => a.isPatternAlert).toList();
      case 'Indicator':
        return alerts.where((a) => a.isIndicatorAlert).toList();
      case 'Chains':
        return alerts.where((a) => a.isMultiStepAlert).toList();
      case 'Scheduled':
        return alerts.where((a) => a.isTimeScheduleAlert).toList();
      default:
        return alerts;
    }
  }

  void _showAlertActions(BuildContext ctx, PriceAlert alert, AlertManager am) {
    final dp = alert.symbol.length == 6
        ? '${alert.symbol.substring(0, 3)}/${alert.symbol.substring(3)}'
        : alert.symbol;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x40EBEBF5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                dp,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0x9DEBEBF5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ActionItem(
              icon: alert.isActive
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
              label: alert.isActive ? 'Pause Alert' : 'Resume Alert',
              color: const Color(0xFF0A84FF),
              onTap: () {
                Navigator.pop(ctx);
                am.toggleAlert(alert.id);
              },
            ),
            _ActionItem(
              icon: Icons.edit_outlined,
              label: 'Edit Alert',
              color: const Color(0xFFFFB340),
              onTap: () {
                Navigator.pop(ctx);
                _openEditAlert(alert);
              },
            ),
            _ActionItem(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Alert',
              color: const Color(0xFFFF453A),
              onTap: () {
                Navigator.pop(ctx);
                am.deleteAlert(alert.id);
              },
            ),
            _ActionItem(
              icon: Icons.close_rounded,
              label: 'Cancel',
              color: const Color(0x9DEBEBF5),
              onTap: () => Navigator.pop(ctx),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  void _openEditAlert(PriceAlert alert) {
    if (widget.alertManager == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateAlertSheet(
        symbol: alert.symbol,
        currentPrice: widget.biquoteService?.livePriceFor(alert.symbol) ?? 0,
        biquoteService: widget.biquoteService,
        initialTargetPrice: alert.targetPrice > 0 ? alert.targetPrice : null,
        initialCondition: alert.condition,
        initialAlertType: alert.alertType,
        initialIndicatorConfig: alert.indicatorConfig,
        initialNote: alert.note,
        precision: alert.targetPrice > 100 ? 2 : 4,
        alarmService: widget.alertManager!.alarmService,
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
              DateTime? scheduledTime,
            }) {
              widget.alertManager!.deleteAlert(alert.id);
              _buildHandler()(
                symbol: symbol,
                alertType: alertType,
                targetPrice: targetPrice,
                condition: condition,
                candlestickPattern: candlestickPattern,
                indicatorConfig: indicatorConfig,
                multiStepConfig: multiStepConfig,
                timeframe: timeframe,
                note: note,
                ringtoneTitle: ringtoneTitle,
                ringtoneUri: ringtoneUri,
                drawingId: drawingId,
                targetSymbols: targetSymbols,
                triggerOnCandleClose: triggerOnCandleClose,
                cooldownMinutes: cooldownMinutes,
                scheduledTime: scheduledTime,
              );
            },
      ),
    );
  }

  Widget _buildAlertCard(
    BuildContext context,
    PriceAlert alert,
    AlertManager am,
  ) {
    final isChain = alert.isMultiStepAlert;
    final isPattern = alert.isPatternAlert;
    final isIndicator = alert.isIndicatorAlert;
    final isDrawing = alert.isDrawingAlert;
    final isScheduled = alert.isTimeScheduleAlert;

    final Color tileColor;
    final Color tileText;
    final Widget tileIcon;

    if (isScheduled) {
      tileColor = const Color(0x28FFB340);
      tileText = const Color(0xFFFFB340);
      tileIcon = Icon(Icons.calendar_month_rounded, color: tileText, size: 22);
    } else if (isChain) {
      tileColor = const Color(0x2DBF5AF2);
      tileText = const Color(0xFFD58CF7);
      tileIcon = _ChainIcon(color: tileText);
    } else if (isPattern) {
      final isBull = alert.candlestickPattern?.isBullish;
      tileColor = isBull == true
          ? const Color(0x28FF9F0A)
          : const Color(0x28FF453A);
      tileText = isBull == true
          ? const Color(0xFFFFB340)
          : const Color(0xFFFF6961);
      tileIcon = _CandleIcon(color: tileText);
    } else if (isIndicator) {
      tileColor = const Color(0x2DBF5AF2);
      tileText = const Color(0xFFD58CF7);
      tileIcon = _WaveIcon(color: tileText);
    } else if (isDrawing) {
      tileColor = const Color(0x2864D2FF);
      tileText = const Color(0xFF64D2FF);
      tileIcon = _TrendlineIcon(color: tileText);
    } else {
      tileColor = const Color(0x290A84FF);
      tileText = const Color(0xFF4DA3FF);
      tileIcon = _BellIcon(color: tileText);
    }

    final dp = alert.symbol.length == 6
        ? '${alert.symbol.substring(0, 3)}/${alert.symbol.substring(3)}'
        : alert.symbol;
    final config = isChain ? alert.multiStepConfig : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onLongPress: () => _showAlertActions(context, alert, am),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tileColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: tileIcon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isScheduled
                              ? (alert.eventName ?? 'Calendar Alert')
                              : isChain
                              ? (alert.note.isNotEmpty
                                    ? alert.note
                                    : 'Logic Chain')
                              : isPattern
                              ? (alert.candlestickPattern?.label ?? 'Pattern')
                              : isIndicator
                              ? (alert.indicatorConfig?.summary ??
                                    'Indicator Alert')
                              : '$dp ${alert.condition.label}',
                          style: AppTheme.sans(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isScheduled
                              ? '${alert.symbol} · ${alert.scheduledTime != null ? DateFormat('MMM d, HH:mm').format(alert.scheduledTime!.toLocal()) : 'Pending'}'
                              : isChain
                              ? '$dp · Logic chain'
                              : isPattern
                              ? '$dp · ${alert.timeframe} · On candle close'
                              : isIndicator
                              ? '$dp · ${alert.timeframe}'
                              : isDrawing
                              ? '$dp · ${alert.formattedTarget()} · Drawing'
                              : '${alert.formattedTarget()} · now ${alert.initialPrice.toStringAsFixed(alert.initialPrice > 100 ? 3 : 5)}',
                          style: AppTheme.mono(fontSize: 13, color: _t2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _IosToggle(
                        value: alert.isActive,
                        onChanged: (_) => am.toggleAlert(alert.id),
                      ),
                      if (alert.cooldownMinutes > 0 && alert.isActive) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x28FF9F0A),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            'Cooldown ${alert.cooldownMinutes}m',
                            style: AppTheme.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFFB340),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (isChain && config != null) ...[
                const SizedBox(height: 16),
                _chainProgressBar(config),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STAGE ${config.currentStageIndex + 1} OF ${config.stages.length}',
                          style: AppTheme.sans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.9,
                            color: _t2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          config.stages.isNotEmpty
                              ? config.stages[config.currentStageIndex].name
                              : 'Running',
                          style: AppTheme.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Builder(
                      builder: (ctx) {
                        final rem = config.timeRemaining(DateTime.now());
                        if (rem == null) return const SizedBox.shrink();
                        final mins = rem.inMinutes;
                        final secs = (rem.inSeconds % 60).toString().padLeft(
                          2,
                          '0',
                        );
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x290A84FF),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: _bl,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${mins}m ${secs}s left',
                                style: AppTheme.mono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF4DA3FF),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chainProgressBar(MultiStepConfig config) {
    return Row(
      children: [
        for (int i = 0; i < config.stages.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < config.currentStageIndex
                    ? _up
                    : i == config.currentStageIndex
                    ? null
                    : _s3,
                gradient: i == config.currentStageIndex
                    ? const LinearGradient(
                        colors: [_bl, _s3],
                        stops: [0.6, 0.6],
                      )
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── History tab ─────────────────────────────────────────────────────────
  Widget _buildHistoryTab(AlertManager? am) {
    final triggered = am?.history ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 100),
      children: [
        if (triggered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _summaryCard(triggered),
          ),
        if (triggered.isNotEmpty || (_history?.isNotEmpty ?? false))
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
              child: GestureDetector(
                onTap: () => _showClearDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _s2,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    'Clear',
                    style: AppTheme.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFF6961),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (triggered.isNotEmpty) ..._groupedTriggered(triggered, am!),
        if (_history == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _bl),
            ),
          )
        else if (_history!.isEmpty && triggered.isEmpty)
          _emptyState(
            icon: Icons.notifications_none_rounded,
            message: 'No alert history yet',
            sub: 'Triggered alerts will appear here',
          )
        else if (_history!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'AI ANALYSIS HISTORY',
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.99,
                color: _t2,
              ),
            ),
          ),
          for (final item in _history!)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _aiHistoryCard(item),
            ),
        ],
      ],
    );
  }

  Widget _summaryCard(List<PriceAlert> triggered) {
    final now = DateTime.now();
    final counts = List.filled(7, 0);
    for (final a in triggered) {
      if (a.triggeredAt == null) continue;
      final d = now.difference(a.triggeredAt!).inDays;
      if (d >= 0 && d < 7) counts[6 - d]++;
    }
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRIGGERED · 7 DAYS',
                style: AppTheme.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.99,
                  color: _t2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${triggered.length}',
                style: AppTheme.mono(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.36,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                Container(
                  width: 18,
                  height: maxCount == 0
                      ? 8.0
                      : (14 + (40 * counts[i] / maxCount)).clamp(8.0, 54.0),
                  decoration: BoxDecoration(
                    color: i == 6 ? _bl : _s3,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _groupedTriggered(List<PriceAlert> triggered, AlertManager am) {
    final now = DateTime.now();
    final today = <PriceAlert>[],
        yesterday = <PriceAlert>[],
        older = <PriceAlert>[];
    for (final a in triggered) {
      final d = now.difference(a.triggeredAt ?? now).inDays;
      if (d == 0) {
        today.add(a);
      } else if (d == 1) {
        yesterday.add(a);
      } else {
        older.add(a);
      }
    }
    final out = <Widget>[];
    void addGroup(String label, List<PriceAlert> items) {
      if (items.isEmpty) return;
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            label,
            style: AppTheme.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.99,
              color: _t2,
            ),
          ),
        ),
      );
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: _s1,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++)
                  _triggeredRow(items[i], isLast: i == items.length - 1),
              ],
            ),
          ),
        ),
      );
    }

    addGroup('TODAY', today);
    addGroup('YESTERDAY', yesterday);
    addGroup('EARLIER', older);
    return out;
  }

  Widget _triggeredRow(PriceAlert alert, {required bool isLast}) {
    final isChain = alert.isMultiStepAlert;
    final isPattern = alert.isPatternAlert;
    final isIndicator = alert.isIndicatorAlert;
    final Color tileColor;
    final Color tileText;
    final Widget tileIcon;
    if (isChain) {
      tileColor = const Color(0x2830D158);
      tileText = const Color(0xFF43E06A);
      tileIcon = Icon(Icons.check, color: tileText, size: 20);
    } else if (isPattern) {
      tileColor = const Color(0x28FF9F0A);
      tileText = const Color(0xFFFFB340);
      tileIcon = _CandleIcon(color: tileText);
    } else if (isIndicator) {
      tileColor = const Color(0x2DBF5AF2);
      tileText = const Color(0xFFD58CF7);
      tileIcon = _WaveIcon(color: tileText);
    } else {
      tileColor = const Color(0x290A84FF);
      tileText = const Color(0xFF4DA3FF);
      tileIcon = _BellIcon(color: tileText);
    }
    final dp = alert.symbol.length == 6
        ? '${alert.symbol.substring(0, 3)}/${alert.symbol.substring(3)}'
        : alert.symbol;
    final timeStr = alert.triggeredAt != null
        ? DateFormat('HH:mm').format(alert.triggeredAt!)
        : '';
    final priceStr = alert.isPatternAlert ? '' : alert.formattedTarget();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0x17FFFFFF))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: tileIcon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isChain
                      ? '$dp chain completed'
                      : isPattern
                      ? (alert.candlestickPattern?.label ?? 'Pattern')
                      : isIndicator
                      ? '${alert.indicatorConfig?.indicatorType.label ?? "Indicator"} triggered'
                      : '$dp ${alert.condition.label}',
                  style: AppTheme.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isChain
                      ? 'All stages complete · ${alert.timeframe}'
                      : isPattern
                      ? '$dp · ${alert.timeframe}'
                      : isIndicator
                      ? '${alert.indicatorConfig?.summary ?? ""} · $dp'
                      : 'Target ${alert.formattedTarget()}',
                  style: AppTheme.sans(fontSize: 12, color: _t2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (priceStr.isNotEmpty)
                Text(
                  priceStr,
                  style: AppTheme.mono(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              Text(timeStr, style: AppTheme.mono(fontSize: 12, color: _t2)),
            ],
          ),
        ],
      ),
    );
  }

  // ── AI Analysis History card (logic unchanged, restyled) ─────────────────
  Widget _aiHistoryCard(PipelineRunResult item) {
    final dateStr = DateFormat('MMM d, yyyy • HH:mm').format(item.timestamp);
    final sig = item.finalSignal;
    final dirColor = sig.direction == SignalDirection.buy
        ? _up
        : (sig.direction == SignalDirection.sell
              ? const Color(0xFFFF453A)
              : Colors.amber);
    return Container(
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () =>
                      _navigateToChart(item.symbol, item.consolidatedSignal),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${item.symbol} · ${item.timeframe}',
                        style: AppTheme.sans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _bl,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: _bl,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: dirColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: dirColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sig.direction.name.toUpperCase(),
                        style: AppTheme.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: dirColor,
                        ),
                      ),
                      if (sig.confidence > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${sig.confidence}/10',
                          style: AppTheme.mono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: dirColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.strategy.name,
              style: AppTheme.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _bl,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _priceCol(
                  'Entry',
                  sig.entryPrice,
                  () => _openCreateAlert(
                    item.symbol,
                    sig.entryPrice,
                    note: 'Entry from ${item.strategy.name}',
                    condition: sig.direction == SignalDirection.buy
                        ? AlertCondition.crossesAbove
                        : AlertCondition.crossesBelow,
                  ),
                ),
                const SizedBox(width: 6),
                _priceCol(
                  'Take Profit',
                  sig.takeProfit,
                  () => _openCreateAlert(
                    item.symbol,
                    sig.takeProfit,
                    note: 'TP from ${item.strategy.name}',
                    condition: sig.direction == SignalDirection.buy
                        ? AlertCondition.crossesAbove
                        : AlertCondition.crossesBelow,
                  ),
                ),
                const SizedBox(width: 6),
                _priceCol(
                  'Stop Loss',
                  sig.stopLoss,
                  () => _openCreateAlert(
                    item.symbol,
                    sig.stopLoss,
                    note: 'SL from ${item.strategy.name}',
                    condition: sig.direction == SignalDirection.buy
                        ? AlertCondition.crossesBelow
                        : AlertCondition.crossesAbove,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    label: 'Set Alert',
                    icon: Icons.add_alert_rounded,
                    color: _bl,
                    onTap: () => _openCreateAlert(
                      item.symbol,
                      sig.entryPrice,
                      note: '${item.strategy.name} Entry',
                      condition: sig.direction == SignalDirection.buy
                          ? AlertCondition.crossesAbove
                          : AlertCondition.crossesBelow,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionBtn(
                    label: 'Logic Chain',
                    icon: Icons.linear_scale_rounded,
                    color: Colors.amber,
                    onTap: () => _buildLogicChain(item),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionBtn(
                    label: 'Re-run',
                    icon: Icons.play_arrow_rounded,
                    color: const Color(0xFF38BDF8),
                    filled: true,
                    onTap: () => _reRunStrategy(item),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(color: Color(0x17FFFFFF), height: 1),
            ),
            ExpansionTile(
              title: Text(
                'Multi-Agent Deliberation & Analysis',
                style: AppTheme.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _bl,
                ),
              ),
              subtitle: Text(
                '${item.initialSpecialistSignals.length} Specialists · Grounding Critic',
                style: AppTheme.sans(fontSize: 11, color: _t2),
              ),
              tilePadding: EdgeInsets.zero,
              children: [
                if (item.initialSpecialistSignals.isNotEmpty ||
                    item.refinedSpecialistSignals.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SPECIALIST AGENTS DELIBERATION',
                      style: AppTheme.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _bl,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...(item.refinedSpecialistSignals.isNotEmpty
                          ? item.refinedSpecialistSignals
                          : item.initialSpecialistSignals)
                      .asMap()
                      .entries
                      .map((entry) {
                        final idx = entry.key;
                        final spec = entry.value;
                        final sc = spec.direction == SignalDirection.buy
                            ? _up
                            : (spec.direction == SignalDirection.sell
                                  ? const Color(0xFFFF453A)
                                  : Colors.amber);
                        final initSpec =
                            (item.refinedSpecialistSignals.isNotEmpty &&
                                item.initialSpecialistSignals.length > idx)
                            ? item.initialSpecialistSignals[idx]
                            : null;
                        return _SpecialistHistoryCard(
                          spec: spec,
                          initSpec: initSpec,
                          sc: sc,
                        );
                      }),
                  const SizedBox(height: 12),
                ],
                if (item.groundingCritique.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ADVERSARIAL GROUNDING CRITIC',
                      style: AppTheme.sans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.amber,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.security_rounded,
                              size: 16,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Risk & Adversarial Critique',
                              style: AppTheme.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        MarkdownBody(
                          data: item.groundingCritique,
                          selectable: true,
                        ),
                      ],
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CONSOLIDATED STRATEGY VERDICT',
                    style: AppTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: dirColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: MarkdownBody(
                    data: sig.analysis.isNotEmpty
                        ? sig.analysis
                        : 'No analysis provided.',
                    selectable: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _strategyStorage.saveLastChartSignal(sig);
                      _navigateToChart(item.symbol);
                    },
                    icon: const Icon(Icons.layers_rounded, size: 18),
                    label: const Text('Overlay Setup On Chart'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dirColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 6),
            Text(dateStr, style: AppTheme.sans(fontSize: 11, color: _t2)),
          ],
        ),
      ),
    );
  }

  Widget _priceCol(String label, double val, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _s2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _bl.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: AppTheme.sans(
                      fontSize: 10,
                      color: _t2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.touch_app_rounded, size: 11, color: _bl),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                val > 0 ? val.toStringAsFixed(val > 100 ? 2 : 4) : '--',
                style: AppTheme.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _bl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String message,
    required String sub,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 54, color: _t2),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTheme.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(sub, style: AppTheme.sans(fontSize: 13, color: _t2)),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _s2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete triggered alerts and all AI analyses.',
          style: TextStyle(color: _t2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _t2)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearHistory();
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: Color(0xFFFF6961)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialistHistoryCard extends StatefulWidget {
  final AgentSignal spec;
  final AgentSignal? initSpec;
  final Color sc;

  const _SpecialistHistoryCard({
    required this.spec,
    this.initSpec,
    required this.sc,
  });

  @override
  State<_SpecialistHistoryCard> createState() => _SpecialistHistoryCardState();
}

class _SpecialistHistoryCardState extends State<_SpecialistHistoryCard> {
  bool _expanded = false;
  bool _showInitialRound = false;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final sc = widget.sc;
    final initSpec = widget.initSpec;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x17FFFFFF)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: Agent Name, Direction & Confidence Badge, Expand/Collapse icon
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spec.agentName,
                        style: AppTheme.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: sc.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${spec.direction.label} · ${spec.confidenceScore}%',
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: sc,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _t2,
                      size: 18,
                    ),
                  ],
                ),
                // Theory subtitle (if present)
                if (spec.theory.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A84FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF0A84FF).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'Intent: ${spec.theory}',
                      style: AppTheme.sans(
                        fontSize: 11,
                        color: const Color(0xFF64D2FF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                // Analysis text (collapsed snippet or full)
                const SizedBox(height: 6),
                Text(
                  _expanded
                      ? spec.analysis
                      : (spec.analysis.length > 120
                            ? '${spec.analysis.substring(0, 117)}...'
                            : spec.analysis),
                  style: AppTheme.sans(fontSize: 12, color: _t2, height: 1.4),
                ),
                // Expanded Details
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  const Divider(color: Color(0x17FFFFFF), height: 1),
                  const SizedBox(height: 10),
                  // Levels Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _levelColumn(
                        'Entry',
                        spec.entryPrice > 0
                            ? spec.entryPrice.toStringAsFixed(5)
                            : 'Market',
                        Colors.white,
                      ),
                      _levelColumn(
                        'Stop Loss',
                        spec.stopLoss > 0
                            ? spec.stopLoss.toStringAsFixed(5)
                            : 'None',
                        const Color(0xFFFF6961),
                      ),
                      _levelColumn(
                        'Target TP',
                        spec.takeProfit > 0
                            ? spec.takeProfit.toStringAsFixed(5)
                            : 'Open',
                        const Color(0xFF43E06A),
                      ),
                      if (spec.takeProfit2 != null && spec.takeProfit2! > 0)
                        _levelColumn(
                          'TP2',
                          spec.takeProfit2!.toStringAsFixed(5),
                          const Color(0xFF30D158),
                        ),
                    ],
                  ),
                  // If there is an initial round pre-grounding critique
                  if (initSpec != null &&
                      (initSpec.direction != spec.direction ||
                          initSpec.theory != spec.theory ||
                          initSpec.analysis != spec.analysis)) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(
                        () => _showInitialRound = !_showInitialRound,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 12,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _showInitialRound
                                  ? 'Hide initial draft'
                                  : 'View initial draft (pre-critique)',
                              style: AppTheme.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showInitialRound) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0x17FFFFFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Initial Round: ${initSpec.direction.label} (${initSpec.confidenceScore}%)',
                              style: AppTheme.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _t2,
                              ),
                            ),
                            if (initSpec.theory.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                initSpec.theory,
                                style: AppTheme.sans(
                                  fontSize: 11,
                                  color: _t2,
                                ).copyWith(fontStyle: FontStyle.italic),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              initSpec.analysis,
                              style: AppTheme.sans(
                                fontSize: 11,
                                color: const Color(0x73EBEBF5),
                                height: 1.35,
                              ),
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
        ),
      ),
    );
  }

  Widget _levelColumn(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.sans(fontSize: 10, color: const Color(0x73EBEBF5)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Shared UI primitives ─────────────────────────────────────────────────────

class _SegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _SegmentedControl({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 32,
                  decoration: BoxDecoration(
                    color: i == selectedIndex ? _s3 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: i == selectedIndex
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: AppTheme.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: i == selectedIndex ? Colors.white : _t2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        height: 30,
        decoration: BoxDecoration(
          color: selected ? Colors.white : _s1,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTheme.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black : _t2,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _IconBtn({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xAA2C2C2E),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x17FFFFFF)),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _IosToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _IosToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 51,
        height: 31,
        decoration: BoxDecoration(
          color: value ? _up : _s3,
          borderRadius: BorderRadius.circular(16),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.9) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: filled ? null : Border.all(color: color, width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: filled ? Colors.black : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: filled ? Colors.black : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SVG-style icon painters ──────────────────────────────────────────────────

class _FilterIconPainter extends CustomPainter {
  final Color color;
  _FilterIconPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawLine(const Offset(4, 7), const Offset(20, 7), p);
    canvas.drawLine(const Offset(7, 12), const Offset(17, 12), p);
    canvas.drawLine(const Offset(10, 17), const Offset(14, 17), p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _BellIcon extends StatelessWidget {
  final Color color;
  const _BellIcon({required this.color});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.notifications_outlined, color: color, size: 20);
}

class _ChainIcon extends StatelessWidget {
  final Color color;
  const _ChainIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 22),
    painter: _ChainPainter(color: color),
  );
}

class _ChainPainter extends CustomPainter {
  final Color color;
  _ChainPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(5, 6)
      ..lineTo(11, 6)
      ..lineTo(11, 11)
      ..lineTo(19, 11)
      ..moveTo(5, 18)
      ..lineTo(11, 18)
      ..lineTo(11, 13);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CandleIcon extends StatelessWidget {
  final Color color;
  const _CandleIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 22),
    painter: _CandlePainter(color: color),
  );
}

class _CandlePainter extends CustomPainter {
  final Color color;
  _CandlePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawLine(const Offset(12, 4), const Offset(12, 7), p);
    canvas.drawLine(const Offset(12, 17), const Offset(12, 20), p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 7, 6, 10),
        const Radius.circular(1),
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _WaveIcon extends StatelessWidget {
  final Color color;
  const _WaveIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 22),
    painter: _WavePainter(color: color),
  );
}

class _WavePainter extends CustomPainter {
  final Color color;
  _WavePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(3, 15)
      ..cubicTo(6, 15, 6, 7, 9, 7)
      ..cubicTo(12, 7, 12, 17, 15, 17)
      ..cubicTo(18, 17, 18, 11, 21, 11);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _TrendlineIcon extends StatelessWidget {
  final Color color;
  const _TrendlineIcon({required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(22, 22),
    painter: _TrendlinePainter(color: color),
  );
}

class _TrendlinePainter extends CustomPainter {
  final Color color;
  _TrendlinePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final fp = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawLine(const Offset(4, 19), const Offset(20, 6), p);
    canvas.drawCircle(const Offset(4, 19), 1.6, fp);
    canvas.drawCircle(const Offset(20, 6), 1.6, fp);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
