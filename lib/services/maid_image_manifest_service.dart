import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

import 'maid_content_cache_store.dart';

class MaidImageManifestService {
  MaidImageManifestService._();

  static const String baseUrl = 'http://127.0.0.1:6988/';
  static const String _manifestPath = 'manifest.json';
  static const String _imagesPath = 'images';
  static const String _cacheKey = 'maid_image_manifest';

  static Map<String, String>? _manifestCache;

  static Future<Map<String, String>> fetchManifest({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _manifestCache != null) {
      return _manifestCache!;
    }

    if (!forceRefresh) {
      try {
        await MaidContentCacheStore.ensureInitialized();
        if (MaidContentCacheStore.containsKey(_cacheKey)) {
          final cached = MaidContentCacheStore.read<Map>(_cacheKey);
          if (cached != null) {
            final parsed = <String, String>{};
            for (final entry in cached.entries) {
              final key = entry.key.toString().trim();
              final value = entry.value.toString().trim();
              if (key.isEmpty || value.isEmpty) continue;
              parsed[key] = value;
            }
            _manifestCache = parsed;
            return _manifestCache!;
          }
        }
      } catch (e, st) {
        dev.log(
          'Failed to read cached image manifest: $e',
          name: 'MaidImageManifestService',
          stackTrace: st,
        );
      }
    }

    final manifestUri = Uri.parse('$baseUrl$_manifestPath');
    try {
      final response = await http.get(manifestUri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('manifest 结构不是 JSON object');
      }

      final parsed = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value.toString().trim();
        if (key.isEmpty || value.isEmpty) continue;
        parsed[key] = value;
      }

      _manifestCache = parsed;
      try {
        await MaidContentCacheStore.ensureInitialized();
        await MaidContentCacheStore.write(_cacheKey, parsed);
      } catch (e, st) {
        dev.log(
          'Failed to cache image manifest: $e',
          name: 'MaidImageManifestService',
          stackTrace: st,
        );
      }
      return parsed;
    } catch (e, st) {
      dev.log(
        'Failed to fetch image manifest: $e',
        name: 'MaidImageManifestService',
        stackTrace: st,
      );
      _manifestCache ??= <String, String>{};
      return _manifestCache!;
    }
  }

  static String resolveImageUrl(String vrcid) {
    final id = vrcid.trim();
    if (id.isEmpty) return '';

    final sha1 = _manifestCache?[id]?.trim() ?? '';
    if (sha1.isEmpty) return '';
    return '$baseUrl$_imagesPath/$id-$sha1.avif';
  }

  static void clearCache() {
    _manifestCache = null;
  }
}
