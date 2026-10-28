import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub 仓库地址，「访问项目」与「前往查看新版本」共用。
const String sukiGitHubRepoUrl = 'https://github.com/ucrvk/suki';

const String _repoSlug = 'ucrvk/suki';

/// 检查更新时的失败（网络不可达、GitHub 限流等）。
class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => 'AppUpdateException: $message';
}

/// 可比较的版本号：按数字段从左到右逐段比较，缺位补 0。
///
/// [parse] 只接受 `3.0.1`、`v3.0.1`、`1.2.0+1` 这类正式版本，
/// 带后缀的预发布版本（`-rc1`、`-alpha.1` 等）与非数字 tag 一律返回 null。
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts);

  static final RegExp _numberSegment = RegExp(r'^\d+$');
  static final RegExp _numericCore = RegExp(r'^\d+(\.\d+)*$');

  /// 解析版本号；不是正式版本时返回 null。
  static AppVersion? parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    final segments = text.split('+');
    if (segments.length > 2) return null;
    final core = segments.first;
    if (!_numericCore.hasMatch(core)) return null;
    final parts = core.split('.').map(int.parse).toList();
    if (segments.length == 2) {
      final build = segments.last;
      if (!_numberSegment.hasMatch(build)) return null;
      parts.add(int.parse(build));
    }
    return AppVersion(parts);
  }

  final List<int> parts;

  /// 大版本号（`3.0.2` → 3）。2.x 与 3.x 并行维护，检查更新时按它分线。
  int get major => parts.first;

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var index = 0; index < length; index++) {
      final left = index < parts.length ? parts[index] : 0;
      final right = index < other.parts.length ? other.parts[index] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }
}

/// 一次版本检查的结果。
@immutable
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestTag,
    required this.hasUpdate,
  });

  /// 当前版本号（原样展示，例如 `3.0.1+1`）。
  final String currentVersion;

  /// 当前版本线（同一大版本）上最高的正式 tag（例如 `v3.0.2`）；
  /// 没有可比较的 tag 时为 null。
  final String? latestTag;

  /// 最新正式 tag 高于当前版本。
  final bool hasUpdate;

  /// 新版本的发布页；没有新版本时为 null。
  Uri? get releaseUri {
    final tag = latestTag;
    if (!hasUpdate || tag == null) return null;
    return Uri.parse('$sukiGitHubRepoUrl/releases/tag/$tag');
  }
}

/// 拉取 GitHub 仓库的 tag 列表；抽成接口便于测试替换。
abstract interface class AppUpdateRemote {
  Future<List<String>> fetchTagNames();
}

class GitHubTagRemote implements AppUpdateRemote {
  GitHubTagRemote({
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _timeout = timeout;

  /// 一页最多 100 个 tag，按提交时间倒序，够用很久。
  static final Uri tagsEndpoint = Uri.parse(
    'https://api.github.com/repos/$_repoSlug/tags?per_page=100',
  );

  final http.Client _client;
  final Duration _timeout;

  @override
  Future<List<String>> fetchTagNames() async {
    final response = await _client
        .get(
          tagsEndpoint,
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw AppUpdateException('GitHub 返回 ${response.statusCode}');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! List) {
      throw const AppUpdateException('GitHub tag 列表格式不正确');
    }
    return [
      for (final item in payload)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  }
}

/// 版本更新检查：对比当前应用版本与 GitHub 上**同一版本线**（大版本相同）
/// 的最高正式 tag。
class AppUpdateService {
  AppUpdateService({
    AppUpdateRemote? remote,
    Future<String> Function()? currentVersion,
  }) : _remote = remote ?? GitHubTagRemote(),
       _currentVersion = currentVersion ?? readPlatformVersion;

  final AppUpdateRemote _remote;
  final Future<String> Function() _currentVersion;

  /// 读取打包进应用的版本号（含 build 号），例如 `3.0.1+1`。
  static Future<String> readPlatformVersion() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    return build.isEmpty ? info.version : '${info.version}+$build';
  }

  /// 对比 GitHub 上「与当前版本同一条版本线」的最高正式 tag。
  ///
  /// 项目 2.x 与 3.x 并行维护，所以 3.x 客户端只看 3.x 的 tag，
  /// 避免把另一条线的版本误报成更新。
  Future<AppUpdateInfo> check() async {
    final currentLabel = (await _currentVersion()).trim();
    final current = AppVersion.parse(currentLabel);
    final tags = await _remote.fetchTagNames();

    AppVersion? latest;
    String? latestTag;
    if (current != null) {
      for (final tag in tags) {
        final version = AppVersion.parse(tag);
        // 预发布（rc / alpha 等）与非法 tag 直接跳过。
        if (version == null) continue;
        // 只比较同一大版本线。
        if (version.major != current.major) continue;
        if (latest == null || version.compareTo(latest) > 0) {
          latest = version;
          latestTag = tag.trim();
        }
      }
    }

    return AppUpdateInfo(
      currentVersion: currentLabel,
      latestTag: latestTag,
      hasUpdate:
          current != null && latest != null && latest.compareTo(current) > 0,
    );
  }
}
