class LocalRoomDevice {
  const LocalRoomDevice({
    required this.id,
    required this.roomId,
    required this.name,
    required this.type,
    required this.isOn,
    this.brightness = 85,
    this.temperature = 22,
    this.humidity = 45,
    this.mode = 'neutral',
    this.isFavorite = false,
    this.schedules = const [],
    this.rgbHue = 25,
    this.rgbEffect = 'steady',
  });

  final String id;
  final String roomId;
  final String name;
  final String type;
  final bool isOn;
  final double brightness;
  final double temperature;
  final double humidity;
  final String mode;
  final bool isFavorite;
  final List<DeviceSchedule> schedules;
  final double rgbHue;
  final String rgbEffect;

  LocalRoomDevice copyWith({
    String? name,
    bool? isOn,
    double? brightness,
    double? temperature,
    double? humidity,
    String? mode,
    bool? isFavorite,
    List<DeviceSchedule>? schedules,
    double? rgbHue,
    String? rgbEffect,
  }) =>
      LocalRoomDevice(
        id: id,
        roomId: roomId,
        name: name ?? this.name,
        type: type,
        isOn: isOn ?? this.isOn,
        brightness: brightness ?? this.brightness,
        temperature: temperature ?? this.temperature,
        humidity: humidity ?? this.humidity,
        mode: mode ?? this.mode,
        isFavorite: isFavorite ?? this.isFavorite,
        schedules: schedules ?? this.schedules,
        rgbHue: rgbHue ?? this.rgbHue,
        rgbEffect: rgbEffect ?? this.rgbEffect,
      );

  factory LocalRoomDevice.fromJson(Map<String, dynamic> json) =>
      LocalRoomDevice(
        id: (json['id'] ?? '').toString(),
        roomId: (json['room_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        type: (json['type'] ?? 'sensor').toString(),
        isOn: json['is_on'] == true,
        brightness: (json['brightness'] as num?)?.toDouble() ?? 85,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 22,
        humidity: (json['humidity'] as num?)?.toDouble() ?? 45,
        mode: (json['mode'] ?? 'neutral').toString(),
        isFavorite: json['is_favorite'] == true,
        schedules: (json['schedules'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(DeviceSchedule.fromJson)
                .toList(growable: false) ??
            const [],
        rgbHue: (json['rgb_hue'] as num?)?.toDouble() ?? 25,
        rgbEffect: (json['rgb_effect'] ?? 'steady').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'name': name,
        'type': type,
        'is_on': isOn,
        'brightness': brightness,
        'temperature': temperature,
        'humidity': humidity,
        'mode': mode,
        'is_favorite': isFavorite,
        'schedules': schedules.map((item) => item.toJson()).toList(),
        'rgb_hue': rgbHue,
        'rgb_effect': rgbEffect,
      };
}

class DeviceSchedule {
  const DeviceSchedule({
    required this.id,
    required this.days,
    required this.onTime,
    required this.offTime,
    this.enabled = true,
  });

  final String id;
  final List<int> days;
  final String onTime;
  final String offTime;
  final bool enabled;

  DeviceSchedule copyWith({
    List<int>? days,
    String? onTime,
    String? offTime,
    bool? enabled,
  }) =>
      DeviceSchedule(
        id: id,
        days: days ?? this.days,
        onTime: onTime ?? this.onTime,
        offTime: offTime ?? this.offTime,
        enabled: enabled ?? this.enabled,
      );

  factory DeviceSchedule.fromJson(Map<String, dynamic> json) => DeviceSchedule(
        id: (json['id'] ?? '').toString(),
        days: (json['days'] as List?)
                ?.whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false) ??
            const [],
        onTime: (json['on_time'] ?? '08:00').toString(),
        offTime: (json['off_time'] ?? '09:00').toString(),
        enabled: json['enabled'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'days': days,
        'on_time': onTime,
        'off_time': offTime,
        'enabled': enabled,
      };
}
