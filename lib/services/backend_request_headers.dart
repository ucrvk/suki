import 'package:package_info_plus/package_info_plus.dart';

/// Headers for the self-hosted backend only. Supabase uses its own client.
class BackendRequestHeaders {
  BackendRequestHeaders._();

  static const String headerName = 'x-suki-app-version';
  static const String baseUrl = String.fromEnvironment(
    'SYSBOOKING_BASE_URL',
    defaultValue: 'https://api.wenwen12305.top/suki',
  );
  static String get normalizedBaseUrl =>
      baseUrl.replaceFirst(RegExp(r'/+$'), '');

  // Compatibility version used only when package metadata is unavailable.
  static String _version = '2.0';
  static Future<void>? _initializing;

  static Future<void> initialize() => _initializing ??= _loadVersion();

  static Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isNotEmpty) {
        _version = build.isEmpty ? version : '$version+$build';
      }
    } catch (_) {
      // Retain the compatibility version when package metadata is unavailable.
    }
  }

  static bool isBackendUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final base = Uri.tryParse(normalizedBaseUrl);
    if (uri == null ||
        base == null ||
        !uri.hasAuthority ||
        !base.hasAuthority) {
      return false;
    }
    return uri.scheme == base.scheme &&
        uri.host == base.host &&
        uri.port == base.port &&
        (uri.path == base.path || uri.path.startsWith('${base.path}/'));
  }

  static Map<String, String> forUrl(String url) =>
      isBackendUrl(url) ? {headerName: _version} : const {};
}
