import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'supabase_service.dart';

@pragma('vm:entry-point')
Future<void> fcmBackgroundMessageHandler(RemoteMessage message) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await Firebase.initializeApp();
}

class FcmService {
  FcmService._();

  static const String _baseUrl = 'https://api.wenwen12305.top/suki';
  static const String _fcmEndpoint = '$_baseUrl/fcmconnect';

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  static bool _wired = false;
  static String? _lastRegisteredEmail;
  static String? _lastRegisteredFcmToken;
  static DateTime? _lastRegisteredAt;

  static bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initializeForCurrentUser() async {
    if (!_isAndroidRuntime) return;
    await _ensureWired();
    final user = SupabaseService.client.auth.currentUser;
    final email = (user?.email ?? '').trim();
    if (email.isEmpty) return;
    await registerForEmail(email);
  }

  static Future<void> registerForEmail(String email) async {
    if (!_isAndroidRuntime) return;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return;
    await _ensureWired();

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FCM permission denied, skip register');
      return;
    }

    final fcmToken = await _messaging.getToken();
    if (fcmToken == null || fcmToken.trim().isEmpty) {
      debugPrint('FCM token empty, skip register');
      return;
    }
    await _register(normalizedEmail, fcmToken.trim());
  }

  static Future<void> unregisterByEmail(String email) async {
    if (!_isAndroidRuntime) return;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return;

    final encodedEmail = Uri.encodeQueryComponent(normalizedEmail);
    final uri = Uri.parse('$_fcmEndpoint?email=$encodedEmail');
    try {
      final response = await http.delete(uri, headers: {
        'accept': 'application/json',
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('FCM unregister failed: ${response.statusCode} ${response.body}');
      } else {
        _lastRegisteredEmail = null;
        _lastRegisteredFcmToken = null;
        _lastRegisteredAt = null;
      }
    } catch (e) {
      debugPrint('FCM unregister exception: $e');
      rethrow;
    }
  }

  static Future<void> _ensureWired() async {
    if (_wired) return;
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
    _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
    });
    _tokenRefreshSub ??= _messaging.onTokenRefresh.listen((newToken) async {
      final user = SupabaseService.client.auth.currentUser;
      final email = (user?.email ?? '').trim();
      if (email.isEmpty || newToken.trim().isEmpty) return;
      try {
        await _register(email, newToken.trim(), bypassDedup: true);
      } catch (e) {
        debugPrint('FCM token refresh register failed: $e');
      }
    });
    _wired = true;
  }

  static Future<void> _register(
    String email,
    String fcmToken, {
    bool bypassDedup = false,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final accessToken = (session?.accessToken ?? '').trim();
    final refreshToken = (session?.refreshToken ?? '').trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      debugPrint('Session token missing, skip FCM register');
      return;
    }

    final now = DateTime.now();
    final hitDedup = !bypassDedup &&
        _lastRegisteredEmail == email &&
        _lastRegisteredFcmToken == fcmToken &&
        _lastRegisteredAt != null &&
        now.difference(_lastRegisteredAt!) < const Duration(minutes: 1);
    if (hitDedup) return;

    final response = await http.post(
      Uri.parse(_fcmEndpoint),
      headers: {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'token': accessToken,
        'refreshtoken': refreshToken,
        'fcm': fcmToken,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('FCM register failed: ${response.statusCode} ${response.body}');
    }

    _lastRegisteredEmail = email;
    _lastRegisteredFcmToken = fcmToken;
    _lastRegisteredAt = now;
  }
}

