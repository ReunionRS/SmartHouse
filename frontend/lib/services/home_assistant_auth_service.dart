import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_config.dart';
import '../models/home_assistant_connection.dart';

class HomeAssistantAuthService {
  static const callbackScheme = 'smarthouse';
  static const callbackHost = 'ha-callback';
  static const callbackPath = '/oauth2redirect';
  static const _pendingStateKey = 'ha_oauth_pending_state';
  static const _pendingBaseUrlKey = 'ha_oauth_pending_base_url';

  String get redirectUri {
    const redirectFromEnv =
        String.fromEnvironment('HA_OAUTH_REDIRECT_URI', defaultValue: '');
    if (redirectFromEnv.isNotEmpty) {
      return redirectFromEnv;
    }
    if (kIsWeb) {
      return '${ApiConfig.baseUrl}/ha-oauth-web-callback';
    }
    return '$callbackScheme://$callbackHost$callbackPath';
  }

  String get clientId {
    const fromEnv =
        String.fromEnvironment('HA_OAUTH_CLIENT_ID', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv;
    return '${ApiConfig.baseUrl}/ha-oauth-client';
  }

  bool get _isInvalidLocalClientId {
    final id = clientId.toLowerCase();
    return id.contains('localhost') ||
        id.contains('127.0.0.1') ||
        id.contains('10.0.2.2');
  }

  String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.endsWith('/')) return trimmed.substring(0, trimmed.length - 1);
    return trimmed;
  }

  String _randomState() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Uri buildAuthorizeUrl({
    required String baseUrl,
    required String state,
  }) {
    final normalized = _normalizeBaseUrl(baseUrl);
    return Uri.parse('$normalized/auth/authorize').replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'state': state,
      'response_type': 'code',
    });
  }

  Future<(String code, String state)> handleCallback({
    required String baseUrl,
  }) async {
    if (kIsWeb) {
      final current = Uri.base;
      final prefs = await SharedPreferences.getInstance();
      final pendingState = prefs.getString(_pendingStateKey);

      if (current.path == '/ha-oauth-web-callback') {
        final authError = current.queryParameters['error'];
        if (authError != null && authError.isNotEmpty) {
          final description = current.queryParameters['error_description'];
          throw Exception(
            description == null || description.isEmpty
                ? authError
                : '$authError: $description',
          );
        }

        final code = current.queryParameters['code'];
        final returnedState = current.queryParameters['state'];
        if (code == null || code.isEmpty) {
          throw Exception('Не удалось получить код авторизации');
        }
        final hasValidState = pendingState != null &&
            pendingState.isNotEmpty &&
            returnedState == pendingState;
        final allowDevFallback = !kReleaseMode &&
            (pendingState == null || pendingState.isEmpty) &&
            returnedState != null &&
            returnedState.isNotEmpty;
        if (!hasValidState && !allowDevFallback) {
          throw Exception(
            'Ошибка проверки состояния авторизации. Повторите подключение ещё раз.',
          );
        }
        await prefs.remove(_pendingStateKey);
        return (code, returnedState ?? '');
      }

      if (_isInvalidLocalClientId) {
        throw Exception(
          'OAuth client_id использует localhost. Запустите с --dart-define=HA_OAUTH_CLIENT_ID=http://<LAN-IP>:4000/ha-oauth-client',
        );
      }

      final state = _randomState();
      await prefs.setString(_pendingStateKey, state);
      await prefs.setString(_pendingBaseUrlKey, baseUrl);
      final authUrl =
          buildAuthorizeUrl(baseUrl: baseUrl, state: state).toString();
      await launchUrl(
        Uri.parse(authUrl),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      throw Exception('oauth_redirect_started');
    }

    if (_isInvalidLocalClientId) {
      throw Exception(
        'OAuth client_id использует localhost. Запустите с --dart-define=HA_OAUTH_CLIENT_ID=http://<LAN-IP>:4000/ha-oauth-client',
      );
    }

    final state = _randomState();
    final authUrl =
        buildAuthorizeUrl(baseUrl: baseUrl, state: state).toString();

    final callback = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: callbackScheme,
    );

    final uri = Uri.parse(callback);
    final authError = uri.queryParameters['error'];
    if (authError != null && authError.isNotEmpty) {
      final description = uri.queryParameters['error_description'];
      if (description != null && description.isNotEmpty) {
        throw Exception('$authError: $description');
      }
      throw Exception(authError);
    }
    final code = uri.queryParameters['code'];
    final returnedState = uri.queryParameters['state'];
    if (code == null || code.isEmpty) {
      throw Exception('Не удалось получить код авторизации');
    }
    if (returnedState != state) {
      throw Exception('Ошибка проверки состояния авторизации');
    }
    return (code, returnedState ?? '');
  }

  Future<String?> getPendingBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingBaseUrlKey);
  }

  Future<void> clearPendingBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingBaseUrlKey);
  }

  Future<HomeAssistantTokenPayload> exchangeCodeForToken({
    required String baseUrl,
    required String code,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final response = await http.post(
      Uri.parse('$normalized/auth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Не удалось завершить подключение Home Assistant');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = (body['access_token'] ?? '').toString();
    final refreshToken = (body['refresh_token'] ?? '').toString();
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 0;
    if (accessToken.isEmpty || refreshToken.isEmpty || expiresIn <= 0) {
      throw Exception('Не удалось завершить подключение Home Assistant');
    }

    return HomeAssistantTokenPayload(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  Future<HomeAssistantTokenPayload> refreshAccessToken({
    required String baseUrl,
    required String refreshToken,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final response = await http.post(
      Uri.parse('$normalized/auth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('refresh_failed');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = (body['access_token'] ?? '').toString();
    final nextRefresh = (body['refresh_token'] ?? refreshToken).toString();
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 0;
    if (accessToken.isEmpty || nextRefresh.isEmpty || expiresIn <= 0) {
      throw Exception('refresh_failed');
    }

    return HomeAssistantTokenPayload(
      accessToken: accessToken,
      refreshToken: nextRefresh,
      expiresIn: expiresIn,
    );
  }

  Future<void> logout() async {}
}
