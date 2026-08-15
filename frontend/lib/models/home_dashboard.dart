import 'package:flutter/material.dart';

class DashboardMetric {
  const DashboardMetric({
    required this.id,
    required this.title,
    required this.value,
    required this.icon,
    this.source = '',
  });

  final String id;
  final String title;
  final String value;
  final IconData icon;
  final String source;
}

class DashboardPreferences {
  const DashboardPreferences({required this.enabled, this.visible = true});

  static const defaultIds = [
    'temperature',
    'humidity',
    'power',
    'energy',
    'lights',
    'openings',
    'low_battery',
    'unavailable',
  ];

  final List<String> enabled;
  final bool visible;

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    final raw = json['enabled'];
    return DashboardPreferences(
      visible: json['visible'] != false,
      enabled: raw is List
          ? raw
              .map((item) => item.toString())
              .where(defaultIds.contains)
              .toList()
          : defaultIds,
    );
  }

  Map<String, dynamic> toJson() => {'enabled': enabled, 'visible': visible};
}
