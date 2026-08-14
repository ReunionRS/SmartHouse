import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'auth_service.dart';

class AiChatResponse {
  const AiChatResponse(
      {required this.conversationId,
      required this.message,
      required this.type,
      this.data});
  final String conversationId;
  final String message;
  final String type;
  final Map<String, dynamic>? data;
}

class AiAssistantService {
  AiAssistantService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<AiChatResponse> send(
      {required String message, String? conversationId}) async {
    final session = await _auth.getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/ai/chat'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'message': message,
            if (conversationId?.isNotEmpty == true)
              'conversationId': conversationId
          }),
        )
        .timeout(const Duration(seconds: 150));
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          (decoded['error'] ?? 'AI-ассистент недоступен').toString());
    }
    return AiChatResponse(
      conversationId: (decoded['conversationId'] ?? '').toString(),
      message: (decoded['message'] ?? '').toString(),
      type: (decoded['type'] ?? 'text').toString(),
      data: decoded['data'] is Map<String, dynamic>
          ? decoded['data'] as Map<String, dynamic>
          : null,
    );
  }

  Future<String> confirmAction(String confirmationId) async {
    final decoded = await _postAction('confirm-action', confirmationId);
    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final device = (result['device'] ?? 'Устройство').toString();
      return result['success'] == true
          ? '$device: команда выполнена.'
          : (result['warning'] ??
                  'Команда отправлена, но состояние пока не подтверждено.')
              .toString();
    }
    return 'Команда выполнена.';
  }

  Future<void> cancelAction(String confirmationId) async {
    await _postAction('cancel-action', confirmationId);
  }

  Future<String> createAutomation(Map<String, dynamic> draft) async {
    final session = await _auth.getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/automations'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'draft': draft}),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          (decoded['error'] ?? 'Не удалось создать автоматизацию').toString());
    }
    return 'Автоматизация «${decoded['name'] ?? draft['name']}» создана в Home Assistant.';
  }

  Future<Map<String, dynamic>> _postAction(String action, String id) async {
    final session = await _auth.getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/ai/$action/$id'),
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      },
    ).timeout(const Duration(seconds: 30));
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          (decoded['error'] ?? 'Не удалось выполнить действие').toString());
    }
    return decoded;
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
