import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/drawing_models.dart';
import 'storage_service.dart';

class DrawingStorageService {
  static final DrawingStorageService _instance =
      DrawingStorageService._internal();
  factory DrawingStorageService() => _instance;
  DrawingStorageService._internal();

  final Map<String, List<ChartDrawing>> _cache = {};

  Future<void> init() async {}

  Future<List<ChartDrawing>> loadDrawings(String symbol) async {
    if (_cache.containsKey(symbol)) {
      return List.from(_cache[symbol]!);
    }

    try {
      final key = 'drawings_$symbol';
      final content = await StorageService.getString(key);
      if (content != null && content.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(content);
        final drawings = jsonList
            .map((item) => ChartDrawing.fromJson(item as Map<String, dynamic>))
            .toList();
        _cache[symbol] = drawings;
        return drawings;
      }
    } catch (e) {
      debugPrint('Error loading drawings for $symbol: $e');
    }

    _cache[symbol] = [];
    return [];
  }

  Future<void> saveDrawings(String symbol, List<ChartDrawing> drawings) async {
    _cache[symbol] = List.from(drawings);
    try {
      final key = 'drawings_$symbol';
      final jsonString = jsonEncode(drawings.map((d) => d.toJson()).toList());
      await StorageService.setString(key, jsonString);
    } catch (e) {
      debugPrint('Error saving drawings for $symbol: $e');
    }
  }

  Future<void> clearDrawings(String symbol) async {
    _cache[symbol] = [];
    try {
      final key = 'drawings_$symbol';
      await StorageService.remove(key);
    } catch (_) {}
  }
}
