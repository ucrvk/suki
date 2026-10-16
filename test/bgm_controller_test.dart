import 'package:flutter_test/flutter_test.dart';
import 'package:suki/services/bgm_controller.dart';

void main() {
  test(
    'stays silent by default and loops the bundled asset when enabled',
    () async {
      final engine = _FakeEngine();
      final persisted = <bool>[];
      final controller = AssetBgmController(
        engine: engine,
        persist: (enabled) async => persisted.add(enabled),
      );

      expect(controller.value, isFalse);
      expect(engine.played, isEmpty);

      await controller.setEnabled(true);
      expect(controller.value, isTrue);
      expect(engine.played, [AssetBgmController.assetPath]);
      expect(persisted, [true]);

      await controller.setEnabled(false);
      expect(controller.value, isFalse);
      expect(engine.stopCalls, 1);
      expect(persisted, [true, false]);
    },
  );

  test('keeps a single player when toggled repeatedly', () async {
    final engine = _FakeEngine();
    final controller = AssetBgmController(engine: engine);

    await controller.setEnabled(true);
    await controller.setEnabled(true);
    expect(engine.played, hasLength(1));

    await controller.setEnabled(false);
    await controller.setEnabled(false);
    expect(engine.stopCalls, 1);
  });

  test('retries a blocked autoplay until the first user interaction', () async {
    final engine = _FakeEngine()..failPlay = true;
    final controller = AssetBgmController(engine: engine, enabled: true);

    // 浏览器拦截自动播放：失败后仍保留待补播标记。
    await controller.resumeIfNeeded();
    await controller.resumeIfNeeded();
    expect(engine.played, hasLength(2));

    engine.failPlay = false;
    await controller.resumeIfNeeded();
    expect(engine.played, hasLength(3));

    // 已经在播放，之后的交互不再重复触发。
    await controller.resumeIfNeeded();
    expect(engine.played, hasLength(3));
  });

  test('does not resume while the switch is off', () async {
    final engine = _FakeEngine();
    final controller = AssetBgmController(engine: engine);

    await controller.resumeIfNeeded();
    expect(engine.played, isEmpty);

    // 失败过的播放被用户关掉后，也不再补播。
    final failing = _FakeEngine()..failPlay = true;
    final other = AssetBgmController(engine: failing, enabled: true);
    await other.resumeIfNeeded();
    await other.setEnabled(false);
    failing.failPlay = false;
    await other.resumeIfNeeded();
    expect(failing.played, hasLength(1));
    expect(failing.stopCalls, 1);
  });
}

class _FakeEngine implements BgmAudioEngine {
  final List<String> played = [];
  int stopCalls = 0;
  bool failPlay = false;

  @override
  Future<void> playLoop(String assetPath) async {
    played.add(assetPath);
    if (failPlay) throw StateError('autoplay blocked');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}
