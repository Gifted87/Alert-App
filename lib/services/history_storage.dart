import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ai_models.dart';
import 'storage_service.dart';

class HistoryStorage {
  static const String _historyKey = 'ai_analysis_history';
  static final HistoryStorage _instance = HistoryStorage._internal();

  factory HistoryStorage() => _instance;
  HistoryStorage._internal();

  List<PipelineRunResult>? _cachedHistory;

  Future<List<PipelineRunResult>> getHistory() async {
    if (_cachedHistory != null) return _cachedHistory!;

    try {
      final raw = await StorageService.getString(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final list = decoded
            .map((e) => PipelineRunResult.fromJson(e as Map<String, dynamic>))
            .toList();

        // Sort newest first
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _cachedHistory = list;
        return list;
      }
    } catch (e) {
      debugPrint('HistoryStorage load error: $e');
    }

    _cachedHistory = [];
    return _cachedHistory!;
  }

  Future<void> saveAnalysis(PipelineRunResult result) async {
    final history = await getHistory();
    history.insert(0, result);

    // Keep last 100 analyses max to prevent bloat
    if (history.length > 100) {
      history.removeLast();
    }

    _cachedHistory = history;
    await _persistHistory(history);
  }

  Future<void> clearHistory() async {
    _cachedHistory = [];
    await StorageService.remove(_historyKey);
  }

  Future<void> _persistHistory(List<PipelineRunResult> history) async {
    try {
      final encoded = jsonEncode(history.map((e) => e.toJson()).toList());
      await StorageService.setString(_historyKey, encoded);
    } catch (e) {
      debugPrint('HistoryStorage save error: $e');
    }
  }
}
