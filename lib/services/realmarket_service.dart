import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_models.dart';
import '../models/market_models.dart';
import 'biquote_service.dart';
import 'storage_service.dart';

class RealMarketFetchResult {
  final List<BiquoteCandle> candles;
  final bool isSuccess;
  final String source;
  final String? errorMessage;
  final MarketStructureAnalysis? structure;

  const RealMarketFetchResult({
    required this.candles,
    required this.isSuccess,
    required this.source,
    this.errorMessage,
    this.structure,
  });
}

class RealMarketTestResult {
  final bool success;
  final String message;
  final int candleCount;
  final double? latestPrice;

  const RealMarketTestResult({
    required this.success,
    required this.message,
    this.candleCount = 0,
    this.latestPrice,
  });
}

/// Market structure and indicator analytics matching tradde.py and agent_orchestrator.py
class MarketStructureAnalysis {
  final double currentPrice;
  final double ema50;
  final double ema200;
  final String trend; // "Uptrend", "Downtrend", "Sideways"
  final List<Map<String, dynamic>> swingHighs;
  final List<Map<String, dynamic>> swingLows;
  final double atr;
  final double bollingerWidth;
  final bool isConsolidating;

  const MarketStructureAnalysis({
    required this.currentPrice,
    required this.ema50,
    required this.ema200,
    required this.trend,
    required this.swingHighs,
    required this.swingLows,
    required this.atr,
    required this.bollingerWidth,
    required this.isConsolidating,
  });
}

class RealMarketService {
  final http.Client _client;
  RealMarketConfig config;
  final BiquoteService? biquoteFallback;

  RealMarketService({
    http.Client? client,
    this.config = const RealMarketConfig(),
    this.biquoteFallback,
  }) : _client = client ?? http.Client();

  // Exactly matching SYMBOL_MAP from trade.py in the reference project
  static const Map<String, String> _symbolMap = {
    'EUR/USD': 'EURUSD',
    'USD/JPY': 'USDJPY',
    'GBP/USD': 'GBPUSD',
    'USD/CHF': 'USDCHF',
    'USD/CAD': 'USDCAD',
    'AUD/USD': 'AUDUSD',
    'NZD/USD': 'NZDUSD',
    'GBP/JPY': 'GBPJPY',
    'EUR/JPY': 'EURJPY',
    'EUR/GBP': 'EURGBP',
    'AUD/JPY': 'AUDJPY',
    'CAD/JPY': 'CADJPY',
    'GOLD': 'XAUUSD',
    'XAU/USD': 'XAUUSD',
    'SILVER': 'XAGUSD',
    'XAG/USD': 'XAGUSD',
    'OIL (WTI)': 'USOIL',
    'BTC/USD': 'BTCUSD',
    'ETH/USD': 'ETHUSD',
    'XRP/USD': 'XRPUSD',
    'SOL/USD': 'SOLUSD',
    'BNB/USD': 'BNBUSD',
    'S&P 500': 'US500',
    'NASDAQ': 'USTEC',
    'DOW JONES': 'US30',
  };

  // Exactly matching TIMEFRAME_MAP from trade.py in the reference project
  static const Map<String, String> _timeframeMap = {
    '1m': 'M1',
    '1M': 'M1',
    'M1': 'M1',
    '5m': 'M5',
    '5M': 'M5',
    'M5': 'M5',
    '15m': 'M15',
    '15M': 'M15',
    'M15': 'M15',
    '30m': 'M30',
    '30M': 'M30',
    'M30': 'M30',
    '1h': 'H1',
    '1H': 'H1',
    'H1': 'H1',
    '4h': 'H4',
    '4H': 'H4',
    'H4': 'H4',
    '1d': 'D1',
    '1D': 'D1',
    'D1': 'D1',
    '1wk': 'D1',
    '1W': 'D1',
    'W1': 'D1',
  };

  String resolveSymbolCode(String raw) {
    final trimmed = raw.trim().toUpperCase();
    if (_symbolMap.containsKey(trimmed)) {
      return _symbolMap[trimmed]!;
    }

    if (trimmed == 'GC=F' || trimmed.contains('GOLD')) return 'XAUUSD';
    if (trimmed == 'SI=F' || trimmed.contains('SILVER')) return 'XAGUSD';

    final cleaned = trimmed
        .replaceAll('=X', '')
        .replaceAll('=F', '')
        .replaceAll('-', '')
        .replaceAll('/', '')
        .replaceAll(' ', '');

    return _symbolMap[cleaned] ?? cleaned;
  }

