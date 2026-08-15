import 'package:flutter/material.dart';

import '../../models/home_dashboard.dart';

class HomeDashboardSettingsPage extends StatefulWidget {
  const HomeDashboardSettingsPage({
    super.key,
    required this.preferences,
    required this.availableIds,
  });

  final DashboardPreferences preferences;
  final Set<String> availableIds;

  @override
  State<HomeDashboardSettingsPage> createState() =>
      _HomeDashboardSettingsPageState();
}

class _HomeDashboardSettingsPageState extends State<HomeDashboardSettingsPage> {
  late List<String> enabled = [...widget.preferences.enabled];
  late bool visible = widget.preferences.visible;
  late List<String> orderedIds = [
    ...widget.preferences.enabled,
    ...DashboardPreferences.defaultIds
        .where((id) => !widget.preferences.enabled.contains(id)),
  ];

  static const labels = {
    'temperature': ('Температура', Icons.thermostat_rounded),
    'humidity': ('Влажность', Icons.water_drop_outlined),
    'power': ('Текущая мощность', Icons.bolt_rounded),
    'energy': ('Энергопотребление', Icons.energy_savings_leaf_outlined),
    'lights': ('Включённый свет', Icons.lightbulb_outline_rounded),
    'openings': ('Открытые двери и окна', Icons.sensor_door_outlined),
    'low_battery': ('Низкий заряд', Icons.battery_alert_outlined),
    'unavailable': ('Недоступные устройства', Icons.cloud_off_outlined),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Сводка главного экрана'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context,
                  DashboardPreferences(enabled: enabled, visible: visible)),
              child: const Text('Готово'),
            ),
          ],
        ),
        body: ReorderableListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          header: Column(
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined,
                      color: Color(0xFFFF7A18)),
                  title: const Text('Показывать блок'),
                  subtitle: const Text(
                      'Сводка полностью скрывается с главного экрана'),
                  value: visible,
                  onChanged: (value) => setState(() => visible = value),
                ),
              ),
              if (visible)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  child: Text(
                    'Выберите показатели и перетащите их в нужном порядке. Карточки без источника данных не появятся на главном экране.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = orderedIds.removeAt(oldIndex);
              orderedIds.insert(newIndex, item);
              enabled = orderedIds.where(enabled.contains).toList();
            });
          },
          children: visible
              ? [
                  for (final id in orderedIds)
                    Builder(
                      key: ValueKey(id),
                      builder: (context) {
                        final info = labels[id]!;
                        final selected = enabled.contains(id);
                        final available = widget.availableIds.contains(id);
                        return Card(
                          child: SwitchListTile(
                            secondary: Icon(info.$2,
                                color:
                                    available ? const Color(0xFFFF7A18) : null),
                            title: Text(info.$1),
                            subtitle: Text(available
                                ? 'Источник данных найден'
                                : 'Сейчас нет подходящего датчика'),
                            value: selected,
                            onChanged: (value) => setState(() {
                              if (value) {
                                enabled.add(id);
                              } else {
                                enabled.remove(id);
                              }
                            }),
                          ),
                        );
                      },
                    ),
                ]
              : const [],
        ),
      );
}
