import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores a privacy-safe audit trail for direct Supabase auth actions.
///
/// This feature is Android-only. Passwords and all token values are never
/// accepted by this API, so they cannot end up in exported logs.
class AuthLogService {
  AuthLogService._();

  static const String _storageKey = 'supabase_auth_audit_log_v1';
  static const MethodChannel _exportChannel = MethodChannel(
    'top.wenwen12305.suki/auth_log_export',
  );

  static Future<void> _pendingWrite = Future<void>.value();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> record({
    required String event,
    required String source,
    required bool succeeded,
    String? email,
    String? detail,
    Session? session,
    Session? usedSession,
  }) async {
    if (!isSupported) return;

    final entry = <String, String>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'source': source,
      'result': succeeded ? 'success' : 'failure',
      if (email != null && email.trim().isNotEmpty) 'email': _maskEmail(email),
      if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
      ..._sessionFingerprint(session),
      ..._sessionFingerprint(usedSession, prefix: 'used_'),
    };

    final nextWrite = _pendingWrite.then(
      (_) => _append(jsonEncode(entry)),
      onError: (_) => _append(jsonEncode(entry)),
    );
    _pendingWrite = nextWrite.catchError((_) {});
    await _pendingWrite;
  }

  static Future<String> export() async {
    if (!isSupported) {
      throw UnsupportedError('仅 Android 端支持导出登录日志');
    }

    await _pendingWrite;
    final preferences = await SharedPreferences.getInstance();
    final entries = preferences.getStringList(_storageKey) ?? const <String>[];
    if (entries.isEmpty) {
      throw StateError('暂无可导出的登录日志');
    }

    final buffer = StringBuffer()
      ..writeln('Suki Supabase Authentication Log')
      ..writeln('Exported at: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln();
    for (final rawEntry in entries) {
      final decoded = jsonDecode(rawEntry);
      if (decoded is! Map) continue;
      final entry = decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      buffer.writeln(
        '${entry['timestamp'] ?? '-'} | ${entry['result'] ?? '-'} | '
        '${entry['source'] ?? '-'} | ${entry['event'] ?? '-'}'
        '${entry['email'] == null ? '' : ' | email=${entry['email']}'}'
        '${entry['access_token_md5_last8'] == null ? '' : ' | access_token_md5_last8=${entry['access_token_md5_last8']}'}'
        '${entry['refresh_token_md5_last8'] == null ? '' : ' | refresh_token_md5_last8=${entry['refresh_token_md5_last8']}'}'
        '${entry['used_access_token_md5_last8'] == null ? '' : ' | used_access_token_md5_last8=${entry['used_access_token_md5_last8']}'}'
        '${entry['used_refresh_token_md5_last8'] == null ? '' : ' | used_refresh_token_md5_last8=${entry['used_refresh_token_md5_last8']}'}'
        '${entry['detail'] == null ? '' : ' | ${entry['detail']}'}',
      );
    }

    final fileName =
        'suki_auth_log_${DateTime.now().millisecondsSinceEpoch}.log';
    final exportedPath = await _exportChannel.invokeMethod<String>(
      'exportAuthLog',
      <String, String>{'fileName': fileName, 'content': buffer.toString()},
    );
    return exportedPath ?? 'Download/Suki/$fileName';
  }

  static String errorDetail(Object error) {
    if (error is AuthException) return error.message;
    return error.runtimeType.toString();
  }

  static Map<String, String> _sessionFingerprint(
    Session? session, {
    String prefix = '',
  }) {
    if (session == null) return const <String, String>{};

    final accessTokenHash = _tokenHashTail(session.accessToken);
    final refreshTokenHash = _tokenHashTail(session.refreshToken);
    final fingerprints = <String, String>{};
    if (accessTokenHash != null) {
      fingerprints['${prefix}access_token_md5_last8'] = accessTokenHash;
    }
    if (refreshTokenHash != null) {
      fingerprints['${prefix}refresh_token_md5_last8'] = refreshTokenHash;
    }
    return fingerprints;
  }

  static String? _tokenHashTail(String? token) {
    final normalized = token?.trim() ?? '';
    if (normalized.isEmpty) return null;
    final digest = md5.convert(utf8.encode(normalized)).toString();
    return digest.substring(digest.length - 8);
  }

  static Future<void> _append(String encodedEntry) async {
    final preferences = await SharedPreferences.getInstance();
    final entries = List<String>.from(
      preferences.getStringList(_storageKey) ?? const <String>[],
    )..add(encodedEntry);
    await preferences.setStringList(_storageKey, entries);
  }

  static String _maskEmail(String email) {
    final normalized = email.trim();
    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0 || atIndex == normalized.length - 1) return '***';

    final localPart = normalized.substring(0, atIndex);
    final domain = normalized.substring(atIndex + 1);
    if (localPart.length == 1) return '***@$domain';
    if (localPart.length == 2) return '${localPart[0]}***@$domain';
    return '${localPart[0]}***${localPart[localPart.length - 1]}@$domain';
  }
}
