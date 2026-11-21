import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/market_models.dart';
import '../services/favorites_service.dart';
import '../services/market_data_api.dart';
import '../theme/app_theme.dart';

class InstrumentSearchSheet extends StatefulWidget {
  final String currentSymbol;
  final ValueChanged<String> onSelectSymbol;
  final Map<String, BiquoteTick> ticks;

  const InstrumentSearchSheet({
    super.key,
    required this.currentSymbol,
    required this.onSelectSymbol,
    this.ticks = const {},
  });

  static Future<void> show(
    BuildContext context, {
    required String currentSymbol,
    required ValueChanged<String> onSelectSymbol,
    Map<String, BiquoteTick> ticks = const {},
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InstrumentSearchSheet(
        currentSymbol: currentSymbol,
        onSelectSymbol: onSelectSymbol,
        ticks: ticks,
      ),
    );
  }

  @override
  State<InstrumentSearchSheet> createState() => _InstrumentSearchSheetState();
}

class _InstrumentSearchSheetState extends State<InstrumentSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FavoritesService _favService = FavoritesService();

  List<BiquoteInstrument> _allInstruments = [];
  String _selectedCategory = 'Favorites';
  String _searchQuery = '';

  static const List<String> _categories = [
    'Favorites',
    'Forex',
    'Metals',
    'Crypto',
    'Indices',
    'Commodities',
  ];

  @override
  void initState() {
    super.initState();
    _favService.addListener(_onFavoritesChanged);
    _searchController.addListener(_onSearchChanged);
    _loadInstruments();
  }

  @override
  void dispose() {
    _favService.removeListener(_onFavoritesChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _loadInstruments() async {
    // Immediate fallback instruments so catalog renders instantly with 0ms delay
    _allInstruments = _getCuratedFallbackInstruments();
    setState(() {});

    try {
      final list = await MarketDataApi.getAllSymbols();
      if (mounted && list.isNotEmpty) {
        setState(() {
          _allInstruments = list;
        });
      }
    } catch (_) {}
  }

  List<BiquoteInstrument> _getFilteredList() {
    final query = _searchQuery;
    final cat = _selectedCategory;

    return _allInstruments.where((inst) {
      // 1. Search Query Match
      if (query.isNotEmpty) {
        final symbolMatch = inst.symbol.toLowerCase().contains(query);
        final descMatch = inst.description.toLowerCase().contains(query);
        final displayMatch = _getSymbolDisplayName(inst.symbol)
            .toLowerCase()
            .contains(query);
        if (!symbolMatch && !descMatch && !displayMatch) return false;
      }

      // 2. Category Match
      if (cat == 'Favorites') {
        return _favService.isFavorite(inst.symbol);
      } else if (cat == 'Forex') {
        return inst.type.toLowerCase() == 'forex';
      } else if (cat == 'Metals') {
        final s = inst.symbol.toUpperCase();
        return s.startsWith('XAU') || s.startsWith('XAG') || s == 'COPPER';
      } else if (cat == 'Crypto') {
        return inst.type.toLowerCase() == 'crypto';
      } else if (cat == 'Indices') {
        return inst.type.toLowerCase() == 'index' ||
            inst.type.toLowerCase() == 'indices';
      } else if (cat == 'Commodities') {
        final s = inst.symbol.toUpperCase();
        return inst.type.toLowerCase() == 'commodity' &&
            !s.startsWith('XAU') &&
            !s.startsWith('XAG');
      }

      return true;
    }).toList();
  }

  // ─── SYMBOL PRESENTATION MAPPERS (Matching exact Symbols.dc.html design) ──
  String _getSymbolDisplayName(String symbol) {
    final s = symbol.toUpperCase();
    switch (s) {
      case 'EURUSD':
        return 'EUR/USD';
      case 'GBPUSD':
        return 'GBP/USD';
      case 'USDJPY':
        return 'USD/JPY';
      case 'XAUUSD':
        return 'Gold';
      case 'XAGUSD':
        return 'Silver';
      case 'BTCUSD':
        return 'Bitcoin';
      case 'ETHUSD':
        return 'Ethereum';
      case 'SOLUSD':
        return 'Solana';
      case 'US500':
        return 'S&P 500';
      case 'US30':
        return 'Dow Jones';
      case 'USTEC':
      case 'NAS100':
        return 'Nasdaq 100';
      case 'USOIL':
        return 'WTI Oil';
      case 'UKOIL':
        return 'Brent Crude';
      default:
        if (s.length == 6 && !s.contains('/')) {
          return '${s.substring(0, 3)}/${s.substring(3)}';
        }
        return s;
    }
  }

  String _getSymbolCategorySubtitle(String symbol, String originalType) {
    final s = symbol.toUpperCase();
    switch (s) {
      case 'EURUSD':
        return 'Forex Major · EURUSD';
      case 'GBPUSD':
        return 'Forex Major · GBPUSD';
      case 'USDJPY':
        return 'Forex Major · USDJPY';
      case 'AUDUSD':
        return 'Forex Major · AUDUSD';
      case 'USDCAD':
        return 'Forex Major · USDCAD';
      case 'USDCHF':
        return 'Forex Major · USDCHF';
      case 'NZDUSD':
        return 'Forex Major · NZDUSD';
      case 'XAUUSD':
        return 'Precious Metals · XAUUSD';
      case 'XAGUSD':
        return 'Precious Metals · XAGUSD';
      case 'BTCUSD':
        return 'Crypto · BTCUSD';
      case 'ETHUSD':
        return 'Crypto · ETHUSD';
      case 'SOLUSD':
        return 'Crypto · SOLUSD';
      case 'US500':
        return 'Index CFD · US500';
      case 'US30':
        return 'Index CFD · US30';
      case 'USTEC':
      case 'NAS100':
        return 'Index CFD · NAS100';
      case 'USOIL':
        return 'Commodities · USOIL';
      case 'UKOIL':
        return 'Commodities · UKOIL';
      default:
        if (originalType.toLowerCase() == 'forex') {
          return 'Forex Cross · $s';
        }
        return '$originalType · $s';
    }
  }

  String _getSymbolBadgeInitials(String symbol) {
    final s = symbol.toUpperCase();
    switch (s) {
      case 'EURUSD':
        return 'EU';
      case 'GBPUSD':
        return 'GB';
      case 'USDJPY':
        return 'JP';
      case 'AUDUSD':
        return 'AU';
      case 'USDCAD':
        return 'CA';
      case 'USDCHF':
        return 'CH';
      case 'NZDUSD':
        return 'NZ';
      case 'XAUUSD':
        return 'XAU';
      case 'XAGUSD':
        return 'XAG';
      case 'BTCUSD':
        return 'BTC';
      case 'ETHUSD':
        return 'ETH';
      case 'SOLUSD':
        return 'SOL';
      case 'US500':
        return '500';
      case 'US30':
        return 'DOW';
      case 'USTEC':
      case 'NAS100':
        return 'NAS';
      case 'USOIL':
      case 'UKOIL':
        return 'OIL';
      default:
        if (s.length >= 3) return s.substring(0, 3);
        return s;
    }
  }

  // Badge background & foreground tint colors matching Symbols.dc.html line 71
  _BadgeTint _getBadgeTint(String symbol, String type) {
    final s = symbol.toUpperCase();
    final t = type.toLowerCase();

    // Metals / Commodities (Amber)
    if (s.startsWith('XAU') ||
        s.startsWith('XAG') ||
        s == 'USOIL' ||
        s == 'UKOIL' ||
        t == 'commodity') {
      return _BadgeTint(
        bg: const Color.fromRGBO(255, 159, 10, 0.18),
        fg: const Color(0xFFFFB340),
      );
    }

    // Crypto (Purple)
    if (t == 'crypto' ||
        s.startsWith('BTC') ||
        s.startsWith('ETH') ||
        s.startsWith('SOL')) {
      return _BadgeTint(
        bg: const Color.fromRGBO(191, 90, 242, 0.18),
        fg: const Color(0xFFD58CF7),
      );
    }

    // Indices (Teal)
    if (t == 'index' ||
        t == 'indices' ||
        s == 'US500' ||
        s == 'US30' ||
        s == 'USTEC' ||
        s == 'GER40') {
      return _BadgeTint(
        bg: const Color.fromRGBO(100, 210, 255, 0.16),
        fg: const Color(0xFF64D2FF),
      );
    }

    // Forex / Default (Electric Blue)
    return _BadgeTint(
      bg: const Color.fromRGBO(10, 132, 255, 0.18),
      fg: const Color(0xFF4DA3FF),
    );
  }

  // Deterministic seed for sparkline variation
  int _getSymbolSeed(String symbol) {
    int hash = 7;
    for (int i = 0; i < symbol.length; i++) {
      hash = hash * 31 + symbol.codeUnitAt(i);
    }
    return hash.abs() % 1000;
  }

  // Fallback prices matching design mockup
  _PriceInfo _getPriceInfo(String symbol, int digits) {
    final tick = widget.ticks[symbol];
    if (tick != null && tick.mid > 0) {
      final isBull = tick.dayDiffPercent >= 0;
      final sign = isBull ? '+' : '';
      final chgStr = '$sign${tick.dayDiffPercent.toStringAsFixed(2)}%';

      String priceStr;
      if (symbol.toUpperCase().contains('JPY')) {
        priceStr = tick.mid.toStringAsFixed(3);
      } else if (symbol.toUpperCase().contains('BTC')) {
        priceStr = tick.mid
            .toStringAsFixed(0)
            .replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (m) => '${m[1]} ',
            );
      } else if (digits <= 2) {
        priceStr = tick.mid.toStringAsFixed(2);
      } else {
        priceStr = tick.mid.toStringAsFixed(digits);
      }

      return _PriceInfo(price: priceStr, change: chgStr, isBullish: isBull);
    }

    // Default static mock prices matching Symbols.dc.html
    final s = symbol.toUpperCase();
    switch (s) {
      case 'EURUSD':
        return _PriceInfo(price: '1.08548', change: '+0.12%', isBullish: true);
      case 'GBPUSD':
        return _PriceInfo(price: '1.30512', change: '+0.21%', isBullish: true);
      case 'USDJPY':
        return _PriceInfo(price: '155.302', change: '−0.18%', isBullish: false);
      case 'XAUUSD':
        return _PriceInfo(price: '2650.40', change: '−0.38%', isBullish: false);
      case 'BTCUSD':
        return _PriceInfo(price: '67 240', change: '+1.42%', isBullish: true);
      case 'US500':
        return _PriceInfo(price: '5842.3', change: '+0.31%', isBullish: true);
      case 'USOIL':
        return _PriceInfo(price: '71.82', change: '−0.64%', isBullish: false);
      case 'AUDUSD':
        return _PriceInfo(price: '0.66540', change: '+0.08%', isBullish: true);
      case 'USDCAD':
        return _PriceInfo(price: '1.37890', change: '−0.14%', isBullish: false);
      case 'USDCHF':
        return _PriceInfo(price: '0.86542', change: '+0.05%', isBullish: true);
      case 'ETHUSD':
        return _PriceInfo(price: '2640.80', change: '+2.14%', isBullish: true);
      default:
        return _PriceInfo(price: '1.00000', change: '+0.00%', isBullish: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.90;
    final filtered = _getFilteredList();

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0E), // Exact OLED background from Symbols.dc.html
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        border: Border(
          top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.10), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.60),
            blurRadius: 60,
            offset: Offset(0, -20),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle pill matching Symbols.dc.html line 31
          Center(
            child: Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3C),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Header Row matching Symbols.dc.html line 32-35
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Symbols',
                style: AppTheme.sans(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: Colors.white,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Close',
                    style: AppTheme.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Search Bar matching Symbols.dc.html lines 36-39
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Color.fromRGBO(235, 235, 245, 0.62),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: AppTheme.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search 120+ instruments',
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: Color.fromRGBO(235, 235, 245, 0.34),
                        letterSpacing: -0.2,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () => _searchController.clear(),
                    child: const Icon(
                      Icons.cancel_rounded,
                      size: 18,
                      color: Color.fromRGBO(235, 235, 245, 0.62),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Horizontal Category Chips matching Symbols.dc.html lines 40-42 (.chip)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat,
                      style: AppTheme.sans(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isSelected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Section Counter Header matching Symbols.dc.html line 43
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 2),
            child: Text(
              '${_selectedCategory.toUpperCase()} · ${filtered.length}',
              style: AppTheme.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: const Color.fromRGBO(235, 235, 245, 0.62),
              ),
            ),
          ),

          // Instruments List matching Symbols.dc.html lines 44-52
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: Color.fromRGBO(235, 235, 245, 0.34),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No instruments found',
                          style: AppTheme.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color.fromRGBO(235, 235, 245, 0.62),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 30),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildInstrumentRow(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ─── INSTRUMENT ROW COMPONENT (.rw in Symbols.dc.html) ───────────────────
  Widget _buildInstrumentRow(BiquoteInstrument inst) {
    final isFav = _favService.isFavorite(inst.symbol);
    final displayName = _getSymbolDisplayName(inst.symbol);
    final subtitle = _getSymbolCategorySubtitle(inst.symbol, inst.type);
    final initials = _getSymbolBadgeInitials(inst.symbol);
    final tint = _getBadgeTint(inst.symbol, inst.type);
    final priceInfo = _getPriceInfo(inst.symbol, inst.digits);
    final seed = _getSymbolSeed(inst.symbol);

    final trendColor = priceInfo.isBullish
        ? const Color(0xFF43E06A)
        : const Color(0xFFFF6961);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onSelectSymbol(inst.symbol);
        Navigator.of(context).pop();
      },
      splashColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Container(
        height: 66,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color.fromRGBO(255, 255, 255, 0.09),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Star Icon Button
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _favService.toggleFavorite(inst.symbol);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 20,
                  color: isFav
                      ? const Color(0xFFFF9F0A)
                      : const Color.fromRGBO(235, 235, 245, 0.30),
                ),
              ),
            ),

            // Badge Tile (.tile)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: AppTheme.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: tint.fg,
                  letterSpacing: -0.2,
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Name & Category Subtitle
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: AppTheme.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color.fromRGBO(235, 235, 245, 0.62),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Sparkline Wave (56x22)
            SizedBox(
              width: 56,
              height: 22,
              child: CustomPaint(
                painter: _SparklinePainter(
                  seed: seed,
                  isBullish: priceInfo.isBullish,
                  color: trendColor,
                ),
              ),
            ),

            const SizedBox(width: 10),

            // Price & Change Percentage Column (width: 78px, right-aligned)
            SizedBox(
              width: 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    priceInfo.price,
                    style: AppTheme.mono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    priceInfo.change,
                    style: AppTheme.mono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: trendColor,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CURATED FALLBACK INSTRUMENTS FOR ZERO-DELAY INSTANT MOUNT ────────────
  List<BiquoteInstrument> _getCuratedFallbackInstruments() {
    return [
      BiquoteInstrument(
        symbol: 'EURUSD',
        description: 'Euro vs US Dollar',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'GBPUSD',
        description: 'Great Britain Pound vs US Dollar',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'USDJPY',
        description: 'US Dollar vs Japanese Yen',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 3,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'XAUUSD',
        description: 'Gold vs US Dollar',
        exchange: 'COMEX',
        type: 'Commodity',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'BTCUSD',
        description: 'Bitcoin vs US Dollar',
        exchange: 'CRYPTO',
        type: 'Crypto',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'US500',
        description: 'US SPX 500 Index',
        exchange: 'INDEX',
        type: 'Index',
        digits: 1,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'USOIL',
        description: 'WTI Crude Oil',
        exchange: 'NYMEX',
        type: 'Commodity',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'AUDUSD',
        description: 'Australian Dollar vs US Dollar',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'USDCAD',
        description: 'US Dollar vs Canadian Dollar',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'USDCHF',
        description: 'US Dollar vs Swiss Franc',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'NZDUSD',
        description: 'New Zealand Dollar vs US Dollar',
        exchange: 'FOREX',
        type: 'Forex',
        digits: 5,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'ETHUSD',
        description: 'Ethereum vs US Dollar',
        exchange: 'CRYPTO',
        type: 'Crypto',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'SOLUSD',
        description: 'Solana vs US Dollar',
        exchange: 'CRYPTO',
        type: 'Crypto',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'XAGUSD',
        description: 'Silver vs US Dollar',
        exchange: 'COMEX',
        type: 'Commodity',
        digits: 3,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'US30',
        description: 'Dow Jones 30 Index',
        exchange: 'INDEX',
        type: 'Index',
        digits: 1,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'USTEC',
        description: 'Nasdaq 100 Index',
        exchange: 'INDEX',
        type: 'Index',
        digits: 1,
        isActive: true,
        hasData: true,
      ),
      BiquoteInstrument(
        symbol: 'UKOIL',
        description: 'Brent Crude Oil',
        exchange: 'ICE',
        type: 'Commodity',
        digits: 2,
        isActive: true,
        hasData: true,
      ),
    ];
  }
}

