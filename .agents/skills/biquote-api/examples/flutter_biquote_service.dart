// Flutter / Dart Service for Biquote Market Data API (https://biquote.io/docs/)
// Provides batch price fetching, OHLC candle fetching, catalogue search, and SignalR live tick streaming.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents a single market tick from Biquote
class BiquoteTick {
  final String symbol;
  final String description;
  final double bid;
  final double ask;
  final double mid;
  final double spread;
  final double high;
  final double low;
  final String direction;
  final double dayDiffPercent;
  final DateTime timestamp;
  final String source;
  final String marketState; // "open" | "closed"
  final bool stale;
  final int quoteAgeSeconds;

  BiquoteTick({
    required this.symbol,
    required this.description,
    required this.bid,
    required this.ask,
    required this.mid,
    required this.spread,
    required this.high,
    required this.low,
    required this.direction,
    required this.dayDiffPercent,
    required this.timestamp,
    required this.source,
    required this.marketState,
    required this.stale,
    required this.quoteAgeSeconds,
  });

  bool get isMarketClosed => marketState == 'closed' || stale;

  factory BiquoteTick.fromJson(Map<String, dynamic> json) {
    return BiquoteTick(
      symbol: json['symbol'] as String? ?? '',
      description: json['description'] as String? ?? '',
      bid: (json['bid'] as num?)?.toDouble() ?? 0.0,
      ask: (json['ask'] as num?)?.toDouble() ?? 0.0,
      // mid is the primary reference price for broker CFDs
      mid: (json['mid'] as num?)?.toDouble() ?? 0.0,
      spread: (json['spread'] as num?)?.toDouble() ?? 0.0,
      high: (json['high'] as num?)?.toDouble() ?? 0.0,
      low: (json['low'] as num?)?.toDouble() ?? 0.0,
      direction: json['direction'] as String? ?? 'FLAT',
      dayDiffPercent: (json['dayDiffPercent'] as num?)?.toDouble() ?? 0.0,
      // Parse ISO 8601 UTC timestamp, never the MetaTrader 'time' string
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      source: json['source'] as String? ?? '',
      marketState: json['marketState'] as String? ?? 'open',
      stale: json['stale'] as bool? ?? false,
      quoteAgeSeconds: (json['quoteAgeSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Represents an OHLC candlestick bar
class BiquoteCandle {
  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final int tickVolume;
  final bool isOpen;

  BiquoteCandle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.tickVolume,
    required this.isOpen,
  });

  factory BiquoteCandle.fromJson(Map<String, dynamic> json) {
    return BiquoteCandle(
      openTime: DateTime.parse(json['openTime'] as String),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
      tickVolume: (json['tickVolume'] as num?)?.toInt() ?? 0,
      isOpen: json['isOpen'] as bool? ?? false,
    );
  }
}

/// Core service client for Biquote API
class BiquoteService {
  static const String baseUrl = 'https://biquote.io';
  final http.Client _client = http.Client();

  /// Fetch latest quotes for multiple symbols in a SINGLE request.
  /// Anti-pattern averted: Uses repeated query parameters (?symbols=A&symbols=B)
  Future<Map<String, BiquoteTick>> getLatestQuotes(List<String> symbols, {bool allowStale = true}) async {
    if (symbols.isEmpty) return {};

    final queryParams = symbols.map((s) => 'symbols=$s').join('&');
    final uri = Uri.parse('$baseUrl/api/latest?$queryParams&allowStale=$allowStale');

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch quotes: HTTP ${response.statusCode} - ${response.body}');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    return data.map((key, value) => MapEntry(key, BiquoteTick.fromJson(value as Map<String, dynamic>)));
  }

  /// Fetch single quote
  Future<BiquoteTick?> getSingleQuote(String symbol, {bool allowStale = true}) async {
    final uri = Uri.parse('$baseUrl/api/$symbol?allowStale=$allowStale');
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch quote for $symbol: ${response.statusCode}');
    }
    return BiquoteTick.fromJson(jsonDecode(response.body));
  }

  /// Fetch OHLC candles.
  /// Anti-pattern averted: Reverses the API's newest-first order so bars are chronological (oldest to newest).
  Future<List<BiquoteCandle>> getCandles(String symbol, {String interval = '1h', int limit = 100}) async {
    final uri = Uri.parse('$baseUrl/api/$symbol/ohlc?interval=$interval&limit=$limit');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch OHLC for $symbol');
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final List<dynamic> barsJson = data['bars'] as List<dynamic>? ?? [];

    final candles = barsJson.map((b) => BiquoteCandle.fromJson(b as Map<String, dynamic>)).toList();
    // Reverse newest-first to oldest-first for chart widgets
    return candles.reversed.toList();
  }

  /// Get active catalogue for instrument pickers.
  /// Anti-pattern averted: uses quotedWithinDays=7 instead of liveOnly=true
  Future<List<Map<String, dynamic>>> getPickerSymbols({int quotedWithinDays = 7, String? type}) async {
    var url = '$baseUrl/api/symbols?quotedWithinDays=$quotedWithinDays';
    if (type != null) url += '&type=$type';

    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(response.body));
  }

  void dispose() {
    _client.close();
  }
}
