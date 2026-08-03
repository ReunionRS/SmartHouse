class SystemEntity {
  const SystemEntity({
    required this.entityId,
    required this.domain,
    required this.state,
    required this.friendlyName,
    required this.unit,
    required this.deviceClass,
    required this.icon,
    required this.lastChanged,
    required this.lastUpdated,
    required this.attributes,
  });

  final String entityId;
  final String domain;
  final String state;
  final String friendlyName;
  final String unit;
  final String deviceClass;
  final String icon;
  final String lastChanged;
  final String lastUpdated;
  final Map<String, dynamic> attributes;

  factory SystemEntity.fromJson(Map<String, dynamic> json) {
    return SystemEntity(
      entityId: (json['entityId'] ?? '').toString(),
      domain: (json['domain'] ?? '').toString(),
      state: (json['state'] ?? '').toString(),
      friendlyName: (json['friendlyName'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      deviceClass: (json['deviceClass'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      lastChanged: (json['lastChanged'] ?? '').toString(),
      lastUpdated: (json['lastUpdated'] ?? '').toString(),
      attributes: json['attributes'] is Map<String, dynamic>
          ? json['attributes'] as Map<String, dynamic>
          : const <String, dynamic>{},
    );
  }
}

class SystemHistoryPoint {
  const SystemHistoryPoint({
    required this.entityId,
    required this.state,
    required this.lastChanged,
    required this.lastUpdated,
  });

  final String entityId;
  final String state;
  final String lastChanged;
  final String lastUpdated;

  factory SystemHistoryPoint.fromJson(Map<String, dynamic> json) {
    return SystemHistoryPoint(
      entityId: (json['entityId'] ?? '').toString(),
      state: (json['state'] ?? '').toString(),
      lastChanged: (json['lastChanged'] ?? '').toString(),
      lastUpdated: (json['lastUpdated'] ?? '').toString(),
    );
  }
}
