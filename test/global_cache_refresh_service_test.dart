import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/services/global_cache_refresh_service.dart';

void main() {
  setUp(GlobalCacheRefreshService.resetForTest);
  tearDown(GlobalCacheRefreshService.resetForTest);

  test('runs every refresher only once across repeated launch calls', () async {
    var firstCalls = 0;
    var secondCalls = 0;
    GlobalCacheRefreshService.debugRefreshers = [
      () async {
        firstCalls++;
      },
      () async {
        secondCalls++;
      },
    ];

    final first = GlobalCacheRefreshService.refreshOnLaunch();
    final second = GlobalCacheRefreshService.refreshOnLaunch();
    await Future.wait([first, second]);

    await GlobalCacheRefreshService.refreshOnLaunch();

    expect(firstCalls, 1);
    expect(secondCalls, 1);
    expect(GlobalCacheRefreshService.revision.value, 1);
    expect(GlobalCacheRefreshService.recentlyCompleted, isTrue);
  });

  test('increments the revision only after the refresh finishes', () async {
    final gate = Completer<void>();
    GlobalCacheRefreshService.debugRefreshers = [
      () async {
        await gate.future;
      },
    ];

    final refresh = GlobalCacheRefreshService.refreshOnLaunch();
    expect(GlobalCacheRefreshService.revision.value, 0);
    expect(GlobalCacheRefreshService.recentlyCompleted, isFalse);

    gate.complete();
    await refresh;

    expect(GlobalCacheRefreshService.revision.value, 1);
    expect(GlobalCacheRefreshService.recentlyCompleted, isTrue);
  });

  test('keeps refreshing the rest when one refresher fails', () async {
    var completed = 0;
    GlobalCacheRefreshService.debugRefreshers = [
      () async {
        throw StateError('boom');
      },
      () async {
        completed++;
      },
    ];

    await GlobalCacheRefreshService.refreshOnLaunch();

    expect(completed, 1);
  });

  test('prints a completion message to the console', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = original);

    GlobalCacheRefreshService.debugRefreshers = [() async {}];
    await GlobalCacheRefreshService.refreshOnLaunch();

    expect(logs.any((line) => line.contains('刷新完成')), isTrue);
  });

  test('starts all refreshers before awaiting any of them', () async {
    final started = <String>[];
    GlobalCacheRefreshService.debugRefreshers = [
      () async {
        started.add('catalog');
        await Future<void>.delayed(Duration.zero);
      },
      () async {
        started.add('intro');
        await Future<void>.delayed(Duration.zero);
      },
      () async {
        started.add('reviews');
        await Future<void>.delayed(Duration.zero);
      },
      () async {
        started.add('guestbook');
        await Future<void>.delayed(Duration.zero);
      },
    ];

    await GlobalCacheRefreshService.refreshOnLaunch();

    expect(started, ['catalog', 'intro', 'reviews', 'guestbook']);
  });
}
