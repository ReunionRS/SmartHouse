import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/smart_scene.dart';
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
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) => SmartScene(
                id: (item['id'] ?? '').toString(),
                name: (item['name'] ?? '').toString(),
                triggerType: 'home_assistant',
                triggerTime: '',
                triggerDeviceId: '',
                triggerCondition: 'active',
                triggerValue: 0,
                triggerDays: const [],
                actionDeviceId: '',
                actionType: 'ha',
                enabled: item['enabled'] == true,
                lastRunAt:
                    DateTime.tryParse((item['lastTriggered'] ?? '').toString()),
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(String userId, List<SmartScene> scenes) async {
    await _hubState.save(
      key: 'scenes',
      value: scenes.map((scene) => scene.toJson()).toList(),
    );
  }

  Future<void> run(String userId, SmartScene scene) async {
    if (scene.triggerType == 'home_assistant') {
      await AuthService().callSystemService(
        domain: 'automation',
        service: 'trigger',
        data: {'entity_id': scene.id, 'skip_condition': false},
      );
      return;
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
  }
}
