import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'maid_content_cache_store.dart';

/// 背景音乐开关：开启时循环播放在线 BGM，关闭时立即停止。
/// 默认关闭；偏好写入本地缓存，下次启动沿用。
abstract interface class BgmController implements ValueListenable<bool> {
  @override
  bool get value;

  /// 切换开关：通知界面、启停播放并写入本地偏好。
  Future<void> setEnabled(bool enabled);

  /// 浏览器可能拦截首屏自动播放；首次用户交互后补一次播放。
  /// 没有待补播的内容时是空操作。
  Future<void> resumeIfNeeded();
}

/// 只抽出播放能力，便于测试时替掉真实音频引擎。
abstract interface class BgmAudioEngine {
  Future<void> playLoop(String url);

  Future<void> stop();
}

/// `audioplayers` 实现；按 URL 流式播放（服务端支持 range 请求）。
class AudioPlayerBgmEngine implements BgmAudioEngine {
  AudioPlayerBgmEngine() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playLoop(String url) async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(UrlSource(url));
  }

  @override
  Future<void> stop() => _player.stop();
}

class RemoteBgmController extends ChangeNotifier implements BgmController {
  RemoteBgmController({
    required BgmAudioEngine engine,
    bool enabled = false,
    Future<void> Function(bool enabled)? persist,
  }) : _engine = engine,
       _enabled = enabled,
       _needsResume = enabled,
       _persist = persist;

  /// 在线 BGM 地址（由服务端托管，不随包分发）。
  static const String bgmUrl = 'https://vrcsuki.chat/audio/witch/bgm.mp3';
  static const String cacheKey = 'bgm_enabled_v1';

  static RemoteBgmController? _instance;

  /// 全局单例：读取本地偏好（缺省关闭），已开启时尝试续播。
  static Future<RemoteBgmController> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    await MaidContentCacheStore.ensureInitialized();
    final stored = MaidContentCacheStore.read<bool>(cacheKey) ?? false;
    final controller = RemoteBgmController(
      engine: AudioPlayerBgmEngine(),
      enabled: stored,
      persist: (enabled) async {
        await MaidContentCacheStore.ensureInitialized();
        await MaidContentCacheStore.write(cacheKey, enabled);
      },
    );
    if (stored) unawaited(controller.resumeIfNeeded());
    return _instance = controller;
  }

  final BgmAudioEngine _engine;
  final Future<void> Function(bool enabled)? _persist;

  bool _enabled;
  bool _needsResume;

  @override
  bool get value => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    _enabled = enabled;
    _needsResume = enabled;
    notifyListeners();
    if (enabled) {
      await resumeIfNeeded();
    } else {
      await _stop();
    }
    await _persist?.call(enabled);
  }

  @override
  Future<void> resumeIfNeeded() async {
    if (!_enabled || !_needsResume) return;
    try {
      await _engine.playLoop(bgmUrl);
      _needsResume = false;
    } catch (_) {
      // 浏览器自动播放限制 / 网络或音频设备暂不可用：保留待补播标记，界面照常。
      _needsResume = true;
    }
  }

  Future<void> _stop() async {
    _needsResume = false;
    try {
      await _engine.stop();
    } catch (_) {
      // 停止失败无需打扰用户。
    }
  }
}
