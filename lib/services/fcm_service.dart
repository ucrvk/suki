import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
Future<void> fcmBackgroundMessageHandler(RemoteMessage message) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  await Firebase.initializeApp();
}

class FcmService {
  FcmService._();

  static const String _subscriptionBaseUrl = 'https://api.wenwen12305.top/suki';
  static const String _webVapidKey =
      'BGFSbp0GHbHrUvofxGUL21UdIwT_lPp6YnCyTvv-IT0NOQrV9bdn2BBkKfnmGL9muTW1Sa9Ix1iO36joiZ2g3qI';
  static const Duration _networkTimeout = Duration(seconds: 15);

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static bool _wired = false;
  static bool _bookingOpenTopicEnabled = false;
  static String? _lastKnownToken;

  static bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isWebRuntime => kIsWeb;
  static bool get _isPushRuntime => _isAndroidRuntime || _isWebRuntime;

  static Future<void> initialize() async {
    if (!_isPushRuntime) return;
    await _ensureWired();
  }

  static Future<void> requestNotificationPermission() async {
    if (_isWebRuntime) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          return;
        case AuthorizationStatus.denied:
        case AuthorizationStatus.notDetermined:
          throw NotificationPermissionDeniedException(
            message: '浏览器未授予通知权限',
          );
      }
    }

    if (!_isAndroidRuntime) return;

    final currentStatus = await Permission.notification.status;
    if (currentStatus.isGranted) return;

    final requested = await Permission.notification.request();
    if (requested.isGranted || requested.isLimited) return;

    throw NotificationPermissionDeniedException(
      message: requested.isPermanentlyDenied || requested.isRestricted
          ? '通知权限被系统拒绝'
          : '通知权限已被拒绝',
      needsAppSettings:
          requested.isPermanentlyDenied || requested.isRestricted,
      permissionStatus: requested,
    );
  }

  static Future<void> setBookingOpenTopicEnabled(bool enabled) async {
    if (!_isPushRuntime) return;
    await _ensureWired();

    if (enabled == _bookingOpenTopicEnabled) {
      if (enabled) {
        await _syncSubscriptionState(enabled: true);
      }
      return;
    }

    await _syncSubscriptionState(enabled: enabled);
    _bookingOpenTopicEnabled = enabled;
  }

  static Future<void> _ensureWired() async {
    if (_wired) return;

    if (_isAndroidRuntime) {
      FirebaseMessaging.onBackgroundMessage(fcmBackgroundMessageHandler);
    }

    _foregroundMessageSub ??= FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground message: ${message.messageId}');
    });
    _tokenRefreshSub ??= _messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.trim().isEmpty) return;

      final previousToken = _lastKnownToken?.trim();
      _lastKnownToken = newToken.trim();

      if (!_bookingOpenTopicEnabled) return;

      try {
        if (previousToken != null &&
            previousToken.isNotEmpty &&
            previousToken != newToken.trim()) {
          await _callSubscriptionApi(
            method: 'DELETE',
            token: previousToken,
          );
        }
        await _callSubscriptionApi(
          method: 'POST',
          token: newToken.trim(),
        );
      } catch (e) {
        debugPrint('FCM token refresh resubscribe failed: $e');
      }
    });
    _wired = true;
  }

  static Future<void> _syncSubscriptionState({required bool enabled}) async {
    final token = await _getCurrentToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('无法获取 FCM token');
    }

    final normalizedToken = token.trim();
    final previousToken = _lastKnownToken?.trim();
    _lastKnownToken = normalizedToken;

    if (!enabled) {
      try {
        await _callSubscriptionApi(
          method: 'DELETE',
          token: normalizedToken,
        );
      } finally {
        if (previousToken != null &&
            previousToken.isNotEmpty &&
            previousToken != normalizedToken) {
          try {
            await _callSubscriptionApi(
              method: 'DELETE',
              token: previousToken,
            );
          } catch (e) {
            debugPrint('FCM previous token unsubscribe failed: $e');
          }
        }
      }
      return;
    }

    if (previousToken != null &&
        previousToken.isNotEmpty &&
        previousToken != normalizedToken) {
      try {
        await _callSubscriptionApi(
          method: 'DELETE',
          token: previousToken,
        );
      } catch (e) {
        debugPrint('FCM previous token cleanup failed: $e');
      }
    }

    await _callSubscriptionApi(
      method: 'POST',
      token: normalizedToken,
    );
  }

  static Future<String?> _getCurrentToken() {
    if (_isWebRuntime) {
      return _messaging.getToken(vapidKey: _webVapidKey);
    }
    return _messaging.getToken();
  }

  static Future<String?> getCurrentToken() => _getCurrentToken();

  static Future<void> _callSubscriptionApi({
    required String method,
    required String token,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('$_subscriptionBaseUrl/subscription'),
    );
    request.headers.addAll(const {
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode(<String, dynamic>{
      'token': token,
    });

    final response = await http.Response.fromStream(await request.send())
        .timeout(_networkTimeout);
    final responseBody = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Subscription API failed (${response.statusCode}): $responseBody',
      );
    }
  }
}

class NotificationPermissionDeniedException implements Exception {
  NotificationPermissionDeniedException({
    required this.message,
    this.needsAppSettings = false,
    this.permissionStatus,
  });

  final String message;
  final bool needsAppSettings;
  final PermissionStatus? permissionStatus;

  @override
  String toString() => message;
}
