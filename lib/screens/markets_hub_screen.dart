import 'package:flutter/material.dart';

import '../services/alert_manager.dart';
import 'currency_matrix_screen.dart';
import 'economic_calendar_screen.dart';
import 'financial_news_screen.dart';
import 'market_movers_screen.dart';

class MarketsHubScreen extends StatefulWidget {
  final ValueChanged<String>? onSelectSymbol;
  final AlertManager? alertManager;
  final int initialTab;

  const MarketsHubScreen({
    super.key,
    this.onSelectSymbol,
    this.alertManager,
    this.initialTab = 0,
  });

  @override
  State<MarketsHubScreen> createState() => _MarketsHubScreenState();
}

class _MarketsHubScreenState extends State<MarketsHubScreen> {
  late int _activeTab;

  final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'Movers',
      'subtitle': 'Gainers, Losers & Volatility Breakouts',
      'icon': Icons.trending_up_rounded,
      'color': Color(0xFF30D158),
    },
    {
      'title': 'Matrix',
      'subtitle': '28-Pair Currency Strength & Relative Heatmap',
      'icon': Icons.grid_view_rounded,
      'color': Color(0xFF0A84FF),
    },
    {
      'title': 'Calendar',
      'subtitle': 'Economic Events & High-Impact Countdown',
      'icon': Icons.calendar_month_rounded,
      'color': Color(0xFFFF9F0A),
    },
    {
      'title': 'News',
      'subtitle': 'Macro Wire & Sentiment Feeds',
      'icon': Icons.newspaper_rounded,
      'color': Color(0xFF64D2FF),
    },
  ];

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  void _showTabSwitcher() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'MARKET SECTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.99,
                    color: Color(0x9EEBEBF5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...List.generate(_tabs.length, (idx) {
                final tab = _tabs[idx];
                final isSelected = _activeTab == idx;
                final color = tab['color'] as Color;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _activeTab = idx;
                      });
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2C2C2E)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected
                            ? Border.all(color: color.withValues(alpha: 0.35))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              tab['icon'] as IconData,
                              color: color,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tab['title'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xE0FFFFFF),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tab['subtitle'] as String,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0x80EBEBF5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: color,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IndexedStack(
          index: _activeTab,
          children: [
            MarketMoversScreen(
              onSelectSymbol: widget.onSelectSymbol,
              alertManager: widget.alertManager,
            ),
            CurrencyMatrixScreen(
              onSelectSymbol: widget.onSelectSymbol,
              alertManager: widget.alertManager,
            ),
            EconomicCalendarScreen(
              onSelectSymbol: widget.onSelectSymbol,
              alertManager: widget.alertManager,
            ),
            FinancialNewsScreen(
              onSelectSymbol: widget.onSelectSymbol,
              alertManager: widget.alertManager,
            ),
          ],
        ),

        // Subtle Floating Switcher Pill (non-intrusive, top right or title overlay)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: GestureDetector(
            onTap: _showTabSwitcher,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 44,
              width: 160,
              color: Colors.transparent, // Transparent hit area over Title
            ),
          ),
        ),

        // Distinct quick navigation pill in top-right
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: GestureDetector(
            onTap: _showTabSwitcher,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: const Color(0x33FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.unfold_more_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Hub',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
