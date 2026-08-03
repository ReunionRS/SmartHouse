class HomeAssistantRoom {
  const HomeAssistantRoom({
    required this.areaId,
    required this.name,
    required this.aliases,
    required this.labels,
    required this.entityIds,
    required this.deviceIds,
    this.icon = '',
    this.floorId = '',
    this.picture = '',
    this.temperatureEntityId = '',
    this.humidityEntityId = '',
  });

  final String areaId;
  final String name;
  final List<String> aliases;
  final List<String> labels;
  final List<String> entityIds;
  final List<String> deviceIds;
  final String icon;
  final String floorId;
  final String picture;
  final String temperatureEntityId;
  final String humidityEntityId;

  factory HomeAssistantRoom.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => json[key] is List
        ? (json[key] as List).map((value) => value.toString()).toList()
        : const [];

    return HomeAssistantRoom(
      areaId: (json['area_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      aliases: strings('aliases'),
      labels: strings('labels'),
      entityIds: strings('entity_ids'),
      deviceIds: strings('device_ids'),
      icon: (json['icon'] ?? '').toString(),
      floorId: (json['floor_id'] ?? '').toString(),
      picture: (json['picture'] ?? '').toString(),
      temperatureEntityId: (json['temperature_entity_id'] ?? '').toString(),
      humidityEntityId: (json['humidity_entity_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'area_id': areaId,
        'name': name,
        'aliases': aliases,
        'labels': labels,
        'entity_ids': entityIds,
        'device_ids': deviceIds,
        'icon': icon,
        'floor_id': floorId,
        'picture': picture,
        'temperature_entity_id': temperatureEntityId,
        'humidity_entity_id': humidityEntityId,
      };
}
