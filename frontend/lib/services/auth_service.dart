import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';
import '../models/session_models.dart';
import '../models/system_models.dart';
import 'home_assistant_connection_service.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _rememberEmailKey = 'remember_email';
  static const _userEmailKey = 'user_email';
  static const _userFioKey = 'user_fio';
  static const _userAvatarKey = 'user_avatar';

  final HomeAssistantConnectionService _haConnectionService =
      HomeAssistantConnectionService();

  Future<Map<String, String>> _authHeaders() async {
    final session = await getSession();
    if (session == null) throw const UnauthorizedException();
    return {
      'Authorization': 'Bearer ${session.token}',
      'Content-Type': 'application/json',
    };
  }

  Future<String> _token() async {
    final session = await getSession();
    if (session == null) throw const UnauthorizedException();
    return session.token;
  }

  String resolveFileUrl(String storagePath) {
    if (storagePath.isEmpty ||
        storagePath.startsWith('http://') ||
        storagePath.startsWith('https://')) {
      return storagePath;
    }
    final normalized =
        storagePath.startsWith('/') ? storagePath : '/$storagePath';
    return '${ApiConfig.baseUrl}$normalized';
  }

  Future<AppSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    return AppSession(
      id: prefs.getString(_userIdKey) ?? '',
      token: token,
      email: prefs.getString(_userEmailKey) ?? '',
      fio: prefs.getString(_userFioKey) ?? '',
      avatarUrl: prefs.getString(_userAvatarKey) ?? '',
    );
  }

  Future<String> getRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberEmailKey) ?? '';
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey),
      prefs.remove(_userIdKey),
      prefs.remove(_userEmailKey),
      prefs.remove(_userFioKey),
      prefs.remove(_userAvatarKey),
    ]);
  }

  Future<void> _saveSession(AppSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userIdKey, session.id);
    await prefs.setString(_userEmailKey, session.email);
    await prefs.setString(_userFioKey, session.fio);
    await prefs.setString(_userAvatarKey, session.avatarUrl);
  }

  Future<void> _saveRememberedEmail(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    if (email == null || email.isEmpty) {
      await prefs.remove(_rememberEmailKey);
    } else {
      await prefs.setString(_rememberEmailKey, email);
    }
  }

  Future<AppSession> login({
    required String email,
    required String password,
    required bool rememberEmail,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final body = _decodeMap(response.body);
    if (response.statusCode != 200) {
      throw Exception((body['error'] ?? 'Ошибка входа').toString());
    }
    final session = _sessionFromResponse(body, fallbackEmail: email);
    await _saveSession(session);
    await _saveRememberedEmail(rememberEmail ? email : null);
    return session;
  }

  Future<AppSession> register({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.toLowerCase().trim();
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': normalizedEmail,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = _decodeMap(response.body);
    if (response.statusCode != 201) {
      throw Exception((body['error'] ?? 'Ошибка регистрации').toString());
    }
    final session = _sessionFromResponse(body, fallbackEmail: normalizedEmail);
    await _saveSession(session);
    await _saveRememberedEmail(normalizedEmail);
    return session;
  }

  AppSession _sessionFromResponse(Map<String, dynamic> body,
      {required String fallbackEmail}) {
    final token = body['token'];
    final user = body['user'];
    if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
      throw Exception('Некорректный ответ сервера');
    }
    return AppSession(
      id: (user['id'] ?? user['uid'] ?? '').toString(),
      token: token,
      email: (user['email'] ?? fallbackEmail).toString(),
      fio: (user['fio'] ?? '').toString(),
      avatarUrl: (user['avatarUrl'] ?? '').toString(),
    );
  }

  Future<String> uploadAvatar({required PlatformFile file}) async {
    if (file.bytes == null) throw Exception('Файл недоступен');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/api/users/me/avatar'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      file.bytes!,
      filename: file.name,
      contentType: _guessMediaType(file.name),
    ));
    final response = await http.Response.fromStream(await request.send());
    _ensureSuccess(response, fallback: 'Ошибка загрузки изображения');
    final avatarUrl = (_decodeMap(response.body)['avatarUrl'] ?? '').toString();
    if (avatarUrl.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userAvatarKey, avatarUrl);
    }
    return avatarUrl;
  }

  Future<String> updateProfileName(String name) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/api/users/me'),
      headers: await _authHeaders(),
      body: jsonEncode({'fio': name.trim()}),
    );
    _ensureSuccess(response, fallback: 'Не удалось изменить имя');
    final value = (_decodeMap(response.body)['fio'] ?? name).toString().trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userFioKey, value);
    return value;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/users/me/password'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    _ensureSuccess(response, fallback: 'Ошибка смены пароля');
  }

  Future<List<SystemEntity>> fetchSystemStatus({String? domain}) async {
    final direct = await _fetchStatesFromHomeAssistant(domain: domain);
    if (direct != null) return direct;

    final query = <String, String>{};
    if (domain?.isNotEmpty == true) query['domain'] = domain!;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/systems/status')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: await _authHeaders());
    _ensureSuccess(response,
        fallback: 'Не удалось загрузить состояния устройств');
    final decoded = jsonDecode(response.body);
    final items = decoded is Map<String, dynamic> && decoded['items'] is List
        ? decoded['items'] as List
        : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SystemEntity.fromJson)
        .toList(growable: false);
  }

  Future<List<SystemEntity>?> _fetchStatesFromHomeAssistant({
    String? domain,
  }) async {
    if (kIsWeb) return null;
    try {
      final session = await getSession();
      if (session == null) return null;
      var connection = await _haConnectionService.getConnection(session.id);
      if (connection == null) return null;
      if (connection.isExpired) {
        if (!await _haConnectionService.isConnected(session.id)) return null;
        connection = await _haConnectionService.getConnection(session.id);
        if (connection == null) return null;
      }

      Future<http.Response> request() => http.get(
            Uri.parse('${connection!.baseUrl}/api/states'),
            headers: {
              'Authorization': 'Bearer ${connection.accessToken}',
              'Content-Type': 'application/json',
            },
          );

      var response = await request();
      if (response.statusCode == 401 &&
          await _haConnectionService.isConnected(session.id)) {
        connection = await _haConnectionService.getConnection(session.id);
        if (connection == null) return null;
        response = await request();
      }
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_systemEntityFromHomeAssistant)
          .where((item) => item.entityId.isNotEmpty)
          .where((item) => domain?.isNotEmpty != true || item.domain == domain)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  SystemEntity _systemEntityFromHomeAssistant(Map<String, dynamic> raw) {
    final entityId = (raw['entity_id'] ?? '').toString();
    final attributes = raw['attributes'] is Map<String, dynamic>
        ? raw['attributes'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return SystemEntity(
      entityId: entityId,
      domain: entityId.contains('.') ? entityId.split('.').first : 'sensor',
      state: (raw['state'] ?? '').toString(),
      friendlyName: (attributes['friendly_name'] ?? entityId).toString(),
      unit: (attributes['unit_of_measurement'] ?? '').toString(),
      deviceClass: (attributes['device_class'] ?? '').toString(),
      icon: (attributes['icon'] ?? '').toString(),
      lastChanged: (raw['last_changed'] ?? '').toString(),
      lastUpdated: (raw['last_updated'] ?? '').toString(),
      attributes: attributes,
    );
  }

  Future<void> callSystemService({
    required String domain,
    required String service,
    required Map<String, dynamic> data,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/systems/service'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'domain': domain,
        'service': service,
        'data': data,
      }),
    );
    _ensureSuccess(response, fallback: 'Не удалось выполнить команду');
  }

  Future<void> saveHomeAssistantConnection({
    required String baseUrl,
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
    String houseId = '',
    required String clientId,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/home-assistant/connection'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'houseId': houseId,
        'status': 'connected',
        'clientId': clientId,
      }),
    );
    _ensureSuccess(response,
        fallback: 'Не удалось сохранить подключение Home Assistant');
  }

  Future<void> deleteHomeAssistantConnection() async {
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/home-assistant/connection'),
      headers: await _authHeaders(),
    );
    _ensureSuccess(response,
        fallback: 'Не удалось удалить подключение Home Assistant');
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } catch (_) {
      return const {};
    }
  }

  void _ensureSuccess(http.Response response, {required String fallback}) {
    if (response.statusCode == 401) throw const UnauthorizedException();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          (_decodeMap(response.body)['error'] ?? fallback).toString());
    }
  }

  MediaType _guessMediaType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('application', 'octet-stream');
  }
}
