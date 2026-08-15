class SmartScene {
  const SmartScene({
    required this.id,
    required this.name,
    required this.triggerType,
    required this.triggerTime,
    required this.triggerDeviceId,
    required this.triggerCondition,
    required this.triggerValue,
    required this.triggerDays,
    required this.actionDeviceId,
    required this.actionType,
    this.enabled = true,
    this.lastRunAt,
    this.settings = const {},
  });

  final String id;
  final String name;
  final String triggerType;
  final String triggerTime;
  final String triggerDeviceId;
  final String triggerCondition;
  final double triggerValue;
  final List<int> triggerDays;
  final String actionDeviceId;
  final String actionType;
  final bool enabled;
  final DateTime? lastRunAt;
  final Map<String, dynamic> settings;

  SmartScene copyWith({bool? enabled, DateTime? lastRunAt}) => SmartScene(
        id: id,
        name: name,
        triggerType: triggerType,
        triggerTime: triggerTime,
        triggerDeviceId: triggerDeviceId,
        triggerCondition: triggerCondition,
        triggerValue: triggerValue,
        triggerDays: triggerDays,
        actionDeviceId: actionDeviceId,
        actionType: actionType,
        enabled: enabled ?? this.enabled,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        settings: settings,
      );

  factory SmartScene.fromJson(Map<String, dynamic> json) => SmartScene(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        triggerType: (json['trigger_type'] ?? 'manual').toString(),
        triggerTime: (json['trigger_time'] ?? '').toString(),
        triggerDeviceId: (json['trigger_device_id'] ?? '').toString(),
        triggerCondition: (json['trigger_condition'] ?? 'active').toString(),
        triggerValue: (json['trigger_value'] as num?)?.toDouble() ?? 25,
        triggerDays: (json['trigger_days'] as List?)
                ?.whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false) ??
            const [0, 1, 2, 3, 4, 5, 6],
        actionDeviceId: (json['action_device_id'] ?? '').toString(),
        actionType: (json['action_type'] ?? 'turn_on').toString(),
        enabled: json['enabled'] != false,
        lastRunAt: DateTime.tryParse((json['last_run_at'] ?? '').toString()),
        settings: json['settings'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                json['settings'] as Map<String, dynamic>)
            : const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trigger_type': triggerType,
        'trigger_time': triggerTime,
        'trigger_device_id': triggerDeviceId,
        'trigger_condition': triggerCondition,
        'trigger_value': triggerValue,
        'trigger_days': triggerDays,
        'action_device_id': actionDeviceId,
        'action_type': actionType,
        'enabled': enabled,
        'last_run_at': lastRunAt?.toIso8601String(),
        'settings': settings,
      };
}