  String resolveTimeFrame(String raw) {
    final trimmed = raw.trim();
    return _timeframeMap[trimmed] ??
        _timeframeMap[trimmed.toLowerCase()] ??
        'H1';
  }

  /// Tests the RealMarket API endpoint directly with current configuration
  Future<RealMarketTestResult> testConnection() async {
    final apiKey = config.apiKey.trim();
    if (apiKey.isEmpty) {
      return const RealMarketTestResult(
        success: false,
        message: 'RealMarket API key is not configured for this app build.',
      );
    }

    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(base).replace(
      path: '/api/v1/candle',
      queryParameters: {
        'apiKey': apiKey,
        'symbolCode': 'EURUSD',
        'timeFrame': 'H1',
      },
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent': 'TenX-TradingBot/2.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          list = decoded['data'] as List<dynamic>;
        } else if (decoded is List) {
          list = decoded;
        }

        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final price =
              double.tryParse(
                first['closePrice']?.toString() ??
                    first['close']?.toString() ??
                    '0',
              ) ??
              0.0;
          return RealMarketTestResult(
            success: true,
            message:
                'Connected to RealMarket API! Received ${list.length} candles (EURUSD: $price).',
            candleCount: list.length,
            latestPrice: price,
          );
        } else {
          return const RealMarketTestResult(
            success: false,
            message: 'RealMarket API responded 200 OK, but returned empty candle array.',
          );
        }
      } else {
        return RealMarketTestResult(
          success: false,
          message:
              'RealMarket API returned HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      return RealMarketTestResult(
        success: false,
        message: 'RealMarket API request failed: $e',
      );
    }
  }

  /// Fetches candles using the 3-tier fallback matching trade.py in the reference project:
  /// 1. /api/v1/candle (100 rolling dataset)
  /// 2. /api/v1/history (30-day historical range query)
  /// 3. /api/v1/price (snapshot fallback)
  /// 4. BiquoteService (in-app fallback)
  // ==========================================
  // Offline Candle Cache & Persistence Layer
  // ==========================================
  static final Map<String, List<BiquoteCandle>> _memoryCandleCache = {};
  static final Map<String, Future<void>> _cacheWriteTails = {};
  static final Set<String> _cachedKeys = {};
  static bool _cacheIndexLoaded = false;

  static String getCacheKey(String symbolCode, String tfCode) =>
      '${symbolCode}_$tfCode';

  static Future<void> _ensureCacheIndexLoaded() async {
    if (_cacheIndexLoaded) return;
    try {
      final indexStr = await StorageService.getLocalString(
        'candle_cache_index',
      );
      if (indexStr != null && indexStr.isNotEmpty) {
        _cachedKeys.addAll(indexStr.split(',').where((k) => k.isNotEmpty));
      }
      _cacheIndexLoaded = true;
    } catch (_) {}
  }

  static Future<void> updateCache(
    String cacheKey,
    List<BiquoteCandle> incoming,
  ) async {
    if (incoming.isEmpty) return;
    final previousWrite = _cacheWriteTails[cacheKey] ?? Future<void>.value();
    final nextWrite = previousWrite
        .catchError((Object _) {})
        .then((_) => _writeCache(cacheKey, incoming));
    _cacheWriteTails[cacheKey] = nextWrite;
    try {
      await nextWrite;
    } finally {
      if (identical(_cacheWriteTails[cacheKey], nextWrite)) {
        _cacheWriteTails.remove(cacheKey);
      }
    }
  }

  static Future<void> _writeCache(
    String cacheKey,
    List<BiquoteCandle> incoming,
  ) async {
    await _ensureCacheIndexLoaded();

    var existing = _memoryCandleCache[cacheKey] ?? const <BiquoteCandle>[];

    // On a cold launch, merge with the persisted history before writing. This
    // keeps older scroll-loaded pages when fresh candles arrive from the API.
    if (existing.isEmpty) {
      try {
        final storedJson = await StorageService.getLocalString(
          'candle_cache_$cacheKey',
        );
        final decoded = storedJson == null || storedJson.isEmpty
            ? null
            : jsonDecode(storedJson);
        if (decoded is List) {
          existing = decoded
              .whereType<Map<String, dynamic>>()
              .map(BiquoteCandle.fromJson)
              .toList();
        }
      } catch (_) {
        // A malformed or unavailable cache should not prevent a fresh fetch.
      }
    }

    // Combine and deduplicate by openTime
    final Map<int, BiquoteCandle> candleMap = {};
    for (final c in existing) {
      candleMap[c.openTime.millisecondsSinceEpoch] = c;
    }
    for (final c in incoming) {
      candleMap[c.openTime.millisecondsSinceEpoch] = c;
    }

    final sorted = candleMap.values.toList()
      ..sort((a, b) => a.openTime.compareTo(b.openTime));

    _memoryCandleCache[cacheKey] = sorted;
    _cachedKeys.add(cacheKey);

    // Asynchronously save to storage
    try {
      final jsonList = sorted.map((c) => c.toJson()).toList();
      await StorageService.setLocalString(
        'candle_cache_$cacheKey',
        jsonEncode(jsonList),
      );
      await StorageService.setLocalString(
        'candle_cache_index',
        _cachedKeys.join(','),
      );
    } catch (_) {}
  }

  static Future<List<BiquoteCandle>?> loadFromCache(String cacheKey) async {
    if (_memoryCandleCache.containsKey(cacheKey) &&
        _memoryCandleCache[cacheKey]!.isNotEmpty) {
      return _memoryCandleCache[cacheKey];
    }

    try {
      final storedJson = await StorageService.getLocalString(
        'candle_cache_$cacheKey',
      );
      if (storedJson != null && storedJson.isNotEmpty) {
        final decoded = jsonDecode(storedJson);
        if (decoded is List) {
          final candles =
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map((m) => BiquoteCandle.fromJson(m))
                  .toList()
                ..sort((a, b) => a.openTime.compareTo(b.openTime));
          if (candles.isNotEmpty) {
            await updateCache(cacheKey, candles);
            return _memoryCandleCache[cacheKey];
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Purges all locally cached historical market candles and returns the total purged count
  static Future<int> clearCandleCache() async {
    // Read the index strictly before touching any payload so an inaccessible
    // index cannot be mistaken for an empty cache and leave orphaned entries.
    final storedIndex = await StorageService.getLocalStringRequired(
      'candle_cache_index',
    );
    final persistedPayloadKeys =
        await StorageService.listKeysWithPrefixRequired('candle_cache_');
    final keys = <String>{
      ..._cachedKeys,
      ..._memoryCandleCache.keys,
      ...persistedPayloadKeys
          .where((key) => key != 'candle_cache_index')
          .map((key) => key.substring('candle_cache_'.length)),
      if (storedIndex != null && storedIndex.isNotEmpty)
        ...storedIndex.split(',').where((key) => key.isNotEmpty),
    };
    final snapshots = <String, String?>{};
    var count = 0;
    for (final key in keys) {
      final storageKey = 'candle_cache_$key';
      final stored = await StorageService.getLocalStringRequired(storageKey);
      snapshots[storageKey] = stored;
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is! List) {
          throw FormatException('Invalid candle cache payload: $storageKey');
        }
        count += decoded.length;
      } else {
        count += _memoryCandleCache[key]?.length ?? 0;
      }
    }

    snapshots['candle_cache_index'] = storedIndex;
    final touchedKeys = <String>[];
    try {
      for (final key in keys) {
        final storageKey = 'candle_cache_$key';
        touchedKeys.add(storageKey);
        await StorageService.removeLocalRequired(storageKey);
      }
      touchedKeys.add('candle_cache_index');
      await StorageService.removeLocalRequired('candle_cache_index');
    } catch (purgeError) {
      final rollbackErrors = <Object>[];
      for (final key in touchedKeys.reversed) {
        try {
          final previousValue = snapshots[key];
          if (previousValue == null) {
            await StorageService.removeLocalRequired(key);
          } else {
            await StorageService.setLocalStringRequired(key, previousValue);
          }
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
      if (rollbackErrors.isNotEmpty) {
        throw StateError(
          'Candle cache purge failed ($purgeError), and rollback failed '
          'for ${rollbackErrors.length} storage operation(s): '
          '${rollbackErrors.join('; ')}',
        );
      }
      rethrow;
    }

    _memoryCandleCache.clear();
    _cachedKeys.clear();

    return count;
  }

  /// Returns total count of cached candles across all symbol/timeframe pairs
  static int getCachedCandleCount() {
    int count = 0;
    for (final candles in _memoryCandleCache.values) {
      count += candles.length;
    }
    return count;
  }

  /// Counts memory and persisted cache data without assuming the cache was loaded.
  /// Missing or corrupt entries are reported so diagnostics never present a
  /// partial count as complete.
  static Future<CandleCacheStats> getCachedCandleStats() async {
    final memoryKeys = _memoryCandleCache.keys.toSet();
    String? index;
    var unreadable = 0;
    try {
      index = await StorageService.getLocalStringRequired('candle_cache_index');
    } catch (_) {
      return CandleCacheStats(
        candleCount: getCachedCandleCount(),
        missingEntries: 0,
        unreadableEntries: 1,
        indexReadable: false,
      );
    }
    if (index == null || index.isEmpty) {
      return CandleCacheStats(
        candleCount: getCachedCandleCount(),
        missingEntries: 0,
        unreadableEntries: 0,
        indexReadable: true,
      );
    }

    final keys = index.split(',').where((key) => key.isNotEmpty).toSet();
    var count = 0;
    var missing = 0;
    for (final key in keys) {
      try {
        final stored = await StorageService.getLocalStringRequired(
          'candle_cache_$key',
        );
        if (stored == null || stored.isEmpty) {
          missing++;
          count += _memoryCandleCache[key]?.length ?? 0;
          continue;
        }
        final decoded = jsonDecode(stored);
        if (decoded is List) {
          final validBars = decoded.whereType<Map>().length;
          count += validBars;
          unreadable += decoded.length - validBars;
        } else {
          unreadable++;
          count += _memoryCandleCache[key]?.length ?? 0;
        }
      } catch (_) {
        unreadable++;
        count += _memoryCandleCache[key]?.length ?? 0;
      }
    }
    for (final key in memoryKeys.difference(keys)) {
      count += _memoryCandleCache[key]?.length ?? 0;
    }
    return CandleCacheStats(
      candleCount: count,
      missingEntries: missing,
      unreadableEntries: unreadable,
      indexReadable: true,
    );
  }

  /// Returns count of unique symbol/timeframe pairs currently cached
  static int getCachedPairCount() => _memoryCandleCache.length;

  Future<RealMarketFetchResult> fetchMarketCandles(
    String symbol,
    String timeframe,
  ) async {
    final symbolCode = resolveSymbolCode(symbol);
    final tfCode = resolveTimeFrame(timeframe);
    final cacheKey = getCacheKey(symbolCode, tfCode);
    final apiKey = config.apiKey.trim();
    final cleanBase = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    String lastError = '';

    // ==========================================
    // 1. Primary Endpoint: /api/v1/candle
    // ==========================================
    try {
      final candleUri = Uri.parse(cleanBase).replace(
        path: '/api/v1/candle',
        queryParameters: {
          'apiKey': apiKey,
          'symbolCode': symbolCode,
          'timeFrame': tfCode,
        },
      );

      final response = await _client
          .get(
            candleUri,
            headers: {
              'User-Agent': 'TenX-TradingBot/2.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final candles = _parseCandleList(decoded);
        if (candles.isNotEmpty) {
          final chronological = candles.reversed.toList();
          await updateCache(cacheKey, chronological);
          final structure = computeMarketStructure(chronological);
          return RealMarketFetchResult(
            candles: chronological,
            isSuccess: true,
            source: 'realmarket_candle',
            structure: structure,
          );
        }
      } else {
        lastError =
            'RealMarket /api/v1/candle HTTP ${response.statusCode}: ${response.body}';
        debugPrint(lastError);
      }
    } catch (e) {
      lastError = 'RealMarket /api/v1/candle failed: $e';
      debugPrint(lastError);
    }

    // ==========================================
    // 2. Secondary Endpoint: /api/v1/history
    // ==========================================
    try {
      final now = DateTime.now().toUtc();
      final start = now.subtract(const Duration(days: 30));
      final historyUri = Uri.parse(cleanBase).replace(
        path: '/api/v1/history',
        queryParameters: {
          'apiKey': apiKey,
          'symbolCode': symbolCode,
          'timeFrame': tfCode,
          'startTime': '${start.toIso8601String().split('.').first}Z',
          'endTime': '${now.toIso8601String().split('.').first}Z',
          'limit': '100',
        },
      );

      final response = await _client
          .get(
            historyUri,
            headers: {
              'User-Agent': 'TenX-TradingBot/2.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final candles = _parseCandleList(decoded);
        if (candles.isNotEmpty) {
          final chronological = candles.reversed.toList();
          await updateCache(cacheKey, chronological);
          final structure = computeMarketStructure(chronological);
          return RealMarketFetchResult(
            candles: chronological,
            isSuccess: true,
            source: 'realmarket_history',
            structure: structure,
          );
        }
      } else {
        lastError =
            'RealMarket /api/v1/history HTTP ${response.statusCode}: ${response.body}';
        debugPrint(lastError);
      }
    } catch (e) {
      lastError = 'RealMarket /api/v1/history failed: $e';
      debugPrint(lastError);
    }

    // ==========================================
    // 3. Fallback Endpoint: /api/v1/price
    // ==========================================
    try {
      final priceUri = Uri.parse(cleanBase).replace(
        path: '/api/v1/price',
        queryParameters: {
          'apiKey': apiKey,
          'symbolCode': symbolCode,
          'timeFrame': tfCode,
        },
      );

      final response = await _client
          .get(
            priceUri,
            headers: {
              'User-Agent': 'TenX-TradingBot/2.0',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final candles = _parseCandleList(decoded);
        if (candles.isNotEmpty) {
          final chronological = candles.reversed.toList();
          await updateCache(cacheKey, chronological);
          final structure = computeMarketStructure(chronological);
          return RealMarketFetchResult(
            candles: chronological,
            isSuccess: true,
            source: 'realmarket_price',
            structure: structure,
          );
        }
      }
    } catch (e) {
      debugPrint('RealMarket /api/v1/price fallback failed: $e');
    }

    // ==========================================
    // 4. In-App Biquote Fallback
    // ==========================================
    if (biquoteFallback != null) {
      try {
        debugPrint('Falling back to live BiquoteService for $symbol...');
        final candles = await biquoteFallback!.getCandles(
          symbol,
          interval: timeframe.toLowerCase(),
          limit: 100,
        );
        if (candles.isNotEmpty) {
          await updateCache(cacheKey, candles);
          final structure = computeMarketStructure(candles);
          return RealMarketFetchResult(
            candles: candles,
            isSuccess: true,
            source: 'biquote_fallback',
            structure: structure,
          );
        }
      } catch (e) {
        debugPrint('Biquote fallback also failed: $e');
      }
    }

    // ==========================================
    // 5. Offline Local Cache Fallback
    // ==========================================
    final cached = await loadFromCache(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      debugPrint(
        'Returning ${cached.length} cached historical candles for $symbolCode ($tfCode) [Offline]',
      );
      final structure = computeMarketStructure(cached);
      return RealMarketFetchResult(
        candles: cached,
        isSuccess: true,
        source: 'offline_cache',
        structure: structure,
      );
    }

    return RealMarketFetchResult(
      candles: [],
      isSuccess: false,
      source: 'none',
      errorMessage: lastError.isNotEmpty
          ? lastError
          : 'Failed to retrieve candles for $symbolCode.',
    );
  }

  /// Backward-compatible alias for fetchMarketCandles returning `List<BiquoteCandle>`
  Future<List<BiquoteCandle>> fetch100Candles(
    String symbol,
    String timeframe,
  ) async {
    final res = await fetchMarketCandles(symbol, timeframe);
    return res.candles;
  }

  /// Normalizes candle schema matching trade.py field_map
  List<BiquoteCandle> _parseCandleList(dynamic decoded) {
    List<dynamic> rawList = [];
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is List) {
        rawList = decoded['data'] as List<dynamic>;
      } else if (decoded['candles'] is List) {
        rawList = decoded['candles'] as List<dynamic>;
      } else if (decoded.containsKey('openPrice') ||
          decoded.containsKey('open')) {
        rawList = [decoded];
      }
    } else if (decoded is List) {
      rawList = decoded;
    }

    final List<BiquoteCandle> candles = [];
    for (final c in rawList) {
      if (c is Map<String, dynamic>) {
        final timeStr =
            c['openTime']?.toString() ??
            c['OpenTime']?.toString() ??
            c['timestamp']?.toString() ??
            c['time']?.toString() ??
            c['Date']?.toString() ??
            '';
        final openTime = DateTime.tryParse(timeStr) ?? DateTime.now();

        final open = _toDouble(
          c['openPrice'] ?? c['OpenPrice'] ?? c['open'] ?? c['Open'],
        );
        final high = _toDouble(
          c['highPrice'] ?? c['HighPrice'] ?? c['high'] ?? c['High'],
        );
        final low = _toDouble(
          c['lowPrice'] ?? c['LowPrice'] ?? c['low'] ?? c['Low'],
        );
        final close = _toDouble(
          c['closePrice'] ?? c['ClosePrice'] ?? c['close'] ?? c['Close'],
        );
        final volume = _toInt(
          c['volume'] ?? c['Volume'] ?? c['tickVolume'] ?? 0,
        );

        if (open > 0 || high > 0 || low > 0 || close > 0) {
          candles.add(
            BiquoteCandle(
              openTime: openTime,
              open: open,
              high: high,
              low: low,
              close: close,
              tickVolume: volume,
              isOpen: false,
            ),
          );
        }
      }
    }

    return candles;
  }

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  /// Computes EMA, Swing Highs/Lows, ATR, and Bollinger Bands matching tradde.py
  MarketStructureAnalysis computeMarketStructure(List<BiquoteCandle> candles) {
    if (candles.isEmpty) {
      return const MarketStructureAnalysis(
        currentPrice: 0,
        ema50: 0,
        ema200: 0,
        trend: 'Sideways',
        swingHighs: [],
        swingLows: [],
        atr: 0,
        bollingerWidth: 0,
        isConsolidating: false,
      );
    }

    final currentPrice = candles.last.close;

    // EMA calculation
    double calcEma(int period) {
      if (candles.isEmpty) return 0;
      final k = 2 / (period + 1);
      double ema = candles.first.close;
      for (int i = 1; i < candles.length; i++) {
        ema = (candles[i].close * k) + (ema * (1 - k));
      }
      return ema;
    }

    final ema50 = calcEma(50);
    final ema200 = calcEma(200);

    String trend = 'Sideways';
    if (ema50 > ema200) {
      trend = 'Uptrend';
    } else if (ema50 < ema200) {
      trend = 'Downtrend';
    }

    // Local Extrema Swing Highs & Lows (order = 3)
    final List<Map<String, dynamic>> swingHighs = [];
    final List<Map<String, dynamic>> swingLows = [];

    const order = 3;
    for (int i = order; i < candles.length - order; i++) {
      final curHigh = candles[i].high;
      final curLow = candles[i].low;

      bool isHigh = true;
      bool isLow = true;
      for (int j = 1; j <= order; j++) {
        if (candles[i - j].high >= curHigh || candles[i + j].high >= curHigh) {
          isHigh = false;
        }
        if (candles[i - j].low <= curLow || candles[i + j].low <= curLow) {
          isLow = false;
        }
      }

      if (isHigh) {
        swingHighs.add({
          'time': candles[i].openTime.toIso8601String(),
          'price': curHigh,
          'index': i,
        });
      }
      if (isLow) {
        swingLows.add({
          'time': candles[i].openTime.toIso8601String(),
          'price': curLow,
          'index': i,
        });
      }
    }

    // ATR (period 14)
    double atr = 0;
    if (candles.length > 1) {
      final trList = <double>[];
      for (int i = 1; i < candles.length; i++) {
        final h = candles[i].high;
        final l = candles[i].low;
        final prevC = candles[i - 1].close;
        final tr = max(h - l, max((h - prevC).abs(), (l - prevC).abs()));
        trList.add(tr);
      }
      final recentTr = trList.length > 14
          ? trList.sublist(trList.length - 14)
          : trList;
      atr = recentTr.reduce((a, b) => a + b) / recentTr.length;
    }

    // Bollinger Bands (period 20)
    double bollingerWidth = 0;
    bool isConsolidating = false;
    if (candles.length >= 20) {
      final subset = candles.sublist(candles.length - 20);
      final mean = subset.map((c) => c.close).reduce((a, b) => a + b) / 20;
      final variance =
          subset.map((c) => pow(c.close - mean, 2)).reduce((a, b) => a + b) /
          20;
      final stdDev = sqrt(variance);
      final upper = mean + (2 * stdDev);
      final lower = mean - (2 * stdDev);
      bollingerWidth = (upper - lower) / (mean > 0 ? mean : 1);
      isConsolidating = bollingerWidth < 0.05;
    }

    return MarketStructureAnalysis(
      currentPrice: currentPrice,
      ema50: ema50,
      ema200: ema200,
      trend: trend,
      swingHighs: swingHighs,
      swingLows: swingLows,
      atr: atr,
      bollingerWidth: bollingerWidth,
      isConsolidating: isConsolidating,
    );
  }
}

class CandleCacheStats {
  final int candleCount;
  final int missingEntries;
  final int unreadableEntries;
  final bool indexReadable;

  const CandleCacheStats({
    required this.candleCount,
    required this.missingEntries,
    required this.unreadableEntries,
    required this.indexReadable,
  });
}
