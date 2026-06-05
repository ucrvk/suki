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

  static const String _bookingOpenTopic = 'booking_open';
  static const String _webVapidKey =
      'BGFSbp0GHbHrUvofxGUL21UdIwT_lPp6YnCyTvv-IT0NOQrV9bdn2BBkKfnmGL9muTW1Sa9Ix1iO36joiZ2g3qI';
  static const String _lambdaBaseUrl =
      'https://tdpllor4isco2miay6o3vloewa0kilik.lambda-url.ap-northeast-3.on.aws';
  static const Duration _networkTimeout = Duration(seconds: 15);

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static bool _wired = false;
  static bool _bookingOpenTopicEnabled = false;

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
          throw NotificationPermissionDeniedException(
            message: '浏览器已拒绝通知权限',
          );
        case AuthorizationStatus.notDetermined:
          throw NotificationPermissionDeniedException(
            message: '浏览器尚未授予通知权限',
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
        await _applyBookingOpenTopicState(true);
      }
      return;
    }

    if (enabled) {
      await _applyBookingOpenTopicState(true);
      _bookingOpenTopicEnabled = true;
    } else {
      await _applyBookingOpenTopicState(false);
      _bookingOpenTopicEnabled = false;
    }
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
      if (!_bookingOpenTopicEnabled) return;
      try {
        await _applyBookingOpenTopicState(true);
      } catch (e) {
        debugPrint('FCM topic resubscribe failed: $e');
      }
    });
    _wired = true;
  }

  static Future<void> _applyBookingOpenTopicState(bool enabled) async {
    if (_isWebRuntime) {
      await _updateWebTopicSubscription(enabled);
      return;
    }

    if (enabled) {
      await _subscribeToTopic();
    } else {
      await _unsubscribeFromTopic();
    }
  }

  static Future<void> _subscribeToTopic() async {
    try {
      await _messaging.subscribeToTopic(_bookingOpenTopic);
      debugPrint('FCM topic subscribed: $_bookingOpenTopic');
    } catch (e) {
      debugPrint('FCM subscribeToTopic failed: $e');
      rethrow;
    }
  }

  static Future<void> _unsubscribeFromTopic() async {
    try {
      await _messaging.unsubscribeFromTopic(_bookingOpenTopic);
      debugPrint('FCM topic unsubscribed: $_bookingOpenTopic');
    } catch (e) {
      debugPrint('FCM unsubscribeFromTopic failed: $e');
      rethrow;
    }
  }

  static Future<void> _updateWebTopicSubscription(bool enabled) async {
    if (Uri.base.host != 'suki.wenwen12305.top') {
      throw StateError('Web Push 仅支持在 https://suki.wenwen12305.top 使用');
    }

    if (!enabled) {
      final token = await _messaging.getToken(vapidKey: _webVapidKey);
      if (token == null || token.trim().isEmpty) {
        debugPrint('FCM web unsubscribe skipped because token is missing');
        return;
      }

      await _callLambdaTopicApi(
        action: 'unsubscribe',
        token: token.trim(),
      );
      debugPrint('FCM web topic unsubscribed: $_bookingOpenTopic');
      return;
    }

    final token = await _messaging.getToken(vapidKey: _webVapidKey);
    if (token == null || token.trim().isEmpty) {
      throw StateError('无法获取 Web Push token');
    }

    await _callLambdaTopicApi(
      action: 'subscribe',
      token: token.trim(),
    );
    debugPrint('FCM web topic subscribed: $_bookingOpenTopic');
  }

  static Future<void> _callLambdaTopicApi({
    required String action,
    required String token,
  }) async {
    final response = await http
        .post(
          Uri.parse('$_lambdaBaseUrl/fcm/topic'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'action': action,
            'token': token,
            'topic': _bookingOpenTopic,
          }),
        )
        .timeout(_networkTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Lambda topic API failed (${response.statusCode}): ${response.body}',
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
