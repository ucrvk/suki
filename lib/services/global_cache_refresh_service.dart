import 'package:flutter/foundation.dart';

import 'guestbook_cache_service.dart';
import 'intro_profile_service.dart';
import 'maid_catalog_cache_service.dart';
import 'reviews_cache_service.dart';

/// 应用冷启动时统一刷新一次公共数据缓存。
///
/// 只触发一次：重复调用会复用同一个 Future，不会重复请求。
class GlobalCacheRefreshService {
  GlobalCacheRefreshService._();

  static Future<void>? _launchRefresh;

  /// 每次全局刷新完成后自增，页面监听它来重新读取缓存并刷新界面。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 本次进程内最近一次全局刷新完成的时间。
  static DateTime? lastCompletedAt;

  /// 页面初始化时用来判断是否还需要自己再发一次后台刷新。
  static bool get recentlyCompleted {
    final completedAt = lastCompletedAt;
    return completedAt != null &&
        DateTime.now().difference(completedAt) < const Duration(seconds: 30);
  }

  /// 测试时注入自定义刷新任务。
  @visibleForTesting
  static List<Future<void> Function()>? debugRefreshers;

  static Future<void> refreshOnLaunch() {
    return _launchRefresh ??= _refreshAll();
  }

  static Future<void> _refreshAll() async {
    final startedAt = DateTime.now();
    try {
      final refreshers = debugRefreshers ?? _defaultRefreshers;
      await Future.wait([
        for (final refresh in refreshers) _ignoreErrors(refresh()),
      ]);
    } finally {
      lastCompletedAt = DateTime.now();
      revision.value++;
      final elapsed = lastCompletedAt!.difference(startedAt).inMilliseconds;
      debugPrint('[GlobalCacheRefresh] 刷新完成，耗时 ${elapsed}ms');
    }
  }

  static List<Future<void> Function()> get _defaultRefreshers => [
    () async {
      await MaidCatalogCacheService.refreshSnapshot();
    },
    () async {
      await IntroProfileService.refreshProfiles();
    },
    () async {
      await ReviewsCacheService.refreshSnapshot();
    },
    () async {
      await GuestbookCacheService.refreshSnapshot();
    },
  ];

  static Future<void> _ignoreErrors(Future<void> future) async {
    try {
      await future;
    } catch (error) {
      debugPrint('[GlobalCacheRefresh] 刷新失败: $error');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _launchRefresh = null;
    debugRefreshers = null;
    lastCompletedAt = null;
    revision.value = 0;
  }
}
