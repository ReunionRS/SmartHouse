import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_config.dart';
import 'auth_service.dart';

class HubStateService {
  final AuthService _auth = AuthService();

  Future<List<dynamic>> load({
    required String key,
    required String legacyPreferenceKey,
  }) async {
    final session = await _auth.getSession();
    if (session == null) return const [];
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/app-state/$key'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    ).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('Не удалось загрузить данные с хаба');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final remote = body['value'];
    if (remote is List && remote.isNotEmpty) return remote;

    final prefs = await SharedPreferences.getInstance();
    final legacyRaw = prefs.getString(legacyPreferenceKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return remote is List ? remote : const [];
    }
    try {
      final legacy = jsonDecode(legacyRaw);
      if (legacy is! List) return const [];
      await save(key: key, value: legacy);
      await prefs.remove(legacyPreferenceKey);
      return legacy;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save({required String key, required List<dynamic> value}) async {
    final session = await _auth.getSession();
    if (session == null) throw Exception('Требуется вход в SmartHouse');
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/api/app-state/$key'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'value': value}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Не удалось сохранить данные на хабе');
    }
  }
}
