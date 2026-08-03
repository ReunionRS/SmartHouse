import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_assistant_room.dart';
import '../models/local_room_device.dart';

class RoomService {
  static const _prefix = 'local_rooms_';
  static const _devicesPrefix = 'local_room_devices_';

  Future<List<HomeAssistantRoom>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$userId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw) as List;
      return values
          .whereType<Map<String, dynamic>>()
          .map(HomeAssistantRoom.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LocalRoomDevice>> loadDevices(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_devicesPrefix$userId');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final values = jsonDecode(raw) as List;
      final devices = values
          .whereType<Map<String, dynamic>>()
          .map(LocalRoomDevice.fromJson)
          .toList(growable: false);
      // Старые сборки могли сохранить одно устройство повторно. Для интерфейса
      // это один физический датчик, поэтому оставляем одну запись по комнате,
      // типу и имени, даже если ошибочно были созданы разные локальные id.
      final unique = <String, LocalRoomDevice>{};
      for (final device in devices) {
        final key =
            '${device.roomId}|${device.type}|${device.name.trim().toLowerCase()}';
        unique.putIfAbsent(key, () => device);
      }
      if (unique.length != devices.length) {
        await _saveDevices(userId, unique.values.toList(growable: false));
      }
      return unique.values.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<LocalRoomDevice> addDevice({
    required String userId,
    required String roomId,
    required String name,
    required String type,
  }) async {
    final devices = await loadDevices(userId);
    final device = LocalRoomDevice(
      id: 'device_${DateTime.now().microsecondsSinceEpoch}',
      roomId: roomId,
      name: name.trim(),
      type: type,
      isOn: type == 'light' || type == 'rgb_light' || type == 'rgb_strip',
    );
    await _saveDevices(userId, [...devices, device]);
    return device;
  }

  Future<void> updateDevice(String userId, LocalRoomDevice device) async {
    final devices = await loadDevices(userId);
    await _saveDevices(userId, [
      for (final item in devices)
        if (item.id == device.id) device else item,
    ]);
  }

  Future<void> deleteDevice(String userId, String deviceId) async {
    final devices = await loadDevices(userId);
    await _saveDevices(
      userId,
      devices.where((device) => device.id != deviceId).toList(),
    );
  }

  Future<void> setFavoriteDevices(
      String userId, Set<String> favoriteIds) async {
    final devices = await loadDevices(userId);
    await _saveDevices(userId, [
      for (final device in devices)
        device.copyWith(isFavorite: favoriteIds.contains(device.id)),
    ]);
  }

  Future<void> delete(String userId, String roomId) async {
    final rooms = await load(userId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix$userId',
      jsonEncode(rooms
          .where((room) => room.areaId != roomId)
          .map((room) => room.toJson())
          .toList()),
    );
    final devices = await loadDevices(userId);
    await _saveDevices(
      userId,
      devices.where((device) => device.roomId != roomId).toList(),
    );
  }

  Future<void> _saveDevices(
      String userId, List<LocalRoomDevice> devices) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_devicesPrefix$userId',
        jsonEncode(devices.map((item) => item.toJson()).toList()));
  }

  Future<HomeAssistantRoom> create({
    required String userId,
    required String name,
    required String icon,
  }) async {
    final rooms = await load(userId);
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final room = HomeAssistantRoom(
      areaId:
          '${slug.isEmpty ? 'room' : slug}_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      aliases: const [],
      labels: const [],
      entityIds: const [],
      deviceIds: const [],
      icon: icon,
    );
    final updated = [...rooms, room];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$userId',
        jsonEncode(updated.map((item) => item.toJson()).toList()));
    return room;
  }
}
