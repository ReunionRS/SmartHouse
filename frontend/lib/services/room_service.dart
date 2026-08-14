import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/home_assistant_room.dart';
import '../models/local_room_device.dart';
import 'auth_service.dart';
import 'hub_state_service.dart';

class RoomService {
  static const _prefix = 'local_rooms_';
  static const _devicesPrefix = 'local_room_devices_';
  final HubStateService _hubState = HubStateService();
  final AuthService _auth = AuthService();
  Future<Map<String, dynamic>>? _snapshotRequest;
  List<LocalRoomDevice>? _storedDevicesCache;
  List<LocalRoomDevice> _resolvedDevicesCache = const [];
  Future<void> _deviceSaveQueue = Future<void>.value();

  Future<Map<String, dynamic>> _haSnapshot() {
    return _snapshotRequest ??= _fetchHaSnapshot().whenComplete(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      _snapshotRequest = null;
    });
  }

  Future<Map<String, dynamic>> _fetchHaSnapshot() async {
    final session = await _auth.getSession();
    if (session == null) throw Exception('Требуется вход в SmartHouse');
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/home-assistant/snapshot'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Home Assistant недоступен (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Некорректный ответ Home Assistant');
    }
    return decoded;
  }

  Future<List<HomeAssistantRoom>> load(String userId) async {
    try {
      final snapshot = await _haSnapshot().timeout(const Duration(seconds: 4));
      final rooms = snapshot['rooms'];
      if (rooms is List) {
        return rooms
            .whereType<Map<String, dynamic>>()
            .map(HomeAssistantRoom.fromJson)
            .toList(growable: false);
      }
    } catch (_) {
      // A hub may not be connected yet. Keep locally created rooms available.
    }
    try {
      final values = await _hubState.load(
        key: 'rooms',
        legacyPreferenceKey: '$_prefix$userId',
      );
      return values
          .whereType<Map<String, dynamic>>()
          .map(HomeAssistantRoom.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<LocalRoomDevice>> loadDevices(String userId) async {
    final stored = await _loadStoredDevices(userId);
    try {
      final snapshot = await _haSnapshot().timeout(const Duration(seconds: 3));
      final values = snapshot['devices'];
      if (values is! List) {
        _resolvedDevicesCache = stored;
        return stored;
      }
      final favorites = {
        for (final device in stored) device.id: device.isFavorite,
      };
      final remote = values
          .whereType<Map<String, dynamic>>()
          .map((item) => _deviceFromHa(item,
              isFavorite: favorites[item['entity_id'].toString()] == true))
          .toList(growable: false);
      final remoteIds = remote.map((device) => device.id).toSet();
      final result = [
        ...remote,
        ...stored.where((device) => !remoteIds.contains(device.id)),
      ];
      _resolvedDevicesCache = result;
      return result;
    } catch (_) {
      _resolvedDevicesCache = stored;
      return stored;
    }
  }

  List<LocalRoomDevice> cachedDevicesForRoom(String roomId) =>
      _resolvedDevicesCache
          .where((device) => device.roomId == roomId)
          .toList(growable: false);

  Future<List<LocalRoomDevice>> _loadStoredDevices(String userId) async {
    final cached = _storedDevicesCache;
    if (cached != null) return cached;
    try {
      final values = await _hubState.load(
        key: 'room_devices',
        legacyPreferenceKey: '$_devicesPrefix$userId',
      );
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
      final result = unique.values.toList(growable: false);
      _storedDevicesCache = result;
      return result;
    } catch (_) {
      return const [];
    }
  }

  LocalRoomDevice _deviceFromHa(Map<String, dynamic> raw,
      {required bool isFavorite}) {
    final entityId = (raw['entity_id'] ?? '').toString();
    final domain = (raw['domain'] ?? entityId.split('.').first).toString();
    final state = (raw['state'] ?? 'unknown').toString();
    final attributes = raw['attributes'] is Map<String, dynamic>
        ? raw['attributes'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final deviceClass = (attributes['device_class'] ?? '').toString();
    final supportedModes = (attributes['supported_color_modes'] as List?)
            ?.map((value) => value.toString())
            .toSet() ??
        const <String>{};
    final type = switch (domain) {
      'light'
          when supportedModes.any(
              (mode) => const {'rgb', 'rgbw', 'rgbww', 'hs'}.contains(mode)) =>
        'rgb_light',
      'light' => 'light',
      'switch' when deviceClass == 'outlet' => 'socket',
      'switch' => 'switch',
      'binary_sensor'
          when const {'door', 'garage_door', 'opening', 'window'}
              .contains(deviceClass) =>
        'contact_sensor',
      'binary_sensor'
          when const {'motion', 'occupancy', 'presence'}
              .contains(deviceClass) =>
        'motion_sensor',
      'binary_sensor' when deviceClass == 'moisture' => 'leak_sensor',
      'sensor' when deviceClass == 'temperature' => 'temperature_sensor',
      'sensor' when deviceClass == 'humidity' => 'temperature_humidity_sensor',
      'climate' => 'thermostat',
      'camera' => 'camera',
      'lock' => 'smart_lock',
      _ => domain,
    };
    final brightness =
        ((attributes['brightness'] as num?)?.toDouble() ?? 217) / 255 * 100;
    final numericState = double.tryParse(state);
    return LocalRoomDevice(
      id: entityId,
      roomId: (raw['area_id'] ?? '').toString(),
      name: (raw['name'] ?? attributes['friendly_name'] ?? entityId).toString(),
      type: type,
      isOn: state == 'on' || state == 'open' || state == 'locked',
      brightness: brightness.clamp(0, 100),
      temperature: deviceClass == 'temperature'
          ? numericState ?? 22
          : (attributes['current_temperature'] as num?)?.toDouble() ?? 22,
      humidity: deviceClass == 'humidity'
          ? numericState ?? 45
          : (attributes['current_humidity'] as num?)?.toDouble() ?? 45,
      isFavorite: isFavorite,
    );
  }

  Future<LocalRoomDevice> addDevice({
    required String userId,
    required String roomId,
    required String name,
    required String type,
  }) async {
    final devices = await _loadStoredDevices(userId);
    final device = LocalRoomDevice(
      id: 'device_${DateTime.now().microsecondsSinceEpoch}',
      roomId: roomId,
      name: name.trim(),
      type: type,
      isOn: type == 'light' || type == 'rgb_light' || type == 'rgb_strip',
    );
    final updated = [...devices, device];
    _storedDevicesCache = updated;
    _resolvedDevicesCache = [..._resolvedDevicesCache, device];
    _queueDeviceSave(userId, updated);
    return device;
  }

  Future<void> updateDevice(String userId, LocalRoomDevice device) async {
    if (device.id.contains('.')) {
      final domain = device.id.split('.').first;
      if (domain == 'light' || domain == 'switch' || domain == 'fan') {
        await _auth.callSystemService(
          domain: domain,
          service: device.isOn ? 'turn_on' : 'turn_off',
          data: {
            'entity_id': device.id,
            if (domain == 'light' && device.isOn)
              'brightness_pct': device.brightness.round(),
          },
        );
        _snapshotRequest = null;
        return;
      }
    }
    final devices = await _loadStoredDevices(userId);
    await _saveDevices(userId, [
      for (final item in devices)
        if (item.id == device.id) device else item,
    ]);
  }

  Future<void> deleteDevice(String userId, String deviceId) async {
    final devices = await _loadStoredDevices(userId);
    await _saveDevices(
      userId,
      devices.where((device) => device.id != deviceId).toList(),
    );
  }

  Future<void> setFavoriteDevices(
      String userId, Set<String> favoriteIds) async {
    final source = _resolvedDevicesCache.isNotEmpty
        ? _resolvedDevicesCache
        : await _loadStoredDevices(userId);
    final updated = [
      for (final device in source)
        device.copyWith(isFavorite: favoriteIds.contains(device.id)),
    ];
    _resolvedDevicesCache = updated;
    _storedDevicesCache = updated;
    _queueDeviceSave(userId, updated);
  }

  Future<void> delete(String userId, String roomId) async {
    final session = await _auth.getSession();
    final isLegacyLocalRoom = RegExp(r'_\d{13}$').hasMatch(roomId);
    if (session != null && !isLegacyLocalRoom) {
      final response = await http.delete(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/home-assistant/rooms/${Uri.encodeComponent(roomId)}'),
        headers: {'Authorization': 'Bearer ${session.token}'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 404) {
        var message = 'Не удалось удалить комнату из Smart House Hub';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['error'] != null) {
            message = decoded['error'].toString();
          }
        } catch (_) {}
        throw Exception(message);
      }
      _snapshotRequest = null;
    }
    final rooms = await load(userId);
    await _hubState.save(
      key: 'rooms',
      value: rooms
          .where((room) => room.areaId != roomId)
          .map((room) => room.toJson())
          .toList(),
    );
    final devices = await loadDevices(userId);
    await _saveDevices(
      userId,
      devices.where((device) => device.roomId != roomId).toList(),
    );
  }

  Future<void> _saveDevices(
      String userId, List<LocalRoomDevice> devices) async {
    _storedDevicesCache = devices;
    await _hubState.save(
      key: 'room_devices',
      value: devices.map((item) => item.toJson()).toList(),
    );
  }

  void _queueDeviceSave(String userId, List<LocalRoomDevice> devices) {
    _deviceSaveQueue = _deviceSaveQueue
        .catchError((_) {})
        .then((_) => _saveDevices(userId, devices));
    unawaited(_deviceSaveQueue.catchError((_) {}));
  }

  Future<HomeAssistantRoom> create({
    required String userId,
    required String name,
    required String icon,
    required String roomType,
  }) async {
    final session = await _auth.getSession();
    if (session != null) {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/home-assistant/rooms'),
            headers: {
              'Authorization': 'Bearer ${session.token}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': name.trim(),
              'icon': icon,
              'room_type': roomType,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final item = decoded is Map<String, dynamic> &&
                decoded['item'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded['item'] as Map<String, dynamic>)
            : <String, dynamic>{};
        item['name'] ??= name.trim();
        item['icon'] ??= icon;
        item['room_type'] ??= roomType;
        _snapshotRequest = null;
        return HomeAssistantRoom.fromJson(item);
      }
      if (response.statusCode != 409) {
        var message = 'Не удалось создать комнату в Smart House Hub';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> && decoded['error'] != null) {
            message = decoded['error'].toString();
          }
        } catch (_) {}
        if (response.statusCode == 401 || response.statusCode == 502) {
          message =
              'Авторизация Smart House Hub устарела. Переподключите хаб в настройках.';
        }
        throw Exception(message);
      }
    }

    // Offline fallback for accounts which have not connected a hub yet.
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
      roomType: roomType,
    );
    final updated = [...rooms, room];
    await _hubState.save(
      key: 'rooms',
      value: updated.map((item) => item.toJson()).toList(),
    );
    return room;
  }
}
