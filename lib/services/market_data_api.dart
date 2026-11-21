import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ── Models ──────────────────────────────────────────────────────────────────

class MarketMover {
  final String symbol;
  final String description;
  final double lastPrice;
  final double changePercent;
  final double changeAmount;

  MarketMover({
    required this.symbol,
    required this.description,
    required this.lastPrice,
    required this.changePercent,
    required this.changeAmount,
  });

  factory MarketMover.fromJson(Map<String, dynamic> j) => MarketMover(
    symbol: j['symbol']?.toString() ?? '',
    description: j['name']?.toString() ?? j['description']?.toString() ?? '',
    lastPrice: (j['lastPrice'] as num?)?.toDouble() ?? 0.0,
    changePercent: (j['changePercent'] as num?)?.toDouble() ?? 0.0,
    changeAmount: (j['changeAmount'] as num?)?.toDouble() ?? 0.0,
  );
}

class MostActive {
  final String symbol;
  final String description;
  final double high;
  final double low;
  final double rangePercent;

  MostActive({
    required this.symbol,
    required this.description,
    required this.high,
    required this.low,
    required this.rangePercent,
  });

  factory MostActive.fromJson(Map<String, dynamic> j) => MostActive(
    symbol: j['symbol']?.toString() ?? '',
    description: j['name']?.toString() ?? j['description']?.toString() ?? '',
    high: (j['high'] as num?)?.toDouble() ?? 0.0,
    low: (j['low'] as num?)?.toDouble() ?? 0.0,
    rangePercent:
        (j['rangePercent'] as num?)?.toDouble() ??
        (j['changePercent'] as num?)?.toDouble() ??
        0.0,
  );
}

class CalendarEvent {
  final String id;
  final String name;
  final DateTime time;
  final String countryCode;
  final String currency;
  final String importance;
  final String type;
  final double? actual;
  final double? forecast;
  final double? previous;
  final String? unit;
  final String? multiplier;
  final String timeMode;

  CalendarEvent({
    required this.id,
    required this.name,
    required this.time,
    required this.countryCode,
    required this.currency,
    required this.importance,
    required this.type,
    this.actual,
    this.forecast,
    this.previous,
    this.unit,
    this.multiplier,
    required this.timeMode,
  });

  static double? _safeDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val.replaceAll(RegExp(r'[^0-9.-]'), ''));
    }
    return null;
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    time: DateTime.tryParse(j['time']?.toString() ?? '') ?? DateTime.now(),
    countryCode: j['countryCode']?.toString() ?? '',
    currency: j['currency']?.toString() ?? '',
    importance: j['importance']?.toString() ?? 'low',
    type: j['type']?.toString() ?? 'event',
    actual: _safeDouble(j['actual']),
    forecast: _safeDouble(j['forecast']),
    previous: _safeDouble(j['previous']),
    unit: j['unit']?.toString(),
    multiplier: j['multiplier']?.toString(),
    timeMode: j['timeMode']?.toString() ?? 'exact',
  );
}

class NewsArticle {
  final String title;
  final String description;
  final String url;
  final String publisher;
  final DateTime publishedDate;
  final String? imageUrl;

  NewsArticle({
    required this.title,
    required this.description,
    required this.url,
    required this.publisher,
    required this.publishedDate,
    this.imageUrl,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> j) => NewsArticle(
    title: j['title'] ?? '',
    description: j['description'] ?? '',
    url: j['url'] ?? '',
    publisher: j['publisher'] ?? '',
    publishedDate:
        DateTime.tryParse(j['publishedDate'] ?? '') ?? DateTime.now(),
    imageUrl: j['imageUrl'],
  );
}

class TickData {
  final String symbol;
  final String description;
  final double mid;
  final double bid;
  final double ask;
  final double dayDiffPercent;
  final double high;
  final double low;
  final int digits;

  TickData({
    required this.symbol,
    required this.description,
    required this.mid,
    required this.bid,
    required this.ask,
    required this.dayDiffPercent,
    required this.high,
    required this.low,
    required this.digits,
  });

