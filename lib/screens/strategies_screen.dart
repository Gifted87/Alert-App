import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ai_models.dart';
import '../services/alert_manager.dart';
import '../services/biquote_service.dart';
import '../services/strategy_storage.dart';
import 'agent_editor_sheet.dart';
import 'analysis_screen.dart';
import 'instrument_search_sheet.dart';

class StrategiesScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback? onNavigateToChart;
  final ValueChanged<String>? onSelectSymbolForChart;
  final VoidCallback? onNavigateToHistory;
  final String? activeSymbol;
  final String? activeTimeframe;
  final ValueChanged<AgentSignal>? onSelectSignalForChart;
  final BiquoteService? biquoteService;
  final AlertManager? alertManager;

  const StrategiesScreen({
    super.key,
    this.isDark = true,
    this.onNavigateToChart,
    this.onSelectSymbolForChart,
    this.onNavigateToHistory,
    this.activeSymbol,
    this.activeTimeframe,
    this.onSelectSignalForChart,
    this.biquoteService,
    this.alertManager,
  });

  @override
  State<StrategiesScreen> createState() => _StrategiesScreenState();
}

class _StrategiesScreenState extends State<StrategiesScreen> {
  final StrategyStorage _storage = StrategyStorage();
  List<TradingStrategy> _strategies = [];
  List<SpecialistAgentConfig> _specialists = [];
  List<RecentStrategyRun> _recentRuns = [];
  bool _isLoading = true;
  int _selectedTab = 0; // 0: Strategies, 1: Single Specialists

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final strats = await _storage.getStrategies();
    final specs = await _storage.getSpecialists();
    final runs = await _storage.getRecentRuns();
    if (mounted) {
      setState(() {
        _strategies = strats;
        _specialists = specs;
        _recentRuns = runs;
        _isLoading = false;
      });
    }
  }

  Color _parseHex(String? hex, [Color fallback = const Color(0xFFBF5AF2)]) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('0xFF$clean'));
    } catch (_) {
      return fallback;
    }
  }

  void _runStrategy(TradingStrategy s) {
    _showLaunchAnalysisSheet(strategy: s);
  }

  void _runSpecialistStandalone(SpecialistAgentConfig spec) {
    _showLaunchAnalysisSheet(specialist: spec);
  }

  void _showLaunchAnalysisSheet({
    TradingStrategy? strategy,
    SpecialistAgentConfig? specialist,
  }) {
    final TradingStrategy strat =
        strategy ??
        TradingStrategy(
          id: 'single_${specialist!.id}',
          name: specialist.name,
          description: specialist.description.isNotEmpty
              ? specialist.description
              : 'Standalone specialist analysis with Grounding Critic.',
          specialists: [specialist],
          timeframes: specialist.timeframes.isNotEmpty
              ? specialist.timeframes
              : ['15m', '1H'],
          createdAt: DateTime.now(),
          colorHex: specialist.colorHex,
          consolidatorInstructions:
              'Evaluate standalone specialist output against historical OHLC.',
        );

    final popularPairs = [
      'EUR/USD',
      'GBP/USD',
      'USD/JPY',
      'XAU/USD',
      'BTC/USD',
      'ETH/USD',
      'US500',
      'NAS100',
    ];

    String chosenSymbol = widget.activeSymbol ?? 'EUR/USD';
    if (!chosenSymbol.contains('/') &&
        chosenSymbol.length == 6 &&
        !chosenSymbol.startsWith('US') &&
        !chosenSymbol.startsWith('GER')) {
      chosenSymbol =
          '${chosenSymbol.substring(0, 3)}/${chosenSymbol.substring(3)}';
    }

    final chosenTimeframes = Set<String>.from(
      strat.timeframes.isNotEmpty ? strat.timeframes : ['15m', '4H'],
    );

    Map<String, String> getAssetInfo(String sym) {
      final clean = sym.replaceAll('/', '').trim().toUpperCase();
      switch (clean) {
        case 'EURUSD':
          return {'name': 'Euro / US Dollar', 'class': 'Forex', 'tag': 'FX'};
        case 'GBPUSD':
          return {'name': 'British Pound / USD', 'class': 'Forex', 'tag': 'FX'};
        case 'USDJPY':
          return {'name': 'US Dollar / Yen', 'class': 'Forex', 'tag': 'FX'};
        case 'AUDUSD':
          return {'name': 'Aussie / US Dollar', 'class': 'Forex', 'tag': 'FX'};
        case 'USDCAD':
          return {
            'name': 'USD / Canadian Dollar',
            'class': 'Forex',
            'tag': 'FX',
          };
        case 'USDCHF':
          return {'name': 'USD / Swiss Franc', 'class': 'Forex', 'tag': 'FX'};
        case 'NZDUSD':
          return {'name': 'NZ Dollar / USD', 'class': 'Forex', 'tag': 'FX'};
        case 'XAUUSD':
          return {
            'name': 'Gold Spot / US Dollar',
            'class': 'Metals',
            'tag': 'METAL',
          };
        case 'XAGUSD':
          return {
            'name': 'Silver Spot / US Dollar',
            'class': 'Metals',
            'tag': 'METAL',
          };
        case 'BTCUSD':
          return {
            'name': 'Bitcoin / US Dollar',
            'class': 'Crypto',
            'tag': 'CRYPTO',
          };
        case 'ETHUSD':
          return {
            'name': 'Ethereum / US Dollar',
            'class': 'Crypto',
            'tag': 'CRYPTO',
          };
        case 'US500':
          return {'name': 'S&P 500 Index', 'class': 'Indices', 'tag': 'INDEX'};
        case 'NAS100':
        case 'USTEC':
          return {
            'name': 'Nasdaq 100 Index',
            'class': 'Indices',
            'tag': 'INDEX',
          };
        case 'US30':
          return {'name': 'Dow Jones 30', 'class': 'Indices', 'tag': 'INDEX'};
        default:
          return {'name': clean, 'class': 'Market', 'tag': 'ASSET'};
      }
    }

    IconData getAssetIcon(String assetClass) {
      switch (assetClass) {
        case 'Metals':
          return Icons.diamond_rounded;
        case 'Crypto':
          return Icons.currency_bitcoin_rounded;
        case 'Indices':
          return Icons.show_chart_rounded;
        default:
          return Icons.currency_exchange_rounded;
      }
    }

    Color getAssetColor(String assetClass) {
      switch (assetClass) {
        case 'Metals':
          return const Color(0xFFFFD60A);
        case 'Crypto':
          return const Color(0xFFFF9F0A);
        case 'Indices':
          return const Color(0xFF64D2FF);
        default:
          return const Color(0xFF30D158);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final color = _parseHex(strat.colorHex);
            final assetInfo = getAssetInfo(chosenSymbol);
            final assetClass = assetInfo['class']!;
            final assetColor = getAssetColor(assetClass);

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF141416),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: Color(0x24FFFFFF), width: 1),
                ),
              ),
              padding: EdgeInsets.only(
                top: 12,
                left: 18,
                right: 18,
                bottom: math.max(
                  28.0,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Apple Style Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0x38FFFFFF),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header: Strategy Name, Mode badge, and Close
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: color.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Icon(
                            strat.isMultiAgent
                                ? Icons.hub_rounded
                                : Icons.auto_awesome_rounded,
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                strat.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                strat.isMultiAgent
                                    ? 'Multi-Agent Confluence Strategy · ${strat.specialists.length} Specialists'
                                    : 'Single Specialist Analysis · Grounding Loop',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0x9EEBEBF5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2C2C2E),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Pipeline Step Flow Indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x17FFFFFF)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timeline_rounded, color: color, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              strat.isMultiAgent
                                  ? 'Specialists (${strat.specialists.length}) → Grounding Critic → Refinement Loop → Consolidator'
                                  : '${strat.specialists.first.name} → Grounding Critic → Refined Signal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: color,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // SECTION 1: STANDARD BIQUOTE INSTRUMENT SELECTOR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'INSTRUMENT / CURRENCY PAIR',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0x9EEBEBF5),
                            letterSpacing: 0.99,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF30D158),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Biquote Live Feed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF30D158),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ACTIVE ASSET HERO CARD (Interactive - opens standard InstrumentSearchSheet)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          InstrumentSearchSheet.show(
                            context,
                            currentSymbol: chosenSymbol.replaceAll('/', ''),
                            onSelectSymbol: (newSym) {
                              setModalState(() {
                                final clean = newSym
                                    .replaceAll('/', '')
                                    .trim()
                                    .toUpperCase();
                                if (clean.length == 6 &&
                                    !clean.startsWith('US') &&
                                    !clean.startsWith('GER') &&
                                    !clean.startsWith('XAU') &&
                                    !clean.startsWith('XAG') &&
                                    !clean.startsWith('BTC') &&
                                    !clean.startsWith('ETH')) {
                                  chosenSymbol =
                                      '${clean.substring(0, 3)}/${clean.substring(3)}';
                                } else if (clean == 'XAUUSD') {
                                  chosenSymbol = 'XAU/USD';
                                } else if (clean == 'BTCUSD') {
                                  chosenSymbol = 'BTC/USD';
                                } else if (clean == 'ETHUSD') {
                                  chosenSymbol = 'ETH/USD';
                                } else {
                                  chosenSymbol = clean;
                                }
                              });
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0x38FFFFFF)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: assetColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: assetColor.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Icon(
                                  getAssetIcon(assetClass),
                                  color: assetColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          chosenSymbol,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: assetColor.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            assetInfo['tag']!,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: assetColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      assetInfo['name']!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0x9EEBEBF5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0x17FFFFFF),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_rounded,
                                      size: 14,
                                      color: Color(0xFF0A84FF),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Browse',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0A84FF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick-Pick Liquid Markets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: popularPairs.map((p) {
                          final isSel = chosenSymbol == p;
                          final pInfo = getAssetInfo(p);
                          final pColor = getAssetColor(pInfo['class']!);

                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  chosenSymbol = p;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(0xFF0A84FF)
                                      : const Color(0xFF1C1C1E),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSel
                                        ? const Color(0xFF0A84FF)
                                        : const Color(0x17FFFFFF),
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isSel) ...[
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            color: pColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(
                                        p,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSel
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSel
                                              ? Colors.white
                                              : const Color(0x9EEBEBF5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // SECTION 2: MULTI-TIMEFRAME CONFLUENCE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'MULTI-TIMEFRAME CONFLUENCE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0x9EEBEBF5),
                            letterSpacing: 0.99,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFBF5AF2)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${chosenTimeframes.length} Selected',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFD58CF7),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Timeframe Chips Multi-select
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ['5m', '15m', '30m', '1H', '4H', '1D', '1W']
                          .map((tf) {
                            final isSel = chosenTimeframes.contains(tf);
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (isSel) {
                                    if (chosenTimeframes.length > 1) {
                                      chosenTimeframes.remove(tf);
                                    }
                                  } else {
                                    chosenTimeframes.add(tf);
                                  }
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: 36,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(0x2EBF5AF2)
                                      : const Color(0xFF1C1C1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSel
                                        ? const Color(0xFFBF5AF2)
                                        : const Color(0x17FFFFFF),
                                    width: isSel ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSel) ...[
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Color(0xFFD58CF7),
                                      ),
                                      const SizedBox(width: 5),
                                    ],
                                    Text(
                                      tf,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSel
                                            ? Colors.white
                                            : const Color(0x9EEBEBF5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                    const SizedBox(height: 10),

                    // Preset Confluence Shortcuts
                    Row(
                      children: [
                        _confluencePresetChip('⚡ Scalp (5m+15m)', () {
                          setModalState(() {
                            chosenTimeframes.clear();
                            chosenTimeframes.addAll(['5m', '15m']);
                          });
                        }),
                        const SizedBox(width: 6),
                        _confluencePresetChip('🎯 Intraday (15m+1H+4H)', () {
                          setModalState(() {
                            chosenTimeframes.clear();
                            chosenTimeframes.addAll(['15m', '1H', '4H']);
                          });
                        }),
                        const SizedBox(width: 6),
                        _confluencePresetChip('📈 Swing (1H+4H+1D)', () {
                          setModalState(() {
                            chosenTimeframes.clear();
                            chosenTimeframes.addAll(['1H', '4H', '1D']);
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // START AI ANALYSIS BUTTON
                    Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFBF5AF2), Color(0xFF0A84FF)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A84FF)
                                .withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            Navigator.pop(ctx);
                            final sym = chosenSymbol.isNotEmpty
                                ? chosenSymbol
                                : 'EUR/USD';
                            final tfList = chosenTimeframes.toList();

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AnalysisScreen(
                                  strategy: strat,
                                  initialSymbol: sym,
                                  initialTimeframes: tfList,
                                  initialTimeframe: tfList.first,
                                  onNavigateToChart: widget.onNavigateToChart,
                                  onSelectSymbolForChart:
                                      widget.onSelectSymbolForChart,
                                  onSelectSignalForChart:
                                      widget.onSelectSignalForChart,
                                  biquoteService: widget.biquoteService,
                                  alertManager: widget.alertManager,
                                ),
                              ),
                            ).then((_) => _loadData());
                          },
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.bolt_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Start AI Analysis',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '$chosenSymbol · ${chosenTimeframes.join(', ')}',
                                      style: const TextStyle(
                                        color: Color(0xCCFFFFFF),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _confluencePresetChip(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x17FFFFFF)),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0x9EEBEBF5),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  void _openRecentRun(RecentStrategyRun run) {
    // Open signal directly
    final strat = TradingStrategy(
      id: 'recent_${run.id}',
      name: run.strategyOrAgentName,
      description: '',
      specialists: [],
      timeframes: [run.timeframe],
      createdAt: run.timestamp,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisScreen(
          strategy: strat,
          initialSymbol: run.symbol,
          initialTimeframe: run.timeframe,
          initialSignalResult: run.signal,
          initialSpecialistSignals: run.specialistSignals,
          initialGroundingCritique: run.groundingCritique,
          onNavigateToChart: widget.onNavigateToChart,
          onSelectSymbolForChart: widget.onSelectSymbolForChart,
          onSelectSignalForChart: widget.onSelectSignalForChart,
          biquoteService: widget.biquoteService,
          alertManager: widget.alertManager,
        ),
      ),
    );
  }

  void _openAgentEditor({
    SpecialistAgentConfig? agent,
    TradingStrategy? strategy,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AgentEditorSheet(
        existingAgent: agent,
        associatedStrategy: strategy,
        availableStrategies: _strategies,
        onAgentSaved: _loadData,
        onAgentDeleted: _loadData,
      ),
    );
    _loadData();
  }

  void _showNewActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Create AI Trading System',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x2930D158),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Color(0xFF30D158),
                  ),
                ),
                title: const Text(
                  'New Specialist Agent',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Custom prompt, specialized methodology, standalone or multi-agent',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAgentEditor();
                },
              ),
              const Divider(color: Color(0x17FFFFFF), height: 1),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0x29BF5AF2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Color(0xFFBF5AF2),
                  ),
                ),
                title: const Text(
                  'New Multi-Agent Strategy',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Combine 2+ specialists with Grounding & Consolidator loops',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openStrategyBuilderSheet();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openStrategyBuilderSheet({TradingStrategy? existing}) {
    final nameCtrl = TextEditingController(
      text: existing?.name ?? 'New Confluence Strategy',
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final consolidatorCtrl = TextEditingController(
      text: existing?.consolidatorInstructions ?? '',
    );
    final selectedSpecIds = <String>{};
    if (existing != null) {
      selectedSpecIds.addAll(existing.specialists.map((s) => s.id));
    } else {
      if (_specialists.length >= 2) {
        selectedSpecIds.add(_specialists[0].id);
        selectedSpecIds.add(_specialists[1].id);
      }
    }

    final selectedTfs = existing != null
        ? List<String>.from(existing.timeframes)
        : ['15m', '4H'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final topPadding = MediaQuery.of(context).padding.top;
            final maxSheetHeight =
                MediaQuery.of(context).size.height - topPadding - 32;

            return Container(
              constraints: BoxConstraints(maxHeight: maxSheetHeight),
              margin: EdgeInsets.only(top: topPadding + 16),
              decoration: const BoxDecoration(
                color: Color(0xFF141416),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: Color(0x33FFFFFF), width: 1),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Column(
                  children: [
                    // Grab handle
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
                    // Header
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Color(0xFF4DA3FF),
                                fontSize: 17,
                              ),
                            ),
                          ),
                          Text(
                            existing != null ? 'Edit Strategy' : 'New Strategy',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final name = nameCtrl.text.trim();
                              if (name.isEmpty) return;
                              if (selectedSpecIds.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Select at least one specialist',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final chosenSpecs = _specialists
                                  .where((s) => selectedSpecIds.contains(s.id))
                                  .toList();
                              final strat = TradingStrategy(
                                id:
                                    existing?.id ??
                                    'strat_${DateTime.now().millisecondsSinceEpoch}',
                                name: name,
                                description: descCtrl.text.trim(),
                                specialists: chosenSpecs,
                                timeframes: selectedTfs,
                                createdAt:
                                    existing?.createdAt ?? DateTime.now(),
                                isDefault: existing?.isDefault ?? false,
                                consolidatorInstructions: consolidatorCtrl.text
                                    .trim(),
                              );

                              await _storage.saveStrategy(strat);
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              _loadData();
                            },
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                color: Color(0xFF4DA3FF),
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x17FFFFFF), height: 1),

                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                            'STRATEGY NAME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0x9EEBEBF5),
                              letterSpacing: 0.99,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TextField(
                              controller: nameCtrl,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'DESCRIPTION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0x9EEBEBF5),
                              letterSpacing: 0.99,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TextField(
                              controller: descCtrl,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14),
                                hintText: 'Short methodology description',
                                hintStyle: TextStyle(color: Colors.white30),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'SELECT SPECIALISTS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0x9EEBEBF5),
                              letterSpacing: 0.99,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _specialists.length,
                              separatorBuilder: (c, i) => const Divider(
                                color: Color(0x17FFFFFF),
                                height: 1,
                              ),
                              itemBuilder: (c, idx) {
                                final spec = _specialists[idx];
                                final isSel = selectedSpecIds.contains(spec.id);
                                final color = _parseHex(spec.colorHex);
                                return CheckboxListTile(
                                  value: isSel,
                                  onChanged: (v) {
                                    setModalState(() {
                                      if (v == true) {
                                        selectedSpecIds.add(spec.id);
                                      } else {
                                        selectedSpecIds.remove(spec.id);
                                      }
                                    });
                                  },
                                  activeColor: const Color(0xFFBF5AF2),
                                  title: Text(
                                    spec.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    spec.category,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'CONSOLIDATOR DIRECTIVES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0x9EEBEBF5),
                              letterSpacing: 0.99,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TextField(
                              controller: consolidatorCtrl,
                              maxLines: 3,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                hintText: 'Instructions on how the Consolidator synthesizes specialists...',
                                hintStyle: TextStyle(color: Colors.white30),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Header: "Strategies" + blue (+) button (exact replica of Strategies.dc.html)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Strategies',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.03 * 34,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: _showNewActionSheet,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFF0A84FF),
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
              ),
            ),
            const SizedBox(height: 10),

            // Tab switch: Multi-Agent Strategies vs 22+ Single Specialists
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? const Color(0xFF2C2C2E)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Center(
                            child: Text(
                              'Multi-Agent Strategies',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedTab == 0
                                    ? Colors.white
                                    : const Color(0x9EEBEBF5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? const Color(0xFF2C2C2E)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Center(
                            child: Text(
                              'Specialists (${_specialists.length})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _selectedTab == 1
                                    ? Colors.white
                                    : const Color(0x9EEBEBF5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Main scrollable area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0A84FF),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: const Color(0xFF0A84FF),
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 90),
                        children: [
                          if (_selectedTab == 0) ...[
                            // Strategies Cards List
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: _strategies
                                    .map((strat) => _buildStrategyCard(strat))
                                    .toList(),
                              ),
                            ),
                          ] else ...[
                            // Standalone Specialists List
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: _specialists
                                    .map((spec) => _buildSpecialistCard(spec))
                                    .toList(),
                              ),
                            ),
                          ],

                          const SizedBox(height: 14),

                          // SECTION: RECENT RUNS
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'RECENT RUNS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.09 * 11,
                                color: Color(0x9EEBEBF5),
                              ),
                            ),
                          ),

                          // RECENT RUNS CARD
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Column(
                                children: _recentRuns
                                    .map((run) => _buildRecentRunRow(run))
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyCard(TradingStrategy s) {
    final isHero = s.isDefault;

    // Badges based on specialists
    final badges = <Widget>[];
    for (final spec in s.specialists) {
      final name = spec.name;
      if (name.contains('SMC')) {
        badges.add(
          _badge(
            'SMC Specialist',
            const Color(0x2EBF5AF2),
            const Color(0xFFD58CF7),
          ),
        );
      } else if (name.contains('Wyckoff')) {
        badges.add(
          _badge(
            'Wyckoff Specialist',
            const Color(0x29FFD60A),
            const Color(0xFFFFD60A),
          ),
        );
      } else if (name.contains('Volume')) {
        badges.add(
          _badge(
            'Volume Profile',
            const Color(0x2930D158),
            const Color(0xFF43E06A),
          ),
        );
      } else if (name.contains('Fib')) {
        badges.add(
          _badge('Fibonacci', const Color(0x290A84FF), const Color(0xFF4DA3FF)),
        );
      } else if (name.contains('Macro')) {
        badges.add(
          _badge(
            'Macro Sentiment',
            const Color(0x2EBF5AF2),
            const Color(0xFFD58CF7),
          ),
        );
      } else {
        final c = _parseHex(spec.colorHex);
        badges.add(_badge(spec.name, c.withValues(alpha: 0.18), c));
      }
    }
    // Grounding critic is always in the pipeline
    badges.add(
      _badge(
        'Grounding Critic',
        const Color(0x2964D2FF),
        const Color(0xFF64D2FF),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isHero ? null : const Color(0xFF1C1C1E),
        gradient: isHero
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x1ABF5AF2), Color(0xFF1C1C1E)],
              )
            : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isHero ? const Color(0x99BF5AF2) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _runStrategy(s),
        onLongPress: () => _openStrategyBuilderSheet(existing: s),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  _badge(
                    s.isDefault ? 'Default' : 'Custom',
                    s.isDefault
                        ? const Color(0x2EBF5AF2)
                        : const Color(0xFF2C2C2E),
                    s.isDefault
                        ? const Color(0xFFD58CF7)
                        : const Color(0x9EEBEBF5),
                  ),
                ],
              ),
              const SizedBox(height: 3),

              // Description
              Text(
                s.description.isNotEmpty ? s.description : 'Multi-agent algorithmic pipeline with Grounding & Metareasoning.',
                style: const TextStyle(fontSize: 13, color: Color(0x9EEBEBF5)),
              ),
              const SizedBox(height: 12),

              // Specialist Badges
              Wrap(spacing: 6, runSpacing: 6, children: badges),
              const SizedBox(height: 8),

              // Timeframe Pills
              Row(
                children: s.timeframes.map((tf) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _timeframePill(tf),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialistCard(SpecialistAgentConfig spec) {
    final color = _parseHex(spec.colorHex);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(22),
      ),
      child: InkWell(
        onTap: () => _runSpecialistStandalone(spec),
        onLongPress: () => _openAgentEditor(agent: spec),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        spec.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  _badge(spec.category, color.withValues(alpha: 0.18), color),
                ],
              ),
              const SizedBox(height: 4),

              Text(
                spec.description.isNotEmpty
                    ? spec.description
                    : spec.systemPrompt.replaceAll('\n', ' ').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0x9EEBEBF5),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      _badge(
                        'Standalone',
                        const Color(0x2930D158),
                        const Color(0xFF43E06A),
                      ),
                      _badge(
                        'Grounding Critic',
                        const Color(0x2964D2FF),
                        const Color(0xFF64D2FF),
                      ),
                    ],
                  ),
                  Row(
                    children: spec.timeframes.map((tf) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: _timeframePill(tf),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRunRow(RecentStrategyRun run) {
    final isBuy = run.direction == SignalDirection.buy;
    final isSell = run.direction == SignalDirection.sell;
    final badgeBg = isBuy
        ? const Color(0x2930D158)
        : (isSell ? const Color(0x29FF453A) : const Color(0xFF2C2C2E));
    final badgeFg = isBuy
        ? const Color(0xFF43E06A)
        : (isSell ? const Color(0xFFFF6961) : const Color(0x9EEBEBF5));

    final timeStr = _formatTimestamp(run.timestamp);

    return InkWell(
      onTap: () => _openRecentRun(run),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x17FFFFFF), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Direction Badge (48px wide)
            Container(
              width: 48,
              height: 22,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(
                  run.direction.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeFg,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Symbol & Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.symbol,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${run.strategyOrAgentName} · ${run.timeframe}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0x9EEBEBF5),
                    ),
                  ),
                ],
              ),
            ),

            // Score & Time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  run.score.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0x9EEBEBF5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays >= 1) {
      return diff.inDays == 1 ? 'Yesterday' : '${diff.inDays}d ago';
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _badge(String text, Color bg, Color fg) {
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }

  Widget _timeframePill(String tf) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Center(
        child: Text(
          tf,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0x9EEBEBF5),
          ),
        ),
      ),
    );
  }
}
