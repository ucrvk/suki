import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QueueTabSettings {
  QueueTabSettings._();

  static const String key = 'queue_tab_enabled';
  static final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(false);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    enabledNotifier.value = prefs.getBool(key) ?? false;
    _loaded = true;
  }

  static Future<void> setEnabled(bool enabled) async {
    enabledNotifier.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, enabled);
    _loaded = true;
  }
}
