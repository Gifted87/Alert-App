import 'package:flutter/material.dart';

import '../models/market_models.dart';
import '../services/alert_manager.dart';
import '../services/biquote_widget_service.dart';
import '../theme/app_theme.dart';

class TickerTapeBar extends StatelessWidget {
  final Map<String, BiquoteTick> ticks;
  final String selectedSymbol;
  final ValueChanged<String> onSelectSymbol;
  final bool isOnline;
  final List<String>? symbols;
  final VoidCallback? onOpenSearch;

  final AlertManager? alertManager;

  const TickerTapeBar({
    super.key,
    required this.ticks,
    required this.selectedSymbol,
    required this.onSelectSymbol,
    this.isOnline = true,
    this.symbols,
    this.onOpenSearch,
    this.alertManager,
  });

  static const List<String> defaultSymbols = [
    'EURUSD',
    'GBPUSD',
    'USDJPY',
    'XAUUSD',
    'BTCUSD',
    'AUDUSD',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displaySymbols = symbols ?? defaultSymbols;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : const Color(0xFFE2E8F0),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Widget quick launch buttons
          InkWell(
            onTap: () => BiquoteWidgetService.openEconomicCalendar(
              context,
              onSelectSymbol: onSelectSymbol,
              alertManager: alertManager,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month,
                    size: 13,
                    color: Color(0xFF00E5FF),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'CALENDAR',
                    style: AppTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => BiquoteWidgetService.openMarketMovers(
              context,
              onSelectSymbol: onSelectSymbol,
              alertManager: alertManager,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    size: 13,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'MOVERS',
                    style: AppTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => BiquoteWidgetService.openFinancialNews(
              context,
              onSelectSymbol: onSelectSymbol,
              alertManager: alertManager,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.newspaper_rounded,
                    size: 13,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'NEWS',
                    style: AppTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF38BDF8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => BiquoteWidgetService.openCurrencyMatrix(
              context,
              onSelectSymbol: onSelectSymbol,
              alertManager: alertManager,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.grid_4x4_rounded,
                    size: 13,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'MATRIX',
                    style: AppTheme.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Streaming Ticker Tape items
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: displaySymbols.length,
              separatorBuilder: (_, _) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                width: 1,
                color: theme.dividerColor,
              ),
              itemBuilder: (context, index) {
                final symbol = displaySymbols[index];
                final tick = ticks[symbol];
                final price = tick?.mid ?? 0.0;
                final change = tick?.dayDiffPercent ?? 0.0;
                final isPositive = change >= 0;
                final isSelected = symbol == selectedSymbol;

                final displayPair = symbol.length == 6
                    ? '${symbol.substring(0, 3)}/${symbol.substring(3)}'
                    : symbol;

                final changeColor = isPositive
                    ? (isDark ? AppTheme.darkBullish : AppTheme.lightBullish)
                    : (isDark ? AppTheme.darkBearish : AppTheme.lightBearish);

                return InkWell(
                  onTap: () => onSelectSymbol(symbol),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: isSelected
                            ? BoxDecoration(
                                color:
                                    (isDark
                                            ? AppTheme.darkPrimary
                                            : AppTheme.lightPrimary)
                                        .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              )
                            : null,
                        child: Text(
                          displayPair,
                          style: AppTheme.mono(
                            context: context,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected
                                ? (isDark
                                      ? AppTheme.darkPrimary
                                      : AppTheme.lightPrimary)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        price > 0
                            ? price.toStringAsFixed(
                                symbol.contains('JPY')
                                    ? 3
                                    : (symbol.contains('XAU') ||
                                              symbol.contains('BTC')
                                          ? 2
                                          : 5),
                              )
                            : '---',
                        style: AppTheme.mono(
                          context: context,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${isPositive ? '+' : ''}${change.toStringAsFixed(2)}%',
                        style: AppTheme.mono(
                          context: context,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          if (onOpenSearch != null)
            InkWell(
              onTap: onOpenSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: Icon(
                  Icons.search,
                  size: 16,
                  color: isDark ? AppTheme.darkPrimary : AppTheme.lightPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
