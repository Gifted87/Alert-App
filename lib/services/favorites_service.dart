import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

class FavoritesService extends ChangeNotifier {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  static const String _storageKey = 'favorite_symbols';
  static const List<String> defaultFavorites = [
    'EURUSD',
    'GBPUSD',
    'USDJPY',
    'XAUUSD',
    'BTCUSD',
    'US500',
    'USOIL',
  ];

  List<String> _favorites = List.from(defaultFavorites);
  bool _isLoaded = false;

  List<String> get favorites => List.unmodifiable(_favorites);
  bool get isLoaded => _isLoaded;

  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final raw = await StorageService.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final loaded = decoded.map((e) => e.toString().toUpperCase()).toList();
        if (loaded.isNotEmpty) {
          _favorites = loaded;
        }
      }
    } catch (e) {
      debugPrint('FavoritesService load error: $e');
    }
    _isLoaded = true;
    notifyListeners();
  }

  bool isFavorite(String symbol) {
    return _favorites.contains(symbol.toUpperCase());
  }

  Future<bool> toggleFavorite(String symbol) async {
    final clean = symbol.toUpperCase();
    final bool nowFavorited;
    if (_favorites.contains(clean)) {
      _favorites.remove(clean);
      nowFavorited = false;
    } else {
      _favorites.add(clean);
      nowFavorited = true;
    }
    notifyListeners();
    await _persist();
    return nowFavorited;
  }

  Future<void> addFavorite(String symbol) async {
    final clean = symbol.toUpperCase();
    if (!_favorites.contains(clean)) {
      _favorites.add(clean);
      notifyListeners();
      await _persist();
    }
  }

  Future<void> removeFavorite(String symbol) async {
    final clean = symbol.toUpperCase();
    if (_favorites.remove(clean)) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    try {
      final encoded = jsonEncode(_favorites);
      await StorageService.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('FavoritesService persist error: $e');
    }
  }
}
