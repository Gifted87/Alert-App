import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Account scoped, per-record Firestore persistence. Local storage remains the
/// UI source of truth; Firestore's Android persistence queues these writes
/// while offline and applies them when connectivity returns.
class AccountCloudService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final Map<
    String,
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  >
  _listeners = {};
  static final Set<String> _applyingRemote = {};

  static const Map<String, String> _recordCollections = {
    'saved_alerts': 'alerts',
    'saved_history': 'alertHistory',
    'ai_trading_strategies': 'aiStrategies',
    'ai_specialist_agents': 'aiSpecialists',
    'ai_recent_strategy_runs': 'aiStrategyRuns',
    'ai_analysis_history': 'aiAnalysisHistory',
  };

  static String _docId(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);
  static bool _isSecret(String key) {
    final normalized = key.toLowerCase();
    if (normalized == 'ai_llm_config' || normalized == 'ai_realmarket_config') {
      return true;
    }
    return [
      'apikey',
      'api_key',
      'secret',
      'password',
      'credential',
      'token',
    ].any(normalized.contains);
  }

  static Future<void> _removeLegacyProviderConfigs(String uid) async {
    final appData = _user(uid).collection('appData');
    final batch = _db.batch();
    batch.delete(appData.doc(_docId('ai_llm_config')));
    batch.delete(appData.doc(_docId('ai_realmarket_config')));
    await batch.commit();
  }

  static Future<void> writeValue(
    String uid,
    String key,
    String value, {
    String? previousValue,
  }) async {
    if (_applyingRemote.contains('$uid:$key') || _isSecret(key)) return;
    final collection = _recordCollections[key];
    if (collection == null) {
      if (key.startsWith('setting_')) {
        await _user(uid).collection('settings').doc(_docId(key)).set({
          'key': key,
          'value': value,
          'schemaVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _user(uid).collection('appData').doc(_docId(key)).set({
          'key': key,
          'value': value,
          'schemaVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return;
    }
    final rows = _decodeList(value);
    final records = _user(uid).collection(collection);
    final batch = _db.batch();
    for (final row in rows) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      batch.set(records.doc(_docId(id)), {
        'id': id,
        'payload': jsonEncode(row),
        'schemaVersion': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    final ids = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    if (previousValue != null) {
      for (final row in _decodeList(previousValue)) {
        final id = row['id']?.toString();
        if (id != null && !ids.contains(id)) {
          batch.delete(records.doc(_docId(id)));
        }
      }
    }
    await batch.commit();
  }

  static Future<void> deleteValue(
    String uid,
    String key, {
    String? previousValue,
  }) async {
    if (_applyingRemote.contains('$uid:$key') || _isSecret(key)) return;
    final collection = _recordCollections[key];
    if (collection != null) {
      final records = _user(uid).collection(collection);
      final batch = _db.batch();
      if (previousValue != null) {
        for (final row in _decodeList(previousValue)) {
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) {
            batch.delete(records.doc(_docId(id)));
          }
        }
      } else {
        final snapshot = await records.get();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();
      return;
    }
    final collectionName = key.startsWith('setting_') ? 'settings' : 'appData';
    await _user(uid).collection(collectionName).doc(_docId(key)).delete();
  }

  static List<Map<String, dynamic>> _decodeList(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> removeLegacyDemoAlerts(String uid) async {
    final alerts = _user(uid).collection('alerts');
    final batch = _db.batch();
    const bundled = <String, (String, String, double)>{
      'alert_1': ('EURUSD', 'Breakout above resistance', 1.152),
      'alert_2': ('EURUSD', 'Support breakdown monitor', 1.145),
      'alert_3': ('GBPUSD', 'Major swing high breakout', 1.342),
    };
    for (final entry in bundled.entries) {
      final ref = alerts.doc(_docId(entry.key));
      try {
        final snapshot = await ref.get();
        final raw = snapshot.data()?['payload'];
        if (raw is! String) continue;
        final payload = jsonDecode(raw);
        if (payload is! Map) continue;
        final expected = entry.value;
        final price = (payload['targetPrice'] as num?)?.toDouble();
        if (payload['id'] == entry.key &&
            payload['symbol'] == expected.$1 &&
            payload['note'] == expected.$2 &&
            price == expected.$3) {
          batch.delete(ref);
        }
      } catch (_) {
        // Offline cache misses are retried by the normal background sync.
      }
    }
    await batch.commit();
  }

  static Future<void> syncAccount({
    required String uid,
    required String? email,
    required String? displayName,
    required Future<Set<String>> Function() listLocalKeys,
    required Future<String?> Function(String key) readLocal,
    required Future<void> Function(String key, String value) writeLocal,
  }) async {
    final profile = _user(uid);
    final profileData = <String, Object?>{
      'uid': uid,
      'email': email ?? FirebaseAuth.instance.currentUser?.email ?? '',
      'displayName':
          displayName ?? FirebaseAuth.instance.currentUser?.displayName ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await profile.set(profileData, SetOptions(merge: true));
    // Builds before the account layer seeded these bundled examples into each
    // user's alerts. Remove only those reserved IDs during account migration.
    await removeLegacyDemoAlerts(uid);
    // Remove provider credentials written by older versions before any local
    // key migration runs; these values must never sync between accounts.
    await _removeLegacyProviderConfigs(uid);

    final keys = await listLocalKeys();
    for (final key in keys) {
      final prefix = 'account_${uid}_';
      final logicalKey = key.startsWith(prefix)
          ? key.substring(prefix.length)
          : null;
      if (logicalKey == null || _isSecret(logicalKey)) continue;
      final local = await readLocal(key);
      if (local != null) await writeValue(uid, logicalKey, local);
    }

    for (final key in _recordCollections.keys) {
      _listenCollection(uid, key, _recordCollections[key]!, writeLocal);
    }
    _listenSettings(uid, writeLocal);
    _listenLegacy(uid, writeLocal);
  }

  static void stopListening() {
    for (final sub in _listeners.values) {
      unawaited(sub.cancel());
    }
    _listeners.clear();
    _applyingRemote.clear();
  }

  static void _listenCollection(
    String uid,
    String key,
    String collection,
    Future<void> Function(String, String) writeLocal,
  ) {
    final id = '$uid:$collection';
    if (_listeners.containsKey(id)) return;
    _listeners[id] = _user(uid).collection(collection).snapshots().listen(
      (snapshot) async {
        if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty) return;
        final rows = <Map<String, dynamic>>[];
        for (final doc in snapshot.docs) {
          try {
            rows.add(
              jsonDecode(doc.data()['payload'] as String)
                  as Map<String, dynamic>,
            );
          } catch (_) {}
        }
        _applyingRemote.add('$uid:$key');
        try {
          await writeLocal('account_${uid}_$key', jsonEncode(rows));
        } finally {
          _applyingRemote.remove('$uid:$key');
        }
      },
      onError: (Object error) =>
          debugPrint('Firestore $collection listener error: $error'),
    );
  }

  static void _listenSettings(
    String uid,
    Future<void> Function(String, String) writeLocal,
  ) {
    const collection = 'settings';
    final id = '$uid:$collection';
    if (_listeners.containsKey(id)) return;
    _listeners[id] = _user(uid).collection(collection).snapshots().listen(
      (snapshot) async {
        if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty) return;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final key = data['key'];
          final value = data['value'];
          if (key is! String || value is! String || _isSecret(key)) continue;
          _applyingRemote.add('$uid:$key');
          try {
            await writeLocal('account_${uid}_$key', value);
          } finally {
            _applyingRemote.remove('$uid:$key');
          }
        }
      },
      onError: (Object error) =>
          debugPrint('Firestore settings listener error: $error'),
    );
  }

  static void _listenLegacy(
    String uid,
    Future<void> Function(String, String) writeLocal,
  ) {
    const collection = 'appData';
    final id = '$uid:$collection';
    if (_listeners.containsKey(id)) return;
    _listeners[id] = _user(uid).collection(collection).snapshots().listen(
      (snapshot) async {
        if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty) return;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final key = data['key'];
          final value = data['value'];
          if (key is! String ||
              value is! String ||
              _isSecret(key) ||
              _recordCollections.containsKey(key) ||
              key.startsWith('setting_')) {
            continue;
          }
          _applyingRemote.add('$uid:$key');
          try {
            await writeLocal('account_${uid}_$key', value);
          } finally {
            _applyingRemote.remove('$uid:$key');
          }
        }
      },
      onError: (Object error) =>
          debugPrint('Firestore appData listener error: $error'),
    );
  }
}
