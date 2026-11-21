import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/alert_manager.dart';
import '../services/market_data_api.dart';

class FinancialNewsScreen extends StatefulWidget {
  final ValueChanged<String>? onSelectSymbol;
  final AlertManager? alertManager;

  const FinancialNewsScreen({
    super.key,
    this.onSelectSymbol,
    this.alertManager,
  });

  @override
  State<FinancialNewsScreen> createState() => _FinancialNewsScreenState();
}

class _FinancialNewsScreenState extends State<FinancialNewsScreen> {
  // Category Filter Chips: All, Forex, Crypto, Commodities, Central Banks
  int _selectedCategoryIndex = 0;
  final List<String> _categories = [
    'All',
    'Forex',
    'Crypto',
    'Commodities',
    'Central Banks',
  ];

  bool _loading = true;
  String? _error;
  List<NewsArticle> _articles = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final articles = await MarketDataApi.getNews(limit: 30);
      if (mounted) {
        setState(() {
          _articles = articles;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes < 1 ? 1 : diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  _NewsSentiment _classifySentiment(String title) {
    final t = title.toUpperCase();
    if (t.contains('SURGE') ||
        t.contains('RALLY') ||
        t.contains('JUMP') ||
        t.contains('BULLISH') ||
        t.contains('GAINS') ||
        t.contains('RECORD') ||
        t.contains('CLIMB') ||
        t.contains('EXTENDS') ||
        t.contains('FIRMS')) {
      return _NewsSentiment(
        label: 'Bullish',
        bg: const Color(0x2930D158),
        fg: const Color(0xFF43E06A),
      );
    }
    if (t.contains('SLIP') ||
        t.contains('FALL') ||
        t.contains('DROP') ||
        t.contains('CRASH') ||
        t.contains('BEARISH') ||
        t.contains('DOWN') ||
        t.contains('SINK') ||
        t.contains('LOSS') ||
        t.contains('DECLINE')) {
      return _NewsSentiment(
        label: 'Bearish',
        bg: const Color(0x29FF453A),
        fg: const Color(0xFFFF6961),
      );
    }
    return _NewsSentiment(
      label: 'Neutral',
      bg: const Color(0xFF2C2C2E),
      fg: const Color(0x9EEBEBF5),
    );
  }

  String _inferCategory(String text) {
    final t = text.toUpperCase();
    if (t.contains('FED') ||
        t.contains('RATE') ||
        t.contains('ECB') ||
        t.contains('POWELL') ||
        t.contains('CENTRAL BANK')) {
      return 'Central Banks';
    }
    if (t.contains('BITCOIN') ||
        t.contains('CRYPTO') ||
        t.contains('ETH') ||
        t.contains('SOL') ||
        t.contains('ETF')) {
      return 'Crypto';
    }
    if (t.contains('GOLD') ||
        t.contains('OIL') ||
        t.contains('SILVER') ||
        t.contains('COMMODIT') ||
        t.contains('CRUDE') ||
        t.contains('XAU')) {
      return 'Commodities';
    }
    return 'Forex';
  }

  List<NewsArticle> _getFilteredArticles() {
    if (_selectedCategoryIndex == 0) return _articles;
    final cat = _categories[_selectedCategoryIndex];

    return _articles.where((a) {
      final inferred = _inferCategory('${a.title} ${a.description}');
      return inferred.toLowerCase() == cat.toLowerCase();
    }).toList();
  }

  List<String> _extractRelatedSymbols(String text) {
    final upper = text.toUpperCase();
    final detected = <String>{};
    final candidates = {
      'EURUSD': ['EUR/USD', 'EURUSD', 'EURO', 'ECB'],
      'GBPUSD': ['GBP/USD', 'GBPUSD', 'POUND', 'BOE', 'STERLING'],
      'USDJPY': ['USD/JPY', 'USDJPY', 'YEN', 'BOJ'],
      'XAUUSD': ['GOLD', 'XAUUSD', 'BULLION'],
      'BTCUSD': ['BITCOIN', 'BTCUSD', 'CRYPTO'],
      'ETHUSD': ['ETHEREUM', 'ETHUSD', 'ETHER'],
      'AUDUSD': ['AUD/USD', 'AUDUSD', 'AUSSIE', 'RBA'],
      'USDCAD': ['USD/CAD', 'USDCAD', 'LOONIE', 'BOC'],
    };

    for (final entry in candidates.entries) {
      for (final keyword in entry.value) {
        if (upper.contains(keyword)) {
          detected.add(entry.key);
          break;
        }
      }
    }

    if (detected.isEmpty) {
      detected.addAll(['EURUSD', 'GBPUSD', 'USDJPY']);
    }

    return detected.toList();
  }

  void _showArticleModal(NewsArticle item) {
    final dateStr = DateFormat('MMM dd, yyyy • HH:mm')
        .format(item.publishedDate.toLocal());
    final related = _extractRelatedSymbols('${item.title} ${item.description}');
    final sentiment = _classifySentiment(item.title);
    final category = _inferCategory('${item.title} ${item.description}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: sentiment.bg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        sentiment.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sentiment.fg,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0x9EEBEBF5),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0x57EBEBF5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  height: 1.25,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              if (item.description.isNotEmpty)
                Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xCCEBEBF5),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'RELATED INSTRUMENTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.99,
                  color: Color(0x9EEBEBF5),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: related.map((pair) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF2C2C2E),
                    label: Text(
                      pair,
                      style: const TextStyle(
                        color: Color(0xFF0A84FF),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (widget.onSelectSymbol != null) {
                        widget.onSelectSymbol!(pair);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (widget.onSelectSymbol != null && related.isNotEmpty) {
                      widget.onSelectSymbol!(related.first);
                    }
                  },
                  icon: const Icon(Icons.show_chart_rounded, size: 18),
                  label: Text(
                    'OPEN ${related.isNotEmpty ? related.first : "CHART"}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A84FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final filtered = _getFilteredArticles();

    final NewsArticle? heroArticle = filtered.isNotEmpty
        ? filtered.first
        : null;
    final List<NewsArticle> remainingArticles = filtered.length > 1
        ? filtered.skip(1).toList()
        : [];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            const SizedBox(height: 6),
            // Header: Title "News" + "• Live"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (canPop) ...[
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                        const Text(
                          'News',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.03 * 34,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 64),
                      child: Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x2930D158),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF30D158),
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF43E06A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0A84FF)),
              ),
            if (_error != null && _articles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
                child: Text(
                  'Live news sync: $_error',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0x57EBEBF5),
                  ),
                ),
              ),

