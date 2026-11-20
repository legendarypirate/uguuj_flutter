import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmanager/color/color.dart';
import 'package:taskmanager/firebase_options.dart';

const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'Task manager push notifications',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Fired when a push arrives while the app is in the foreground (refresh inbox badge).
final StreamController<RemoteMessage> _foregroundStreamController =
    StreamController<RemoteMessage>.broadcast();

/// Safe init: Android may auto-init from google-services.json before Dart runs.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
}

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
  );
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await _localNotifications.initialize(initSettings);

  if (Platform.isAndroid) {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  } else if (Platform.isIOS) {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final data = message.data;
  final notification = message.notification;
  final title = (notification?.title ??
          data['title']?.toString() ??
          'Мэдэгдэл')
      .trim();
  final body = (notification?.body ??
          data['body']?.toString() ??
          data['message']?.toString() ??
          '')
      .trim();
  if (title.isEmpty && body.isEmpty) return;

  if (Platform.isIOS) {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  const androidDetails = AndroidNotificationDetails(
    'high_importance_channel',
    'High Importance Notifications',
    channelDescription: 'Task manager push notifications',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    interruptionLevel: InterruptionLevel.active,
  );

  try {
    await _localNotifications.show(
      message.hashCode,
      title.isNotEmpty ? title : 'Мэдэгдэл',
      body.isNotEmpty ? body : title,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: jsonEncode(data),
    );
    if (kDebugMode) {
      print('PushService: showed foreground notification "$title"');
    }
  } catch (e) {
    if (kDebugMode) {
      print('PushService: local notification failed: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await ensureFirebaseInitialized();
}

/// Registers device FCM token with the API after login. Safe to call if Firebase is not configured.
class PushService {
  static bool _initialized = false;
  static bool _iosPushSetupDone = false;

  /// Listen to refresh in-app notification list / badge when app is open.
  static Stream<RemoteMessage> get foregroundMessages =>
      _foregroundStreamController.stream;

  static Future<void> _ensureIosPushSetup() async {
    if (_iosPushSetupDone) return;
    await _setupIosNotifications();
    _iosPushSetupDone = true;
  }

  static Future<void> _setupIosNotifications() async {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (kDebugMode) {
      print('PushService: iOS permission ${settings.authorizationStatus}');
    }

    await Permission.notification.request();

    await Future<void>.delayed(const Duration(seconds: 2));
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print(
        'PushService: foreground message '
        'notification=${message.notification?.title} data=${message.data}',
      );
    }
    _foregroundStreamController.add(message);
    await _showLocalNotification(message);
  }

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await ensureFirebaseInitialized();
      await _initLocalNotifications();

      if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (kDebugMode) {
          print('PushService: Android notification permission $status');
        }
      } else if (Platform.isIOS) {
        await _ensureIosPushSetup();
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _foregroundStreamController.add(message);
      });

      FirebaseMessaging.instance.onTokenRefresh.listen(_postTokenQuietly);
      _initialized = true;
    } catch (e, st) {
      if (kDebugMode) {
        print('PushService: init failed ($e)\n$st');
      }
    }
  }

  static Future<String?> _waitForApnsToken({
    int maxAttempts = 40,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    if (!Platform.isIOS) return null;
    for (var i = 0; i < maxAttempts; i++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) {
        if (kDebugMode) {
          print('PushService: APNS token ready (attempt ${i + 1})');
        }
        return apns;
      }
      await Future<void>.delayed(delay);
    }
    if (kDebugMode) {
      print(
        'PushService: APNS token timeout — check: real iPhone (not simulator), '
        'Xcode → Push Notifications capability, Apple Developer App ID push enabled, '
        'Firebase → APNs .p8 key uploaded',
      );
    }
    return null;
  }

  static Future<String?> _getFcmTokenWithIosRetry() async {
    if (Platform.isIOS) {
      await _ensureIosPushSetup();
      final apns = await _waitForApnsToken(maxAttempts: 30);
      if (apns == null) {
        if (kDebugMode) {
          print(
            'PushService: no APNS token — in Xcode/device log search for '
            '"[APNS] registration failed" (provisioning) or "device token registered" (OK)',
          );
        }
        return null;
      }
    }
    return FirebaseMessaging.instance.getToken();
  }

  static Future<void> registerTokenAfterLogin() async {
    if (!_initialized) await init();
    if (!_initialized) return;

    const maxAttempts = 8;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final token = await _getFcmTokenWithIosRetry();
        if (kDebugMode) {
          final preview = token != null && token.length > 12
              ? '${token.substring(0, 8)}…${token.substring(token.length - 4)}'
              : token;
          print(
            'PushService: FCM token ${token != null ? "received" : "null"} ($preview) attempt $attempt',
          );
        }
        if (token != null && token.isNotEmpty) {
          await _postToken(token);
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          print('PushService: getToken attempt $attempt failed: $e');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static Future<void> _postTokenQuietly(String token) async {
    try {
      await _postToken(token);
    } catch (_) {}
  }

  static Future<void> _postToken(String fcmToken) async {
    final prefs = await SharedPreferences.getInstance();
    final auth = prefs.getString('token');
    if (auth == null || auth.isEmpty) return;

    final uri = Uri.parse('${Url.url}/api/push/fcm-token');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $auth',
      },
      body: jsonEncode({'fcm_token': fcmToken}),
    );
    if (kDebugMode) {
      print('PushService: register token ${res.statusCode} ${res.body}');
    }
  }
}
