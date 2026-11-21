import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/market_models.dart';
import 'alarm_service.dart';
import 'settings_provider.dart';

class BiquoteService {
  /// Biquote documents up to 2,000 historical bars per symbol/timeframe,
  /// returned in requests of at most 1,000 bars.
  static const int maxBarsPerSeries = 2000;
  static const int maxBarsPerRequest = 1000;

  static const String baseUrl = 'https://biquote.io';
  static const String directIp = '142.132.248.240';
  static const String directBaseUrl = 'https://142.132.248.240';
  static const String signalRUrl = 'wss://biquote.io/hubs/tick';
  static const String directSignalRUrl = 'wss://142.132.248.240/hubs/tick';

  final http.Client _client;
  late final HttpClient _ioClient;

  WebSocket? _ws;
  final StreamController<BiquoteTick> _tickController =
      StreamController<BiquoteTick>.broadcast();
  Stream<BiquoteTick> get tickStream => _tickController.stream;

  final Set<String> _subscribedSymbols = {};
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  bool _isConnecting = false;
  bool _isDisposed = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _socketWatchdogTimer;
  DateTime? _lastSocketDataAt;
  bool _disconnectHandled = true;
  int _reconnectAttempt = 0;

  final Map<String, double> _livePrices = {};
  double? livePriceFor(String symbol) => _livePrices[symbol];

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(true);
  bool get isOnline => isOnlineNotifier.value;

  BiquoteService({http.Client? client}) : _client = client ?? http.Client() {
    _ioClient = HttpClient();
    _ioClient.badCertificateCallback = (cert, host, port) =>
        host == directIp &&
        cert.subject.contains('CN=biquote.io') &&
        cert.endValidity.isAfter(DateTime.now());
    _ioClient.connectionTimeout = const Duration(seconds: 4);
  }

  Timer? _fallbackRestTimer;
  Timer? _deadManTimer;
  DateTime? _disconnectedSince;
  bool _fallbackRestRequestInFlight = false;

  void _onNetworkSuccess({bool realtimeSocket = false}) {
    _disconnectedSince = null;
    _deadManTimer?.cancel();
    if (realtimeSocket) _stopRestFallbackPolling();
    if (!isOnlineNotifier.value) {
      isOnlineNotifier.value = true;
    }
  }

  void _onNetworkFailure() {
    if (isOnlineNotifier.value) {
      isOnlineNotifier.value = false;
    }
  }

  /// Manually retry connection when user taps retry
  Future<void> retryConnection() async {
    if (_subscribedSymbols.isNotEmpty) {
      await getLatestQuotes(_subscribedSymbols.toList());
    }
    await _connectSignalR();
  }

  /// Helper to fetch JSON from Biquote API with resilient DNS fallback to direct IP
  Future<dynamic> _fetchJson(String pathAndQuery) async {
    // 1. Try primary domain first
    try {
      final uri = Uri.parse('$baseUrl$pathAndQuery');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _onNetworkSuccess();
        return jsonDecode(response.body);
      }
    } catch (_) {}

