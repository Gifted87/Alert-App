import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/ai_models.dart';
import 'storage_service.dart';

/// Shared admin-published strategy catalog. Firestore is the online source;
/// local-only cached JSON keeps the last published catalog available offline.
class StrategyCatalogService extends ChangeNotifier {
  StrategyCatalogService._();

  static final StrategyCatalogService instance = StrategyCatalogService._();

  static const _strategiesCacheKey = 'shared_strategy_catalog_v1';
  static const _specialistsCacheKey = 'shared_specialist_catalog_v1';
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _uid;
  List<TradingStrategy> _strategies = const [];
  List<SpecialistAgentConfig> _specialists = const [];
  bool _hasCatalogSnapshot = false;

  List<TradingStrategy> get strategies => List.unmodifiable(_strategies);
  List<SpecialistAgentConfig> get specialists =>
      List.unmodifiable(_specialists);
  bool get hasCatalogSnapshot => _hasCatalogSnapshot;
  Future<void> Function()? onCatalogChanged;

  Future<void> initialize(String uid) async {
    if (_uid == uid && _subscription != null) return;
    await _subscription?.cancel();
    _uid = uid;
    _strategies = await _readStrategiesCache();
    _specialists = await _readSpecialistsCache();
    // An empty published collection means no shared catalog has been
    // published yet. Preserve the app's bundled/user-local definitions rather
    // than interpreting the empty remote result as a delete-all command.
    _hasCatalogSnapshot = _strategies.isNotEmpty || _specialists.isNotEmpty;
    notifyListeners();

    _subscription = _db
        .collection('strategyCatalog')
        .where('status', isEqualTo: 'published')
        .snapshots()
        .listen(
          (snapshot) => unawaited(_applySnapshot(snapshot)),
          onError: (Object error) {
            debugPrint('Shared strategy catalog sync failed: $error');
          },
        );
  }

  Future<void> _applySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final strategies = <TradingStrategy>[];
    final specialists = <SpecialistAgentConfig>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      final payload = data['payload'];
      if (payload is! String) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map) continue;
        final json = Map<String, dynamic>.from(decoded);
        if (data['type'] == 'strategy') {
          strategies.add(TradingStrategy.fromJson(json));
        } else if (data['type'] == 'specialist') {
          specialists.add(SpecialistAgentConfig.fromJson(json));
        }
      } catch (error) {
        debugPrint('Skipping invalid shared catalog entry: $error');
      }
    }

    // A published specialist is the authoritative definition for any
    // specialist with the same ID embedded in a published strategy.
    final specialistById = {for (final item in specialists) item.id: item};
    final refreshedStrategies = strategies.map((strategy) {
      final embedded = strategy.specialists.map(
        (item) => specialistById[item.id] ?? item,
      );
      return strategy.copyWith(specialists: embedded.toList());
    }).toList();

    _strategies = refreshedStrategies;
    _specialists = specialists;
    _hasCatalogSnapshot =
        refreshedStrategies.isNotEmpty || specialists.isNotEmpty;
    await Future.wait([
      StorageService.setLocalString(
        _strategiesCacheKey,
        jsonEncode(refreshedStrategies.map((item) => item.toJson()).toList()),
      ),
      StorageService.setLocalString(
        _specialistsCacheKey,
        jsonEncode(specialists.map((item) => item.toJson()).toList()),
      ),
    ]);
    await onCatalogChanged?.call();
    notifyListeners();
  }

  Future<List<TradingStrategy>> _readStrategiesCache() async {
    final raw = await StorageService.getLocalString(_strategiesCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (item) => TradingStrategy.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SpecialistAgentConfig>> _readSpecialistsCache() async {
    final raw = await StorageService.getLocalString(_specialistsCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (item) =>
                SpecialistAgentConfig.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _uid = null;
    _strategies = const [];
    _specialists = const [];
    _hasCatalogSnapshot = false;
  }
}
