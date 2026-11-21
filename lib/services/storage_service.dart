import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'account_cloud_service.dart';

class StorageService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.alert_app/alarm',
  );
  static final Map<String, String> _memoryFallback = {};
  static bool _strictWrites = false;
  static String? _userScope;
  static bool _cloudReady = false;
  static bool _cloudSyncInProgress = false;
  static Timer? _cloudRetryTimer;
  static String? _cloudEmail;
  static String? _cloudDisplayName;
  static Future<void> Function()? onCloudSyncApplied;

  static String? get userScope => _userScope;
  static set userScope(String? value) {
    if (_userScope == value) return;
    AccountCloudService.stopListening();
    _cloudRetryTimer?.cancel();
    _cloudRetryTimer = null;
    _cloudSyncInProgress = false;
    _userScope = value;
    _cloudReady = false;
  }

  static String _scoped(String key) =>
      _userScope == null ? key : 'account_${_userScope}_$key';

  static Future<T> withStrictWrites<T>(Future<T> Function() operation) async {
    final previous = _strictWrites;
    _strictWrites = true;
    try {
      return await operation();
    } finally {
      _strictWrites = previous;
    }
  }

  static Future<void> setString(String key, String value) async {
    final unscopedKey = key;
    final previous = await getString(key);
    key = _scoped(key);
    _memoryFallback[key] = value;
    try {
      await _channel.invokeMethod('saveStorage', {'key': key, 'value': value});
    } catch (_) {
      if (_strictWrites) rethrow;
    }
    _queueCloudWrite(unscopedKey, value, previousValue: previous);
  }

  static Future<void> setStringRequired(String key, String value) async {
    final unscopedKey = key;
    final previous = await getString(key);
    key = _scoped(key);
    await _channel.invokeMethod('saveStorage', {'key': key, 'value': value});
    _memoryFallback[key] = value;
    _queueCloudWrite(unscopedKey, value, previousValue: previous);
  }

  static Future<String?> getString(String key) async {
    key = _scoped(key);
    try {
      final val = await _channel.invokeMethod<String>('loadStorage', {
        'key': key,
      });
      if (val != null) {
        _memoryFallback[key] = val;
        return val;
      }
    } catch (_) {}
    return _memoryFallback[key];
  }

  /// Reads local app cache without treating it as account-owned cloud data.
  static Future<String?> getLocalString(String key) async {
    key = _scoped(key);
    try {
      final value = await _channel.invokeMethod<String>('loadStorage', {
        'key': key,
      });
      if (value != null) _memoryFallback[key] = value;
      return value ?? _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  /// Persists an offline cache locally without syncing it to the user's account.
  static Future<void> setLocalString(String key, String value) async {
    key = _scoped(key);
    _memoryFallback[key] = value;
    try {
      await _channel.invokeMethod('saveStorage', {'key': key, 'value': value});
    } catch (_) {}
  }

  static Future<void> setLocalStringRequired(String key, String value) async {
    key = _scoped(key);
    await _channel.invokeMethod('saveStorage', {'key': key, 'value': value});
    _memoryFallback[key] = value;
  }

  static Future<String?> getLocalStringRequired(String key) async {
    key = _scoped(key);
    final value = await _channel.invokeMethod<String>('loadStorage', {
      'key': key,
    });
    if (value != null) _memoryFallback[key] = value;
    return value ?? _memoryFallback[key];
  }

  static Future<void> removeLocalRequired(String key) async {
    key = _scoped(key);
    await _channel.invokeMethod('removeStorage', {'key': key});
    _memoryFallback.remove(key);
  }

  static Future<String?> getStringRequired(String key) async {
    key = _scoped(key);
    final value = await _channel.invokeMethod<String>('loadStorage', {
      'key': key,
    });
    if (value != null) _memoryFallback[key] = value;
    return value;
  }

  static Future<Set<String>> listKeysWithPrefixRequired(String prefix) async {
    prefix = _scoped(prefix);
    final keys = await _channel.invokeMethod<List<dynamic>>(
      'listStorageKeysWithPrefix',
      {'prefix': prefix},
    );
    if (keys == null) {
      throw StateError('Native storage returned no key listing.');
    }
    return keys.map((key) => key as String).toSet();
  }

  static Future<void> remove(String key) async {
    final unscopedKey = key;
    final previous = await getString(key);
    key = _scoped(key);
    _memoryFallback.remove(key);
    try {
      await _channel.invokeMethod('removeStorage', {'key': key});
    } catch (_) {}
    _queueCloudDelete(unscopedKey, previousValue: previous);
  }

  /// Removes a persisted key and propagates platform/storage failures to callers.
  static Future<void> removeRequired(String key) async {
    final unscopedKey = key;
    final previous = await getString(key);
    key = _scoped(key);
    await _channel.invokeMethod('removeStorage', {'key': key});
    _memoryFallback.remove(key);
    _queueCloudDelete(unscopedKey, previousValue: previous);
  }

  static void _queueCloudWrite(
    String key,
    String value, {
    String? previousValue,
  }) {
    final uid = _userScope;
    if (uid != null && _cloudReady) {
      unawaited(
        AccountCloudService.writeValue(
          uid,
          key,
          value,
          previousValue: previousValue,
        ),
      );
    }
  }

  static void _queueCloudDelete(String key, {String? previousValue}) {
    final uid = _userScope;
    if (uid != null && _cloudReady) {
      unawaited(
        AccountCloudService.deleteValue(uid, key, previousValue: previousValue),
      );
    }
  }

  static Future<void> syncAccountWithCloud({
    required String? email,
    required String? displayName,
  }) async {
    final uid = _userScope;
    if (uid == null) return;
    if (_cloudSyncInProgress) return;
    _cloudEmail = email;
    _cloudDisplayName = displayName;
    _cloudReady = true;
    _cloudRetryTimer ??= Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(
        syncAccountWithCloud(
          email: _cloudEmail,
          displayName: _cloudDisplayName,
        ),
      );
    });
    _cloudSyncInProgress = true;
    final prefix = 'account_${uid}_';
    try {
      await AccountCloudService.syncAccount(
        uid: uid,
        email: email,
        displayName: displayName,
        listLocalKeys: () async {
          try {
            final keys = await _channel.invokeMethod<List<dynamic>>(
              'listStorageKeysWithPrefix',
              {'prefix': prefix},
            );
            if (keys != null) {
              return keys.map((key) => key as String).toSet();
            }
          } catch (_) {}
          return _memoryFallback.keys
              .where((key) => key.startsWith(prefix))
              .toSet();
        },
        readLocal: (key) async {
          try {
            final value = await _channel.invokeMethod<String>('loadStorage', {
              'key': key,
            });
            if (value != null) _memoryFallback[key] = value;
            return value ?? _memoryFallback[key];
          } catch (_) {
            return _memoryFallback[key];
          }
        },
        writeLocal: (key, value) async {
          try {
            await _channel.invokeMethod('saveStorage', {
              'key': key,
              'value': value,
            });
            _memoryFallback[key] = value;
            if (uid == _userScope) await onCloudSyncApplied?.call();
          } catch (error) {
            debugPrint('Local cloud restore failed for $key: $error');
          }
        },
      );
    } finally {
      _cloudSyncInProgress = false;
    }
  }

  static Future<void> setBool(String key, bool value) =>
      setString(key, value.toString());
  static Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final v = await getString(key);
    if (v == null) return defaultValue;
    return v.toLowerCase() == 'true';
  }

  static Future<void> setInt(String key, int value) =>
      setString(key, value.toString());
  static Future<int> getInt(String key, {int defaultValue = 0}) async {
    final v = await getString(key);
    if (v == null) return defaultValue;
    return int.tryParse(v) ?? defaultValue;
  }

  static Future<void> setDouble(String key, double value) =>
      setString(key, value.toString());
  static Future<double> getDouble(
    String key, {
    double defaultValue = 0.0,
  }) async {
    final v = await getString(key);
    if (v == null) return defaultValue;
    return double.tryParse(v) ?? defaultValue;
  }
}