    // 2. Direct IP fallback is independently controlled by the market-data setting.
    if (SettingsProvider().directIpFallback) {
      try {
        final uri = Uri.parse('$directBaseUrl$pathAndQuery');
        final req = await _ioClient
            .getUrl(uri)
            .timeout(const Duration(seconds: 4));
        req.headers.set('Host', 'biquote.io');
        final resp = await req.close().timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          _onNetworkSuccess();
          final body = await resp.transform(utf8.decoder).join();
          return jsonDecode(body);
        }
      } catch (_) {}
    }

    _onNetworkFailure();
    return null;
  }

  /// Initializes real-time SignalR WebSocket connection to https://biquote.io/hubs/tick
  Future<void> initSignalR(List<String> initialSymbols) async {
    _subscribedSymbols.addAll(initialSymbols);
    await _connectSignalR();
  }

  Future<void> _connectSignalR() async {
    if (_isDisposed || _isConnecting || _isConnected) return;
    _isConnecting = true;
    _disconnectHandled = false;

    try {
      try {
        // Try domain first
        _ws = await WebSocket.connect(signalRUrl)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        if (!SettingsProvider().directIpFallback) rethrow;
        // Fallback to direct IP with Host header
        _ws = await WebSocket.connect(
          directSignalRUrl,
          headers: {'Host': 'biquote.io'},
          customClient: _ioClient,
        ).timeout(const Duration(seconds: 5));
      }

      _isConnected = true;
      _isConnecting = false;
      _deadManTimer?.cancel();
      _disconnectedSince = null;

      // 1. Send ASP.NET Core SignalR JSON protocol handshake
      _ws!.add('{"protocol":"json","version":1}\x1e');

      // 2. Start ping interval (SignalR expects periodic heartbeat)
      _pingTimer?.cancel();
      _socketWatchdogTimer?.cancel();
      _lastSocketDataAt = DateTime.now();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_isConnected && _ws != null) {
          try {
            _ws!.add('{"type":6}\x1e'); // SignalR Ping
          } catch (_) {}
        }
      });
      // A half-open TCP/WebSocket can stay "connected" after Wi-Fi or mobile
      // data disappears. Force the normal reconnect path if SignalR goes silent.
      _socketWatchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        final lastData = _lastSocketDataAt;
        if (_isConnected &&
            lastData != null &&
            DateTime.now().difference(lastData) > const Duration(seconds: 45)) {
          _handleDisconnect();
        }
      });

      // 3. Listen to incoming messages
      _ws!.listen(
        (data) => _handleIncomingData(data.toString()),
        onError: (err) {
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnecting = false;
      _handleDisconnect();
    }
  }

  void _handleIncomingData(String rawData) {
    _lastSocketDataAt = DateTime.now();
    // SignalR messages are separated by ASCII 30 (Record Separator \x1e)
    final messages = rawData.split('\x1e');
    for (final msg in messages) {
      final trimmed = msg.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed == '{}') {
        // Handshake acknowledged! Resubscribe to tracked symbols
        _isConnected = true;
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();
        _onNetworkSuccess(realtimeSocket: true);
        if (_subscribedSymbols.isNotEmpty) {
          _sendSubscription(_subscribedSymbols.toList());
        }
        continue;
      }

      try {
        final Map<String, dynamic> json = jsonDecode(trimmed);
        final int type = json['type'] as int? ?? 0;

        if (type == 1) {
          // Invocation message
          final String target = json['target'] as String? ?? '';
          final List<dynamic>? args = json['arguments'] as List<dynamic>?;

          if (target == 'ReceiveTick' && args != null && args.isNotEmpty) {
            _onNetworkSuccess(realtimeSocket: true);
            final tickData = args[0] as Map<String, dynamic>;
            final tick = BiquoteTick.fromJson(tickData);
            _livePrices[tick.symbol] = tick.mid;
            if (!_tickController.isClosed) {
              _tickController.add(tick);
            }
          }
        }
      } catch (_) {}
    }
  }

  void _sendSubscription(List<String> symbols) {
    if (_ws != null && _isConnected) {
      try {
        final payload = jsonEncode({
          'type': 1,
          'target': 'Subscribe',
          'arguments': [symbols],
        });
        _ws!.add('$payload\x1e');
      } catch (_) {}
    }
  }

  /// Subscribe to new symbols live
  void subscribe(List<String> symbols) {
    _subscribedSymbols.addAll(symbols);
    if (_isConnected) {
      _sendSubscription(symbols);
    } else {
      _connectSignalR();
    }
  }

  /// Unsubscribe from symbols
  void unsubscribe(List<String> symbols) {
    _subscribedSymbols.removeAll(symbols);
    if (_ws != null && _isConnected) {
      try {
        final payload = jsonEncode({
          'type': 1,
          'target': 'Unsubscribe',
          'arguments': [symbols],
        });
        _ws!.add('$payload\x1e');
      } catch (_) {}
    }
  }

  void _handleDisconnect() {
    if (_isDisposed || _disconnectHandled) return;
    _disconnectHandled = true;
    _isConnected = false;
    _isConnecting = false;
    if (isOnlineNotifier.value) {
      isOnlineNotifier.value = false;
    }
    _pingTimer?.cancel();
    _socketWatchdogTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;

    final settings = SettingsProvider();
    _disconnectedSince ??= DateTime.now();

    // Dead-Man Connection Loss Warning (triggers if disconnected for 3 continuous minutes)
    if (settings.deadManWarning) {
      _deadManTimer?.cancel();
      _deadManTimer = Timer(const Duration(minutes: 3), () {
        if (!_isConnected && !_isDisposed) {
          AlarmService().playShortBeep();
        }
      });
    }

    // Transport Fallback (WebSocket -> 1-second REST Polling)
    if (settings.transportFallback && _subscribedSymbols.isNotEmpty) {
      _startRestFallbackPolling();
    }

    _scheduleReconnect();
  }

  /// Apply a changed reconnect switch immediately, including canceling a retry
  /// that was queued while the switch was on.
  void applyReconnectSettings() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (!_isConnected && !_isConnecting) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final settings = SettingsProvider();
    if (_isDisposed ||
        (!settings.biquoteAutoReconnect && !settings.autoNetworkFailover) ||
        _subscribedSymbols.isEmpty) {
      return;
    }
    _reconnectTimer?.cancel();
    final seconds = settings.autoNetworkFailover
        ? [1, 2, 4, 8, 15][_reconnectAttempt.clamp(0, 4)]
        : [2, 4, 8, 16, 30][_reconnectAttempt.clamp(0, 4)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_isDisposed && !_isConnected) _connectSignalR();
    });
  }

  void _startRestFallbackPolling() {
    _fallbackRestTimer?.cancel();
    _fallbackRestTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_isConnected ||
          _isDisposed ||
          _subscribedSymbols.isEmpty ||
          _fallbackRestRequestInFlight) {
        return;
      }
      _fallbackRestRequestInFlight = true;
      try {
        final quotes = await getLatestQuotes(_subscribedSymbols.toList());
        for (final tick in quotes.values) {
          _livePrices[tick.symbol] = tick.mid;
          if (!_tickController.isClosed) {
            _tickController.add(tick);
          }
        }
      } catch (_) {
      } finally {
        _fallbackRestRequestInFlight = false;
      }
    });
  }

  void _stopRestFallbackPolling() {
    _fallbackRestTimer?.cancel();
    _fallbackRestTimer = null;
  }

  /// Fetch batch quotes for multiple symbols using repeated query params
  Future<Map<String, BiquoteTick>> getLatestQuotes(
    List<String> symbols, {
    bool allowStale = true,
  }) async {
    if (symbols.isEmpty) return {};

    final queryParams = symbols.map((s) => 'symbols=$s').join('&');
    final path = '/api/latest?$queryParams&allowStale=$allowStale';

    final data = await _fetchJson(path);
    if (data is Map<String, dynamic>) {
      final result = <String, BiquoteTick>{};
      data.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final tick = BiquoteTick.fromJson(value);
          result[key] = tick;
          _livePrices[key] = tick.mid;
        }
      });
      return result;
    }

    return {};
  }

  /// Fetch single quote
  Future<BiquoteTick?> getSingleQuote(
    String symbol, {
    bool allowStale = true,
  }) async {
    final path = '/api/$symbol?allowStale=$allowStale';
    final data = await _fetchJson(path);
    if (data is Map<String, dynamic>) {
      final tick = BiquoteTick.fromJson(data);
      _livePrices[symbol] = tick.mid;
      return tick;
    }
    return null;
  }

  /// Fetch OHLC candles.
  /// Anti-pattern 5 averted: Reverses Biquote newest-first order to chronological (oldest to newest).
  /// Valid intervals according to Biquote docs: 1m, 5m, 15m, 30m, 1h, 4h, 1d.
  Future<List<BiquoteCandle>> getCandles(
    String symbol, {
    String interval = '1h',
    int limit = 60,
    DateTime? to,
  }) async {
    final requestLimit = limit.clamp(1, maxBarsPerRequest).toInt();
    final sanitizedInterval = _sanitizeInterval(interval);
    final toParam = to != null
        ? '&to=${Uri.encodeComponent(to.toUtc().toIso8601String())}'
        : '';
    final path =
        '/api/$symbol/ohlc?interval=$sanitizedInterval&limit=$requestLimit$toParam';

    final data = await _fetchJson(path);
    // Keep transport/API failures distinct from a successful empty result.
    // Paginated chart callers can then retry after a temporary outage instead
    // of treating it as the end of available history.
    if (data == null) {
      throw HttpException('Failed to fetch OHLC history for $symbol.');
    }
    if (data is Map<String, dynamic>) {
      final List<dynamic> barsJson = data['bars'] as List<dynamic>? ?? [];
      if (barsJson.isNotEmpty) {
        final candles = barsJson
            .map((b) => BiquoteCandle.fromJson(b as Map<String, dynamic>))
            .toList();
        final chronological = candles.reversed.toList();
        if (chronological.isNotEmpty) {
          _livePrices[symbol] = chronological.last.close;
        }
        return chronological;
      }
    }

    return [];
  }

  /// Loads the full history Biquote currently makes available for a series.
  /// The API caps one request at 1,000 bars and documents up to 2,000 bars per
  /// series, so this walks back in pages and deduplicates by candle open time.
  Future<List<BiquoteCandle>> getAvailableCandleHistory(
    String symbol, {
    String interval = '1h',
  }) async {
    var history = await getCandles(
      symbol,
      interval: interval,
      limit: maxBarsPerRequest,
    );
    while (history.isNotEmpty && history.length < maxBarsPerSeries) {
      final cursor = history.first.openTime;
      final remaining = maxBarsPerSeries - history.length;
      final olderPage = await getCandles(
        symbol,
        interval: interval,
        limit: remaining.clamp(1, maxBarsPerRequest).toInt(),
        to: cursor.subtract(const Duration(seconds: 1)),
      );
      if (olderPage.isEmpty ||
          !olderPage.any((bar) => bar.openTime.isBefore(cursor))) {
        break;
      }

      final byTime = <int, BiquoteCandle>{
        for (final candle in history)
          candle.openTime.millisecondsSinceEpoch: candle,
      };
      for (final candle in olderPage) {
        byTime[candle.openTime.millisecondsSinceEpoch] = candle;
      }
      final merged = byTime.values.toList()
        ..sort((a, b) => a.openTime.compareTo(b.openTime));
      if (merged.length == history.length) break;
      history = merged;
    }
    return history;
  }

  String _sanitizeInterval(String tf) {
    final lower = tf.toLowerCase();
    switch (lower) {
      case '1m':
        return '1m';
      case '5m':
        return '5m';
      case '15m':
        return '15m';
      case '30m':
        return '30m';
      case '1h':
        return '1h';
      case '4h':
        return '4h';
      case '1d':
      case '1w':
        return '1d';
      default:
        return '1h';
    }
  }

  void dispose() {
    _isDisposed = true;
    _pingTimer?.cancel();
    _socketWatchdogTimer?.cancel();
    _reconnectTimer?.cancel();
    _fallbackRestTimer?.cancel();
    _deadManTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _tickController.close();
    _ioClient.close(force: true);
  }
}
