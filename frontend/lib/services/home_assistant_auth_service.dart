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
      final origin = Uri.base.origin;
      return '$origin/ha-oauth-web-callback';
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

  String pairingClientIdFor(String baseUrl) => '${_normalizeBaseUrl(baseUrl)}/';

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
    String? clientIdOverride,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final response = await http.post(
      Uri.parse('$normalized/auth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientIdOverride ?? clientId,
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

  Future<HomeAssistantTokenPayload> loginWithCredentials({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final response = await http.post(
      Uri.parse('$normalized/auth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'username': username,
        'password': password,
        'client_id': clientId,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Не удалось войти в Home Assistant');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = (body['access_token'] ?? '').toString();
    final refreshToken = (body['refresh_token'] ?? '').toString();
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 0;
    if (accessToken.isEmpty || refreshToken.isEmpty || expiresIn <= 0) {
      throw Exception('Не удалось войти в Home Assistant');
    }

    return HomeAssistantTokenPayload(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: expiresIn,
    );
  }

  Future<HomeAssistantTokenPayload> exchangePairingToken({
    required String baseUrl,
    required String pairingToken,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final pairingClientId = pairingClientIdFor(normalized);
    const headers = {'Content-Type': 'application/json'};
    final startResponse = await http
        .post(
          Uri.parse('$normalized/auth/login_flow'),
          headers: headers,
          body: jsonEncode({
            'client_id': pairingClientId,
            'handler': ['smart_house', null],
            'redirect_uri': pairingClientId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (startResponse.statusCode != 200) {
      throw Exception('smart_house_pairing_unavailable');
    }
    final startBody = jsonDecode(startResponse.body);
    if (startBody is! Map<String, dynamic> ||
        startBody['type'] != 'form' ||
        startBody['flow_id'] is! String) {
      throw Exception('smart_house_pairing_unavailable');
    }

    final flowId = startBody['flow_id'] as String;
    final finishResponse = await http
        .post(
          Uri.parse('$normalized/auth/login_flow/$flowId'),
          headers: headers,
          body: jsonEncode({
            'client_id': pairingClientId,
            'pairing_token': pairingToken,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (finishResponse.statusCode != 200) {
      throw Exception('Не удалось подтвердить подключение Smart House Hub');
    }
    final finishBody = jsonDecode(finishResponse.body);
    if (finishBody is! Map<String, dynamic> ||
        finishBody['type'] != 'create_entry' ||
        finishBody['result'] is! String) {
      throw Exception('Недействительная или истёкшая сессия подключения');
    }
    return exchangeCodeForToken(
      baseUrl: normalized,
      code: finishBody['result'] as String,
      clientIdOverride: pairingClientId,
    );
  }

  Future<(String hubId, String pairingProof)?> detectSmartHouseHub(
    String baseUrl,
  ) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    try {
      final response = await http
          .get(Uri.parse('$normalized/api/smart_house/info'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> ||
          body['product'] != 'Smart House Hub') {
        return null;
      }
      final hubId = (body['hubId'] ?? '').toString().trim();
      final pairingProof = (body['pairingProof'] ?? '').toString().trim();
      return hubId.isEmpty || pairingProof.isEmpty
          ? null
          : (hubId, pairingProof);
    } catch (_) {
      return null;
    }
  }

  Future<HomeAssistantTokenPayload> refreshAccessToken({
    required String baseUrl,
    required String refreshToken,
    String? clientIdOverride,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final response = await http.post(
      Uri.parse('$normalized/auth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientIdOverride ?? clientId,
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