  factory TickData.fromJson(Map<String, dynamic> j) {
    final rawDiff = (j['dayDiffPercent'] as num?)?.toDouble() ?? 0.0;
    final dir = j['direction']?.toString().toUpperCase();
    final signedDiff = dir == 'DOWN'
        ? -rawDiff.abs()
        : (dir == 'UP' ? rawDiff.abs() : rawDiff);
    return TickData(
      symbol: j['symbol'] ?? '',
      description: j['description'] ?? '',
      mid: (j['mid'] as num?)?.toDouble() ?? 0.0,
      bid: (j['bid'] as num?)?.toDouble() ?? 0.0,
      ask: (j['ask'] as num?)?.toDouble() ?? 0.0,
      dayDiffPercent: signedDiff,
      high: (j['high'] as num?)?.toDouble() ?? 0.0,
      low: (j['low'] as num?)?.toDouble() ?? 0.0,
      digits: (j['digits'] as num?)?.toInt() ?? 5,
    );
  }
}

// ── API Service ──────────────────────────────────────────────────────────────

class MarketDataApi {
  static const String _base = 'https://biquote.io';
  static const String _directBase = 'https://142.132.248.240';

  static final http.Client _client = http.Client();
  static final HttpClient _ioClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 4);
    return client;
  }();

  /// Resilient JSON fetcher: queries Biquote API with fallback to direct IP
  /// for networks/emulators with DNS resolution bottlenecks.
  static Future<dynamic> _fetchJson(String pathAndQuery) async {
    // 1. Try primary domain first
    try {
      final uri = Uri.parse('$_base$pathAndQuery');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    // 2. Direct-IP Fallback with Host header for environments with DNS timeouts
    try {
      final uri = Uri.parse('$_directBase$pathAndQuery');
      final req = await _ioClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      req.headers.set('Host', 'biquote.io');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        return jsonDecode(body);
      }
    } catch (_) {}

    return null;
  }

  static Future<List<MarketMover>> getGainers({
    String type = 'Forex',
    int limit = 15,
  }) async {
    final decoded = await _fetchJson(
      '/api/market/gainers?limit=$limit&type=$type',
    );
    if (decoded != null) {
      final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
      return list
          .map((e) => MarketMover.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<List<MarketMover>> getLosers({
    String type = 'Forex',
    int limit = 15,
  }) async {
    final decoded = await _fetchJson(
      '/api/market/losers?limit=$limit&type=$type',
    );
    if (decoded != null) {
      final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
      return list
          .map((e) => MarketMover.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<List<MostActive>> getMostActive({
    String type = 'Forex',
    int limit = 15,
  }) async {
    final decoded = await _fetchJson(
      '/api/market/most-active?limit=$limit&type=$type',
    );
    if (decoded != null) {
      final list = decoded is List ? decoded : (decoded['data'] as List? ?? []);
      return list
          .map((e) => MostActive.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static Future<List<CalendarEvent>> getCalendar({
    String countries = 'US,EU,GB,JP',
    String importance = 'medium',
  }) async {
    final path =
        '/api/calendar/upcoming?limit=50&countries=${Uri.encodeComponent(countries)}&importance=$importance';
    final decoded = await _fetchJson(path);
    if (decoded != null) {
      final list = decoded is List
          ? decoded
          : (decoded['value'] as List? ?? decoded['data'] as List? ?? []);
      final events = <CalendarEvent>[];
      for (final e in list) {
        try {
          events.add(CalendarEvent.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
      return events;
    }
    return [];
  }

  static Future<List<NewsArticle>> getNews({int limit = 20}) async {
    final decoded = await _fetchJson(
      '/api/news/market?maxResults=$limit&language=en',
    );
    if (decoded != null) {
      final list = decoded is List
          ? decoded
          : (decoded['value'] as List? ?? decoded['data'] as List? ?? []);
      return list
          .map((e) => NewsArticle.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Batch tick data for a list of symbols from Biquote API.
  static Future<Map<String, TickData>> getBatchTicks(
    List<String> symbols,
  ) async {
    final query = symbols.map((s) => 'symbols=$s').join('&');
    final decoded = await _fetchJson('/api/latest?$query');
    if (decoded is Map<String, dynamic>) {
      return decoded.map(
        (k, v) => MapEntry(k, TickData.fromJson(v as Map<String, dynamic>)),
      );
    }
    return {};
  }

  static List<BiquoteInstrument>? _cachedInstruments;

  /// Fetches all active instruments from Biquote (Forex, Crypto, Metals, Stocks, Indices).
  static Future<List<BiquoteInstrument>> getAllSymbols({
    bool forceRefresh = false,
    int quotedWithinDays = 7,
  }) async {
    if (!forceRefresh &&
        _cachedInstruments != null &&
        _cachedInstruments!.isNotEmpty) {
      return _cachedInstruments!;
    }
    try {
      final decoded = await _fetchJson(
        '/api/symbols?quotedWithinDays=$quotedWithinDays',
      );
      if (decoded != null) {
        final list = decoded is List
            ? decoded
            : (decoded['value'] as List? ?? decoded['data'] as List? ?? []);
        final instruments = <BiquoteInstrument>[];
        for (final item in list) {
          try {
            if (item is Map<String, dynamic>) {
              final inst = BiquoteInstrument.fromJson(item);
              if (inst.symbol.isNotEmpty) {
                instruments.add(inst);
              }
            }
          } catch (_) {}
        }
        if (instruments.isNotEmpty) {
          _cachedInstruments = instruments;
          return instruments;
        }
      }
    } catch (e) {
      debugPrint('[MarketDataApi] getAllSymbols error: $e');
    }
    return _cachedInstruments ?? _fallbackInstruments;
  }

  /// Known instrument metadata catalog (names, descriptions, pip digits) for symbol search.
  static final List<BiquoteInstrument> _fallbackInstruments = [
    // ── Forex Majors & Crosses ────────────────────────────────────────────────
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
      description: 'US Dollar / Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
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
      symbol: 'EURGBP',
      description: 'Euro vs British Pound',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'EURJPY',
      description: 'Euro vs Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'GBPJPY',
      description: 'British Pound vs Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'AUDJPY',
      description: 'Australian Dollar vs Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'CADJPY',
      description: 'Canadian Dollar vs Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'CHFJPY',
      description: 'Swiss Franc vs Japanese Yen',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'EURCHF',
      description: 'Euro vs Swiss Franc',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'EURCAD',
      description: 'Euro vs Canadian Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'AUDCAD',
      description: 'Australian Dollar vs Canadian Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'NZDCAD',
      description: 'New Zealand Dollar vs Canadian Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'GBPCAD',
      description: 'British Pound vs Canadian Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'AUDNZD',
      description: 'Australian Dollar vs New Zealand Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'EURNZD',
      description: 'Euro vs New Zealand Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'GBPNZD',
      description: 'British Pound vs New Zealand Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    // ── Forex Exotics ─────────────────────────────────────────────────────────
    BiquoteInstrument(
      symbol: 'USDTRY',
      description: 'US Dollar vs Turkish Lira',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'EURTRY',
      description: 'Euro vs Turkish Lira',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDZAR',
      description: 'US Dollar vs South African Rand',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDMXN',
      description: 'US Dollar vs Mexican Peso',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDSEK',
      description: 'US Dollar vs Swedish Krona',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDNOK',
      description: 'US Dollar vs Norwegian Krone',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDPLN',
      description: 'US Dollar vs Polish Zloty',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDSGD',
      description: 'US Dollar vs Singapore Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDHKD',
      description: 'US Dollar vs Hong Kong Dollar',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'USDAED',
      description: 'US Dollar vs UAE Dirham',
      exchange: 'FOREX',
      type: 'Forex',
      digits: 5,
      isActive: true,
      hasData: true,
    ),
    // ── Metals & Commodities ──────────────────────────────────────────────────
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
      symbol: 'XAGUSD',
      description: 'Silver vs US Dollar',
      exchange: 'COMEX',
      type: 'Commodity',
      digits: 3,
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
      symbol: 'UKOIL',
      description: 'Brent Crude Oil',
      exchange: 'ICE',
      type: 'Commodity',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'NGAS',
      description: 'Natural Gas',
      exchange: 'NYMEX',
      type: 'Commodity',
      digits: 3,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'COPPER',
      description: 'Copper Cash CFD',
      exchange: 'COMEX',
      type: 'Commodity',
      digits: 4,
      isActive: true,
      hasData: true,
    ),
    // ── Cryptocurrencies ─────────────────────────────────────────────────────
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
      symbol: 'XRPUSD',
      description: 'Ripple vs US Dollar',
      exchange: 'CRYPTO',
      type: 'Crypto',
      digits: 4,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'DOGEUSD',
      description: 'Dogecoin vs US Dollar',
      exchange: 'CRYPTO',
      type: 'Crypto',
      digits: 4,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'ADAUSD',
      description: 'Cardano vs US Dollar',
      exchange: 'CRYPTO',
      type: 'Crypto',
      digits: 4,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'LTCUSD',
      description: 'Litecoin vs US Dollar',
      exchange: 'CRYPTO',
      type: 'Crypto',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'BTCXAG',
      description: 'Bitcoin vs Silver',
      exchange: 'CRYPTO',
      type: 'Crypto',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    // ── Global Indices ────────────────────────────────────────────────────────
    BiquoteInstrument(
      symbol: 'US30',
      description: 'Wall Street 30 / Dow Jones Index',
      exchange: 'INDEX',
      type: 'Index',
      digits: 1,
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
      symbol: 'USTEC',
      description: 'US Tech 100 / Nasdaq',
      exchange: 'INDEX',
      type: 'Index',
      digits: 1,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'UK100',
      description: 'UK 100 FTSE Index',
      exchange: 'INDEX',
      type: 'Index',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'GER40',
      description: 'Germany 40 DAX Index',
      exchange: 'INDEX',
      type: 'Index',
      digits: 1,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'FR40',
      description: 'France 40 CAC Index',
      exchange: 'INDEX',
      type: 'Index',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'JP225',
      description: 'Japan 225 Nikkei Index',
      exchange: 'INDEX',
      type: 'Index',
      digits: 1,
      isActive: true,
      hasData: true,
    ),
    // ── Leading Global Stocks ─────────────────────────────────────────────────
    BiquoteInstrument(
      symbol: 'AAPL',
      description: 'Apple Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'MSFT',
      description: 'Microsoft Corporation',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'NVDA',
      description: 'NVIDIA Corporation',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'AMZN',
      description: 'Amazon.com Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'GOOGL',
      description: 'Alphabet Inc. Class A',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'META',
      description: 'Meta Platforms Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'TSLA',
      description: 'Tesla Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'NFLX',
      description: 'Netflix Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'AMD',
      description: 'Advanced Micro Devices, Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'INTC',
      description: 'Intel Corporation',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'BABA',
      description: 'Alibaba Group Holding Ltd.',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'COIN',
      description: 'Coinbase Global, Inc.',
      exchange: 'NASDAQ',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'JPM',
      description: 'JPMorgan Chase & Co.',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'DIS',
      description: 'Walt Disney Company',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'V',
      description: 'Visa Inc.',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'MA',
      description: 'Mastercard Incorporated',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'WMT',
      description: 'Walmart Inc.',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'XOM',
      description: 'Exxon Mobil Corporation',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
    BiquoteInstrument(
      symbol: 'UBER',
      description: 'Uber Technologies, Inc.',
      exchange: 'NYSE',
      type: 'Stock',
      digits: 2,
      isActive: true,
      hasData: true,
    ),
  ];
}

class BiquoteInstrument {
  final String symbol;
  final String description;
  final String exchange;
  final String type; // 'Forex', 'Crypto', 'Commodity', 'Stock', 'Index'
  final int digits;
  final bool isActive;
  final bool hasData;

  BiquoteInstrument({
    required this.symbol,
    required this.description,
    required this.exchange,
    required this.type,
    required this.digits,
    required this.isActive,
    required this.hasData,
  });

  factory BiquoteInstrument.fromJson(Map<String, dynamic> j) =>
      BiquoteInstrument(
        symbol: j['name']?.toString() ?? j['symbol']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        exchange: j['exchange']?.toString() ?? '',
        type: j['type']?.toString() ?? 'Forex',
        digits: (j['digits'] as num?)?.toInt() ?? 5,
        isActive: j['isActive'] == true,
        hasData: j['hasData'] == true,
      );
}
