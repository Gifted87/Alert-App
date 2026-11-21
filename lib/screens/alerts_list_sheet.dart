import 'package:flutter/material.dart';

import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../theme/app_theme.dart';

class AlertsListSheet extends StatefulWidget {
  final AlertManager alertManager;
  final Map<String, BiquoteTick> latestTicks;
  final ValueChanged<String>? onSelectSymbol;

  const AlertsListSheet({
    super.key,
    required this.alertManager,
    required this.latestTicks,
    this.onSelectSymbol,
  });

  @override
  State<AlertsListSheet> createState() => _AlertsListSheetState();
}

class _AlertsListSheetState extends State<AlertsListSheet> {
  @override
  void initState() {
    super.initState();
    widget.alertManager.addListener(_onAlertsChanged);
  }

  @override
  void dispose() {
    widget.alertManager.removeListener(_onAlertsChanged);
    super.dispose();
  }

  void _onAlertsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final alertManager = widget.alertManager;

    return DefaultTabController(
      length: 2,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header & Tabs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ALERTS MANAGER',
                  style: AppTheme.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              indicatorWeight: 2.5,
              tabs: [
                Tab(text: 'Active (${alertManager.activeAlerts.length})'),
                Tab(text: 'Triggered (${alertManager.history.length})'),
              ],
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                children: [
                  _buildActiveAlertsList(context, alertManager),
                  _buildTriggeredList(context, alertManager),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAlertsList(
    BuildContext context,
    AlertManager alertManager,
  ) {
    final alerts = alertManager.alerts;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final latestTicks = widget.latestTicks;

    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'No alerts set',
              style: AppTheme.sans(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final tick = latestTicks[alert.symbol];
        final currentPrice = tick?.mid ?? alert.initialPrice;
        final pipDist = alert.pipDistance(currentPrice);

        final Color badgeColor;
        if (alert.isMultiStepAlert) {
          badgeColor = Colors.amber;
        } else if (alert.isTimeScheduleAlert) {
          badgeColor = Colors.amber;
        } else if (alert.isPatternAlert) {
          final isBull = alert.candlestickPattern?.isBullish;
          if (isBull == true) {
            badgeColor = isDark ? AppTheme.darkBullish : AppTheme.lightBullish;
          } else if (isBull == false) {
            badgeColor = isDark ? AppTheme.darkBearish : AppTheme.lightBearish;
          } else {
            badgeColor = Colors.amber;
          }
        } else if (alert.isIndicatorAlert) {
          badgeColor = theme.colorScheme.primary;
        } else {
          final isBullish = alert.condition == AlertCondition.crossesAbove;
          badgeColor = isBullish
              ? (isDark ? AppTheme.darkBullish : AppTheme.lightBullish)
              : (isDark ? AppTheme.darkBearish : AppTheme.lightBearish);
        }

        final displayPair = alert.symbol.length == 6
            ? '${alert.symbol.substring(0, 3)}/${alert.symbol.substring(3)}'
            : alert.symbol;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: alert.isActive
                  ? badgeColor.withValues(alpha: 0.5)
                  : theme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Left: Symbol & Condition / Pattern / Indicator
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (widget.onSelectSymbol != null) {
                          widget.onSelectSymbol!(alert.symbol);
                          Navigator.pop(context);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                displayPair,
                                style: AppTheme.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  alert.isMultiStepAlert
                                      ? '🔗 LOGIC CHAIN • LEVEL ${alert.multiStepConfig!.currentStageIndex + 1}/${alert.multiStepConfig!.stages.length}'
                                      : alert.isTimeScheduleAlert
                                      ? '📅 SCHEDULED EVENT'
                                      : alert.isPatternAlert
                                      ? 'PATTERN • ${alert.timeframe.toUpperCase()}'
                                      : alert.isIndicatorAlert
                                      ? '${alert.indicatorConfig?.indicatorType.label.toUpperCase() ?? "INDICATOR"} • ${alert.timeframe.toUpperCase()}'
                                      : alert.isDrawingAlert
                                      ? '🎯 LINE • ${alert.condition.label.toUpperCase()}'
                                      : alert.condition.label.toUpperCase(),
                                  style: AppTheme.sans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (alert.isMultiStepAlert) ...[
                                Text(
                                  alert.note.isNotEmpty
                                      ? alert.note
                                      : 'Multi-Step Strategy Chain',
                                  style: AppTheme.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber,
                                  ),
                                ),
                              ] else if (alert.isPatternAlert) ...[
                                Text(
                                  alert.candlestickPattern?.label ?? 'Pattern',
                                  style: AppTheme.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: badgeColor,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.dividerColor.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    alert.timeframe.toUpperCase(),
                                    style: AppTheme.mono(
                                      context: context,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ] else if (alert.isIndicatorAlert) ...[
                                Text(
                                  alert.indicatorConfig?.summary ??
                                      'Indicator Alert',
                                  style: AppTheme.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.dividerColor.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    alert.timeframe.toUpperCase(),
                                    style: AppTheme.mono(
                                      context: context,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  'Target: ${alert.formattedTarget()}',
                                  style: AppTheme.mono(
                                    context: context,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '(${pipDist >= 0 ? '+' : ''}${pipDist.abs() > 99999 ? '>9999' : pipDist.toStringAsFixed(1)} pips)',
                                  style: AppTheme.mono(
                                    context: context,
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    size: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    alert.ringtoneTitle,
                                    style: AppTheme.sans(
                                      fontSize: 10,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (alert.note.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              alert.note,
                              style: AppTheme.sans(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Right: Toggle and Delete
                  Switch(
                    value: alert.isActive,
                    activeThumbColor: badgeColor,
                    onChanged: (_) => alertManager.toggleAlert(alert.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => alertManager.deleteAlert(alert.id),
                  ),
                ],
              ),
              if (alert.isMultiStepAlert) ...[
                const SizedBox(height: 8),
                _buildLogicChainProgress(
                  context,
                  alert,
                  theme,
                  isDark,
                  alertManager,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogicChainProgress(
    BuildContext context,
    PriceAlert alert,
    ThemeData theme,
    bool isDark,
    AlertManager alertManager,
  ) {
    final config = alert.multiStepConfig;
    if (config == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface1 : AppTheme.lightSurface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOGIC CHAIN PIPELINE',
                style: AppTheme.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.amber,
                  letterSpacing: 0.6,
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.refresh, size: 12, color: Colors.amber),
                label: Text(
                  'Reset Chain',
                  style: AppTheme.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                onPressed: () => alertManager.resetMultiStepAlert(alert.id),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Vertical Tree / Stages List
          ...config.stages.asMap().entries.map((entry) {
            final idx = entry.key;
            final stage = entry.value;
            final isCompleted = stage.isCompleted;
            final isActive =
                idx == config.currentStageIndex && !config.isAllCompleted;

            final statusColor = isCompleted
                ? (isDark ? AppTheme.darkBullish : AppTheme.lightBullish)
                : isActive
                ? Colors.amber
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor.withValues(alpha: 0.2),
                          border: Border.all(color: statusColor, width: 1.5),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.check
                              : isActive
                              ? Icons.play_arrow
                              : Icons.lock_outline,
                          size: 10,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Level ${idx + 1}: ${stage.name}',
                        style: AppTheme.sans(
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isActive
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          isCompleted
                              ? 'COMPLETED [1]'
                              : isActive
                              ? 'RUNNING'
                              : 'LOCKED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (isActive &&
                          config.timeRemaining(DateTime.now()) != null) ...[
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            final rem = config.timeRemaining(DateTime.now())!;
                            final minStr = rem.inMinutes;
                            final secStr = (rem.inSeconds % 60)
                                .toString()
                                .padLeft(2, '0');
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: Colors.amber,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    size: 10,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '⏳ ${minStr}m ${secStr}s',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  // If active or completed, show sub-alarms in this stage
                  if (isActive || isCompleted)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: stage.nodes.asMap().entries.map((entry) {
                          final nodeIdx = entry.key;
                          final n = entry.value;
                          final isSat = n.isSatisfied;
                          final nodeColor = isSat
                              ? (isDark
                                    ? AppTheme.darkBullish
                                    : AppTheme.lightBullish)
                              : theme.colorScheme.onSurfaceVariant;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                if (nodeIdx > 0)
                                  Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 0.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Text(
                                      n.operatorToPrevious,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ),
                                Text(
                                  '• ',
                                  style: TextStyle(
                                    color: nodeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    n.summary,
                                    style: AppTheme.sans(
                                      fontSize: 10,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: nodeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    isSat ? '[ 1 ]' : '[ 0 ]',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: nodeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (idx < config.stages.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SizedBox(
                        height: 10,
                        child: VerticalDivider(
                          color: isCompleted
                              ? (isDark
                                    ? AppTheme.darkBullish
                                    : AppTheme.lightBullish)
                              : theme.dividerColor,
                          thickness: 1,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTriggeredList(BuildContext context, AlertManager alertManager) {
    final history = alertManager.history;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'No alerts triggered yet',
              style: AppTheme.sans(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final alert = history[index];
        final displayPair = alert.symbol.length == 6
            ? '${alert.symbol.substring(0, 3)}/${alert.symbol.substring(3)}'
            : alert.symbol;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface2 : AppTheme.lightSurface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    if (widget.onSelectSymbol != null) {
                      widget.onSelectSymbol!(alert.symbol);
                      Navigator.pop(context);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            alert.isPatternAlert
                                ? Icons.candlestick_chart
                                : alert.isIndicatorAlert
                                ? Icons.analytics_outlined
                                : Icons.notifications_active,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            displayPair,
                            style: AppTheme.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              alert.isPatternAlert
                                  ? '${alert.candlestickPattern?.label ?? "Pattern"} (${alert.timeframe.toUpperCase()})'
                                  : alert.isIndicatorAlert
                                  ? '${alert.indicatorConfig?.indicatorType.label ?? "Indicator"} (${alert.timeframe.toUpperCase()})'
                                  : alert.condition.label,
                              style: AppTheme.sans(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alert.isPatternAlert
                            ? 'Confirmed on ${alert.timeframe.toUpperCase()} candle'
                            : alert.isIndicatorAlert
                            ? alert.indicatorConfig?.summary ??
                                  'Indicator Confirmed'
                            : 'Target: ${alert.formattedTarget()}',
                        style: AppTheme.mono(context: context, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text(
                      'RE-ARM',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      final tick = widget.latestTicks[alert.symbol];
                      alertManager.rearmAlert(
                        alert.id,
                        currentPrice: tick?.mid,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Re-armed alert for ${alert.symbol}'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => alertManager.deleteAlert(alert.id),
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
