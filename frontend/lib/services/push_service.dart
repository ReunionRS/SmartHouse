import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_config.dart';
import '../models/session_models.dart';
import 'local_push_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await LocalPushService.instance.init();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      final title = notification?.title ?? '';
      final body = notification?.body ?? '';
      if (title.isEmpty && body.isEmpty) return;
      await LocalPushService.instance.show(title: title, body: body);
    });
    _initialized = true;
  }

  Future<void> registerToken(AppSession session) async {
    await init();
    if (!_initialized) return;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final locale =
          WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
      final platform = defaultTargetPlatform.name;
      final fcmToken = await FirebaseMessaging.instance.getToken();

      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _registerToken(
          session: session,
          token: fcmToken,
          tokenType: 'fcm',
          platform: platform,
          appVersion: packageInfo.version,
          locale: locale,
        );
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          await _registerToken(
            session: session,
            token: apnsToken,
            tokenType: 'apns',
            platform: platform,
            appVersion: packageInfo.version,
            locale: locale,
          );
        }
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((nextToken) async {
        if (nextToken.isEmpty) return;
        await _registerToken(
          session: session,
          token: nextToken,
          tokenType: 'fcm',
          platform: platform,
          appVersion: packageInfo.version,
          locale: locale,
        );
      });
    } catch (_) {}
  }

  Future<void> unregisterToken(AppSession session) async {
    if (session.token.isEmpty) return;
    await init();
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _unregisterToken(session: session, token: token);
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null && apnsToken.isNotEmpty) {
          await _unregisterToken(session: session, token: apnsToken);
        }
      }
    } catch (_) {}
  }

  Future<void> _registerToken({
    required AppSession session,
    required String token,
    required String tokenType,
    required String platform,
    required String appVersion,
    required String locale,
  }) async {
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/push/register'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'token': token,
        'tokenType': tokenType,
        'platform': platform,
        'appVersion': appVersion,
        'locale': locale,
      }),
    );
  }

  Future<void> _unregisterToken({
    required AppSession session,
    required String token,
  }) async {
    await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/push/unregister'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token}),
    );
  }
}