            // Category Filter Chips: All | Forex | Crypto | Commodities | Central Banks
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, idx) {
                    final isSelected = _selectedCategoryIndex == idx;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategoryIndex = idx;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: Text(
                            _categories[idx],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.black
                                  : const Color(0x9EEBEBF5),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
                children: [
                  // FEATURED HERO NEWS CARD
                  if (heroArticle != null)
                    GestureDetector(
                      onTap: () => _showArticleModal(heroArticle),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            stops: [0.0, 0.7],
                            colors: [Color(0xFF16314F), Color(0xFF0B0F18)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0x2E64D2FF)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Top-right blue radial glow
                            Positioned(
                              right: -30,
                              top: -30,
                              width: 140,
                              height: 140,
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Color(0x5964D2FF),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Builder(
                                        builder: (context) {
                                          final heroCat = _inferCategory(
                                            '${heroArticle.title} ${heroArticle.description}',
                                          );
                                          final heroSent = _classifySentiment(
                                            heroArticle.title,
                                          );
                                          return Row(
                                            children: [
                                              Container(
                                                height: 22,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0x290A84FF,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    heroCat,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF4DA3FF),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                height: 22,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: heroSent.bg,
                                                  borderRadius:
                                                      BorderRadius.circular(11),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    heroSent.label,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: heroSent.fg,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    heroArticle.title,
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5,
                                      height: 1.22,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text(
                                        heroArticle.publisher.isNotEmpty
                                            ? heroArticle.publisher
                                            : 'Macro Wire',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0x9EEBEBF5),
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                        child: Text(
                                          '·',
                                          style: TextStyle(
                                            color: Color(0x9EEBEBF5),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _timeAgo(heroArticle.publishedDate),
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
                          ],
                        ),
                      ),
                    ),
                  if (heroArticle != null) const SizedBox(height: 12),
                  if (filtered.isEmpty && !_loading)
                    Container(
                      margin: const EdgeInsets.only(top: 40),
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      child: Text(
                        'No news stories found under ${_categories[_selectedCategoryIndex]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0x9EEBEBF5),
                        ),
                      ),
                    ),

                  // REGULAR NEWS ITEMS LIST
                  ...remainingArticles.asMap().entries.map((entry) {
                    final item = entry.value;
                    final sentiment = _classifySentiment(item.title);
                    final cat = _inferCategory(
                      '${item.title} ${item.description}',
                    );

                    return InkWell(
                      onTap: () => _showArticleModal(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Color(0x17FFFFFF),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sentiment.bg,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Center(
                                    child: Text(
                                      sentiment.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: sentiment.fg,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2C2C2E),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Center(
                                    child: Text(
                                      cat,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x9EEBEBF5),
                                      ),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _timeAgo(item.publishedDate),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0x57EBEBF5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.24,
                                height: 1.3,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.publisher.isNotEmpty
                                  ? item.publisher
                                  : 'Market Desk',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0x9EEBEBF5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsSentiment {
  final String label;
  final Color bg;
  final Color fg;

  _NewsSentiment({required this.label, required this.bg, required this.fg});
}