// ─── SPARKLINE PAINTER (Exact algorithm matching Symbols.dc.html line 60-66) ─
class _SparklinePainter extends CustomPainter {
  final int seed;
  final bool isBullish;
  final Color color;

  _SparklinePainter({
    required this.seed,
    required this.isBullish,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Deterministic random walk matching Symbols.dc.html
    int s = seed == 0 ? 1 : seed;
    double random() {
      s = (s * 16807) % 2147483647;
      return s / 2147483647.0;
    }

    double v = 11.0;
    final List<double> pts = [];
    final bias = isBullish ? 0.42 : 0.58;

    for (int i = 0; i < 14; i++) {
      v += (random() - bias) * 4.0;
      pts.add(v);
    }

    double mn = pts.reduce(min);
    double mx = pts.reduce(max);
    if (mx == mn) mx += 1.0;

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = 1.0 + (i * (size.width - 2.0) / (pts.length - 1));
      final y =
          (size.height - 2.0) -
          ((pts[i] - mn) / (mx - mn) * (size.height - 4.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.seed != seed ||
        oldDelegate.isBullish != isBullish ||
        oldDelegate.color != color;
  }
}

// ─── HELPER DATA CLASSES ───────────────────────────────────────────────────
class _BadgeTint {
  final Color bg;
  final Color fg;
  _BadgeTint({required this.bg, required this.fg});
}

class _PriceInfo {
  final String price;
  final String change;
  final bool isBullish;
  _PriceInfo({
    required this.price,
    required this.change,
    required this.isBullish,
  });
}
