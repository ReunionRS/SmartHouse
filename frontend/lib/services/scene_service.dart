import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_scene.dart';
import 'room_service.dart';

class SceneService {
  static const _prefix = 'smart_scenes_';

  Future<List<SmartScene>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$userId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(SmartScene.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(String userId, List<SmartScene> scenes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$userId',
        jsonEncode(scenes.map((scene) => scene.toJson()).toList()));
  }

  Future<void> run(String userId, SmartScene scene) async {
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
