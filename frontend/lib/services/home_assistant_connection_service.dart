import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_assistant_connection.dart';
import 'home_assistant_auth_service.dart';

class HomeAssistantConnectionService {
  static const _storage = FlutterSecureStorage();
  static const _metaPrefix = 'ha_conn_meta_';
  static const _accessPrefix = 'ha_conn_access_';
  static const _refreshPrefix = 'ha_conn_refresh_';

  HomeAssistantConnectionService({
    HomeAssistantAuthService? authService,
  }) : _authService = authService ?? HomeAssistantAuthService();

  final HomeAssistantAuthService _authService;

  String _metaKey(String userId) => '$_metaPrefix$userId';
  String _accessKey(String userId) => '$_accessPrefix$userId';
  String _refreshKey(String userId) => '$_refreshPrefix$userId';

  Future<void> saveConnection(HomeAssistantConnection connection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _metaKey(connection.userId),
      jsonEncode(connection.toJson()),
    );
    if (kIsWeb) {
      await prefs.setString(
          _accessKey(connection.userId), connection.accessToken);
      await prefs.setString(
        _refreshKey(connection.userId),
        connection.refreshToken,
      );
    } else {
      await _storage.write(
        key: _accessKey(connection.userId),
        value: connection.accessToken,
      );
      await _storage.write(
        key: _refreshKey(connection.userId),
        value: connection.refreshToken,
      );
    }
  }

  Future<HomeAssistantConnection?> getConnection(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey(userId));
    if (raw == null || raw.isEmpty) return null;

    final accessToken = kIsWeb
        ? prefs.getString(_accessKey(userId))
        : await _storage.read(key: _accessKey(userId));
    final refreshToken = kIsWeb
        ? prefs.getString(_refreshKey(userId))
        : await _storage.read(key: _refreshKey(userId));
    if (accessToken == null || refreshToken == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return HomeAssistantConnection.fromJson(
        json,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> disconnect(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_metaKey(userId));
    if (kIsWeb) {
      await prefs.remove(_accessKey(userId));
      await prefs.remove(_refreshKey(userId));
    } else {
      await _storage.delete(key: _accessKey(userId));
      await _storage.delete(key: _refreshKey(userId));
    }
  }

  Future<bool> isConnected(String userId) async {
    final connection = await getConnection(userId);
    if (connection == null) return false;

    if (!connection.isExpired) return true;

    try {
      final refreshed = await _authService.refreshAccessToken(
        baseUrl: connection.baseUrl,
        refreshToken: connection.refreshToken,
      );

      final updated = HomeAssistantConnection(
        id: connection.id,
        userId: connection.userId,
        houseId: connection.houseId,
        baseUrl: connection.baseUrl,
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: refreshed.expiresIn)),
        status: 'connected',
        lastCheckedAt: DateTime.now(),
      );
      await saveConnection(updated);
      return true;
    } catch (_) {
      await disconnect(userId);
      return false;
    }
  }
}
