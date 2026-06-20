import 'package:hive_flutter/hive_flutter.dart';

class MaidContentCacheStore {
  MaidContentCacheStore._();

  static const String boxName = 'maid_content_cache_v1';
  static Box<dynamic>? _box;
  static Future<void>? _initializing;

  static Future<void> ensureInitialized() async {
    if (_box != null) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }

    _initializing = () async {
      await Hive.initFlutter();
      _box = await Hive.openBox<dynamic>(boxName);
    }();

    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  static Box<dynamic> get _boxOrThrow {
    final box = _box;
    if (box == null) {
      throw StateError('MaidContentCacheStore is not initialized');
    }
    return box;
  }

  static bool containsKey(String key) {
    return _boxOrThrow.containsKey(key);
  }

  static T? read<T>(String key) {
    final value = _boxOrThrow.get(key);
    if (value is T) return value;
    return null;
  }

  static Future<void> write(String key, dynamic value) async {
    await _boxOrThrow.put(key, value);
  }

  static Future<void> delete(String key) async {
    await _boxOrThrow.delete(key);
  }

  static Future<void> clear() async {
    await _boxOrThrow.clear();
  }
}
