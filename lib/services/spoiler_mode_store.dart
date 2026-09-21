import 'package:flutter/foundation.dart';

import 'maid_content_cache_store.dart';

/// 剧透模式开关：开启时显示全部结局，关闭时只显示已解锁的结局。
abstract interface class SpoilerModeStore implements ValueListenable<bool> {
  @override
  bool get value;

  Future<void> setEnabled(bool enabled);
}

class HiveSpoilerModeStore extends ChangeNotifier implements SpoilerModeStore {
  HiveSpoilerModeStore._(this._enabled);

  static const String cacheKey = 'ending_spoiler_mode_v1';
  static HiveSpoilerModeStore? _instance;

  static Future<HiveSpoilerModeStore> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    await MaidContentCacheStore.ensureInitialized();
    final stored = MaidContentCacheStore.read<bool>(cacheKey) ?? false;
    return _instance = HiveSpoilerModeStore._(stored);
  }

  bool _enabled;

  @override
  bool get value => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    _enabled = enabled;
    notifyListeners();
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(cacheKey, enabled);
  }
}
