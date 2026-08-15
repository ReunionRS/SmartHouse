import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/smart_scene.dart';
import '../models/scene_execution_report.dart';
import 'auth_service.dart';
import 'room_service.dart';
import 'hub_state_service.dart';

class SceneService {
  static const _prefix = 'smart_scenes_';
  final HubStateService _hubState = HubStateService();

  Future<List<SmartScene>> load(String userId) async {
    try {
      return (await _hubState.load(
        key: 'scenes',
        legacyPreferenceKey: '$_prefix$userId',
      ))
          .whereType<Map<String, dynamic>>()
          .map(SmartScene.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<SmartScene>> loadHomeAssistant() async {
    final session = await AuthService().getSession();
    if (session == null) return const [];
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/automations'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : const [];
      return items.whereType<Map<String, dynamic>>().map((item) {
        final local = item['source'] == 'smart_house';
        final trigger = item['trigger'] is Map
            ? Map<String, dynamic>.from(item['trigger'] as Map)
            : const <String, dynamic>{};
        final actions = item['actions'] is List
            ? (item['actions'] as List).whereType<Map>().toList()
            : const <Map>[];
        final action = actions.isEmpty
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(actions.first);
        return SmartScene(
          id: (item['id'] ?? '').toString(),
          name: (item['name'] ?? '').toString(),
          triggerType: local ? 'time' : 'home_assistant',
          triggerTime: local ? (trigger['at'] ?? '').toString() : '',
          triggerDeviceId: '',
          triggerCondition: 'active',
          triggerValue: 0,
          triggerDays: const [],
          actionDeviceId: local ? (action['entity_id'] ?? '').toString() : '',
          actionType: local ? (action['action'] ?? 'turn_on').toString() : 'ha',
          enabled: item['enabled'] == true,
          lastRunAt:
              DateTime.tryParse((item['lastTriggered'] ?? '').toString()),
          settings: local ? const {'source': 'smart_house'} : const {},
        );
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> updateLocalAutomation(SmartScene scene) async {
    final session = await AuthService().getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http
        .put(
          Uri.parse('${ApiConfig.baseUrl}/api/automations/${scene.id}'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': scene.name,
            'triggerTime': scene.triggerTime,
            'actionDeviceId': scene.actionDeviceId,
            'actionType': scene.actionType,
            'enabled': scene.enabled,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((_decodeMap(response.body)['error'] ??
              'Не удалось сохранить автоматизацию')
          .toString());
    }
  }

  Future<void> deleteLocalAutomation(String id) async {
    final session = await AuthService().getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/api/automations/$id'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((_decodeMap(response.body)['error'] ??
              'Не удалось удалить автоматизацию')
          .toString());
    }
  }

  Future<List<SmartScene>> loadPresets() async {
    final session = await AuthService().getSession();
    if (session == null) return const [];
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/homes/default/scenes'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic> && decoded['items'] is List
          ? decoded['items'] as List
          : const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) => SmartScene(
                id: (item['id'] ?? '').toString(),
                name: (item['name'] ?? '').toString(),
                triggerType: 'preset',
                triggerTime: '',
                triggerDeviceId: '',
                triggerCondition: (item['description'] ?? '').toString(),
                triggerValue: ((item['settings'] is Map
                            ? (item['settings'] as Map)['brightness'] ??
                                (item['settings'] as Map)['nightBrightness'] ??
                                (item['settings'] as Map)['temperature']
                            : null) as num?)
                        ?.toDouble() ??
                    0,
                triggerDays: const [],
                actionDeviceId: '',
                actionType: 'preset',
                settings: item['settings'] is Map<String, dynamic>
                    ? Map<String, dynamic>.from(
                        item['settings'] as Map<String, dynamic>)
                    : const {},
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePresetSettings(
      String sceneId, Map<String, dynamic> settings) async {
    final session = await AuthService().getSession();
    if (session == null) throw Exception('Требуется авторизация');
    final response = await http
        .put(
          Uri.parse(
              '${ApiConfig.baseUrl}/api/homes/default/scenes/$sceneId/settings'),
          headers: {
            'Authorization': 'Bearer ${session.token}',
            'Content-Type': 'application/json'
          },
          body: jsonEncode(settings),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception((_decodeMap(response.body)['error'] ??
              'Не удалось сохранить настройки сцены')
          .toString());
    }
  }

  Future<void> save(String userId, List<SmartScene> scenes) async {
    await _hubState.save(
      key: 'scenes',
      value: scenes.map((scene) => scene.toJson()).toList(),
    );
  }

  Future<SceneExecutionReport?> run(String userId, SmartScene scene,
      {bool confirmed = false}) async {
    if (scene.triggerType == 'preset') {
      final session = await AuthService().getSession();
      if (session == null) throw Exception('Требуется авторизация');
      final response = await http
          .post(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/homes/default/scenes/${scene.id}/run'),
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'confirmed': confirmed}),
          )
          .timeout(const Duration(seconds: 45));
      final body = _decodeMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300)
        throw Exception(
            (body['error'] ?? 'Не удалось выполнить сцену').toString());
      return SceneExecutionReport.fromJson(body);
    }
    if (scene.triggerType == 'home_assistant') {
      await AuthService().callSystemService(
        domain: 'automation',
        service: 'trigger',
        data: {'entity_id': scene.id, 'skip_condition': false},
      );
      return null;
    }
    final rooms = RoomService();
    final devices = await rooms.loadDevices(userId);
    final index = devices.indexWhere((item) => item.id == scene.actionDeviceId);
    if (index < 0) throw Exception('Устройство действия не найдено');
    final current = devices[index];
    final isOn = switch (scene.actionType) {
      'turn_off' => false,
      'toggle' => !current.isOn,
      _ => true,
    };
    await rooms.updateDevice(userId, current.copyWith(isOn: isOn));
    return null;
  }

  Map<String, dynamic> _decodeMap(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : const {};
    } catch (_) {
      return const {};
    }
  }
}
