import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/home_dashboard.dart';
import 'auth_service.dart';
import 'hub_state_service.dart';

class HomeDashboardService {
  final AuthService _auth = AuthService();
  final HubStateService _hubState = HubStateService();

  Future<DashboardPreferences> loadPreferences(String userId) async {
    try {
      final values = await _hubState.load(
        key: 'dashboard_settings',
        legacyPreferenceKey: 'dashboard_settings_$userId',
      );
      if (values.isNotEmpty && values.first is Map<String, dynamic>) {
        return DashboardPreferences.fromJson(
            values.first as Map<String, dynamic>);
      }
    } catch (_) {}
    return const DashboardPreferences(enabled: DashboardPreferences.defaultIds);
  }

  Future<void> savePreferences(DashboardPreferences value) => _hubState.save(
        key: 'dashboard_settings',
        value: [value.toJson()],
      );

  Future<List<DashboardMetric>> loadMetrics(
      DashboardPreferences preferences) async {
    final session = await _auth.getSession();
    if (session == null) return const [];
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/home-assistant/snapshot'),
      headers: {'Authorization': 'Bearer ${session.token}'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return const [];
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> || body['devices'] is! List)
      return const [];
    final devices =
        (body['devices'] as List).whereType<Map<String, dynamic>>().toList();
    String deviceClass(Map<String, dynamic> item) =>
        ((item['attributes'] as Map?)?['device_class'] ?? '').toString();
    String unit(Map<String, dynamic> item) =>
        ((item['attributes'] as Map?)?['unit_of_measurement'] ?? '').toString();
    double? number(Map<String, dynamic> item) =>
        double.tryParse('${item['state']}');
    List<Map<String, dynamic>> sensors(String type) => devices
        .where((item) =>
            item['available'] == true &&
            deviceClass(item) == type &&
            number(item) != null)
        .toList();
    String source(List<Map<String, dynamic>> values) => values.length == 1
        ? (values.first['name'] ?? '').toString()
        : '${values.length} датчика';
    final result = <DashboardMetric>[];
    final temperatures = sensors('temperature');
    if (temperatures.isNotEmpty) {
      final average =
          temperatures.map(number).whereType<double>().reduce((a, b) => a + b) /
              temperatures.length;
      result.add(DashboardMetric(
          id: 'temperature',
          title: 'Температура',
          value: '${average.toStringAsFixed(1)}°',
          icon: Icons.thermostat_rounded,
          source: source(temperatures)));
    }
    final humidity = sensors('humidity');
    if (humidity.isNotEmpty) {
      final average =
          humidity.map(number).whereType<double>().reduce((a, b) => a + b) /
              humidity.length;
      result.add(DashboardMetric(
          id: 'humidity',
          title: 'Влажность',
          value: '${average.round()}%',
          icon: Icons.water_drop_outlined,
          source: source(humidity)));
    }
    final power = sensors('power');
    if (power.isNotEmpty) {
      final total = power
          .map(number)
          .whereType<double>()
          .fold<double>(0, (a, b) => a + b);
      final rawUnit = unit(power.first);
      result.add(DashboardMetric(
          id: 'power',
          title: 'Мощность',
          value:
              '${total.toStringAsFixed(total >= 10 ? 0 : 1)} ${rawUnit.isEmpty ? 'W' : rawUnit}',
          icon: Icons.bolt_rounded,
          source: source(power)));
    }
    final energy = sensors('energy');
    if (energy.isNotEmpty) {
      final total = energy
          .map(number)
          .whereType<double>()
          .fold<double>(0, (a, b) => a + b);
      result.add(DashboardMetric(
          id: 'energy',
          title: 'Энергия',
          value: '${total.toStringAsFixed(1)} ${unit(energy.first)}',
          icon: Icons.energy_savings_leaf_outlined,
          source: source(energy)));
    }
    final lights = devices.where((item) => item['domain'] == 'light').toList();
    if (lights.isNotEmpty)
      result.add(DashboardMetric(
          id: 'lights',
          title: 'Свет',
          value:
              '${lights.where((item) => item['state'] == 'on').length}/${lights.length}',
          icon: Icons.lightbulb_outline_rounded));
    final openings = devices
        .where((item) =>
            item['domain'] == 'binary_sensor' &&
            const {'door', 'window', 'opening', 'garage_door'}
                .contains(deviceClass(item)))
        .toList();
    if (openings.isNotEmpty)
      result.add(DashboardMetric(
          id: 'openings',
          title: 'Открыто',
          value:
              '${openings.where((item) => item['state'] == 'on' || item['state'] == 'open').length}',
          icon: Icons.sensor_door_outlined));
    final batteries = sensors('battery');
    if (batteries.isNotEmpty)
      result.add(DashboardMetric(
          id: 'low_battery',
          title: 'Низкий заряд',
          value: '${batteries.where((item) => number(item)! <= 20).length}',
          icon: Icons.battery_alert_outlined));
    if (devices.isNotEmpty)
      result.add(DashboardMetric(
          id: 'unavailable',
          title: 'Недоступно',
          value: '${devices.where((item) => item['available'] != true).length}',
          icon: Icons.cloud_off_outlined));
    final byId = {for (final item in result) item.id: item};
    return preferences.enabled
        .map((id) => byId[id])
        .whereType<DashboardMetric>()
        .toList();
  }
}
