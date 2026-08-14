import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/home_assistant_room.dart';
import '../../models/local_room_device.dart';
import '../../models/smart_scene.dart';
import '../../services/scene_service.dart';
import '../../ui/device_asset_catalog.dart';

const _accent = Color(0xFFFF7A18);

class ScenesPage extends StatefulWidget {
  const ScenesPage({
    super.key,
    required this.userId,
    required this.devices,
    required this.rooms,
    required this.onDevicesChanged,
  });
  final String userId;
  final List<LocalRoomDevice> devices;
  final List<HomeAssistantRoom> rooms;
  final Future<void> Function() onDevicesChanged;

  @override
  State<ScenesPage> createState() => _ScenesPageState();
}

class _ScenesPageState extends State<ScenesPage> {
  final service = SceneService();
  List<SmartScene> scenes = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await Future.wait([
      service.load(widget.userId),
      service.loadHomeAssistant(),
    ]);
    if (mounted) setState(() => scenes = [...values[1], ...values[0]]);
  }

  Future<void> persist(List<SmartScene> value) async {
    setState(() => scenes = value);
    await service.save(widget.userId,
        value.where((item) => item.triggerType != 'home_assistant').toList());
  }

  Future<void> edit([SmartScene? scene]) async {
    if (widget.devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Сначала добавьте устройство в комнату')));
      return;
    }
    final result = await Navigator.of(context).push<SmartScene>(
      MaterialPageRoute(
        builder: (_) => _SceneEditor(scene: scene, devices: widget.devices),
      ),
    );
    if (result == null) return;
    final value = [...scenes];
    final index = value.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      value.add(result);
    } else {
      value[index] = result;
    }
    await persist(value);
  }

  Future<void> run(SmartScene scene) async {
    try {
      await service.run(widget.userId, scene);
      final index = scenes.indexWhere((item) => item.id == scene.id);
      final value = [...scenes];
      value[index] = scene.copyWith(lastRunAt: DateTime.now());
      await persist(value);
      await widget.onDevicesChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Сценарий «${scene.name}» выполнен')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  String deviceName(String id) {
    final index = widget.devices.indexWhere((item) => item.id == id);
    return index < 0
        ? 'Устройство удалено'
        : widget.devices[index].name;
  }

  String subtitle(SmartScene scene) {
    if (scene.triggerType == 'home_assistant') {
      final lastRun = scene.lastRunAt;
      return lastRun == null
          ? 'Автоматизация Home Assistant'
          : 'Home Assistant · запуск ${lastRun.toLocal()}';
    }
    final trigger = scene.triggerType == 'time'
        ? 'В ${scene.triggerTime}'
        : scene.triggerType == 'device'
            ? 'Сигнал: ${deviceName(scene.triggerDeviceId)}'
            : 'Ручной запуск';
    final action = switch (scene.actionType) {
      'turn_off' => 'выключить',
      'toggle' => 'переключить',
      _ => 'включить',
    };
    return '$trigger → $action ${deviceName(scene.actionDeviceId)}';
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 72, 20, 120),
        children: [
          const Text('АВТОМАТИЗАЦИИ',
              style: TextStyle(
                  color: Color(0xFFFF8A2A),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: Text(
                  I18n.t('Умные сценарии', 'Сценарийёс',
                      'Smart scenes'),
                  style: const TextStyle(
                      fontSize: 29, fontWeight: FontWeight.w700)),
            ),
            IconButton.filled(
                onPressed: edit, icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 8),
          Text(
            I18n.t(
                'Автоматизируйте устройства и запускайте действия одним касанием.',
                'Устройстваосты автоматизируй.',
                'Automate devices and run actions with one tap.'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (scenes.isEmpty)
            _EmptyScenes(onAdd: edit)
          else
            ...scenes.map((scene) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                            color: _accent.withOpacity(.14),
                            borderRadius: BorderRadius.circular(17)),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Color(0xFFFF8A2A)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(scene.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(subtitle(scene),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 11)),
                            ]),
                      ),
                      IconButton(
                        tooltip: 'Запустить',
                        onPressed: scene.enabled ? () => run(scene) : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        color: _accent,
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') edit(scene);
                          if (value == 'toggle') {
                            persist([
                              for (final item in scenes)
                                if (item.id == scene.id)
                                  item.copyWith(enabled: !item.enabled)
                                else
                                  item,
                            ]);
                          }
                          if (value == 'delete') {
                            persist(scenes
                                .where((item) => item.id != scene.id)
                                .toList());
                          }
                        },
                        itemBuilder: (_) => [
                          if (scene.triggerType != 'home_assistant') ...[
                            const PopupMenuItem(
                                value: 'edit', child: Text('Изменить')),
                            PopupMenuItem(
                                value: 'toggle',
                                child: Text(scene.enabled
                                    ? 'Отключить'
                                    : 'Включить')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Удалить')),
                          ] else
                            const PopupMenuItem(
                                enabled: false,
                                child: Text(
                                    'Управляется Home Assistant')),
                        ],
                      ),
                    ]),
                  ),
                )),
        ],
      );
}
class _EmptyScenes extends StatelessWidget {
  const _EmptyScenes({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          const Icon(Icons.auto_awesome_outlined, color: _accent, size: 38),
          const SizedBox(height: 12),
          const Text('Сценариев пока нет',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              'Создайте первое автоматическое действие для вашего дома.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 17),
          FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать сценарий')),
        ]),
      );
}

class _SceneEditor extends StatefulWidget {
  const _SceneEditor({required this.devices, this.scene});
  final List<LocalRoomDevice> devices;
  final SmartScene? scene;

  @override
  State<_SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<_SceneEditor> {
  late final name = TextEditingController(text: widget.scene?.name ?? '');
  late String triggerType = widget.scene?.triggerType ?? 'manual';
  late String triggerTime = widget.scene?.triggerTime ?? '08:00';
  late String triggerDeviceId;
  late String actionDeviceId;
  late String triggerCondition = widget.scene?.triggerCondition ?? 'active';
  late double triggerValue = widget.scene?.triggerValue ?? 25;
  late Set<int> triggerDays =
      (widget.scene?.triggerDays ?? const [0, 1, 2, 3, 4, 5, 6]).toSet();
  late String actionType = widget.scene?.actionType ?? 'turn_on';

  List<LocalRoomDevice> get sensorDevices => widget.devices
      .where((device) => const {
            'temperature_humidity_sensor',
            'motion_sensor',
            'leak_sensor',
            'smoke_sensor',
          }.contains(device.type))
      .toList(growable: false);

  List<LocalRoomDevice> get actionDevices => widget.devices
      .where((device) => const {
            'light',
            'rgb_light',
            'rgb_strip',
            'socket',
            'air_conditioner',
            'thermostat',
            'lock',
          }.contains(device.type))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final sensors = sensorDevices;
    final actions = actionDevices;
    triggerDeviceId =
        sensors.any((item) => item.id == widget.scene?.triggerDeviceId)
            ? widget.scene!.triggerDeviceId
            : (sensors.isEmpty ? '' : sensors.first.id);
    actionDeviceId =
        actions.any((item) => item.id == widget.scene?.actionDeviceId)
            ? widget.scene!.actionDeviceId
            : (actions.isEmpty ? '' : actions.first.id);
    _normalizeCondition();
  }

  LocalRoomDevice? get selectedSensor {
    for (final device in sensorDevices) {
      if (device.id == triggerDeviceId) return device;
    }
    return null;
  }

  void _normalizeCondition() {
    final allowed = _conditionsFor(selectedSensor?.type).map((item) => item.$1);
    if (!allowed.contains(triggerCondition)) {
      triggerCondition = allowed.isEmpty ? 'active' : allowed.first;
    }
  }

  List<(String, String)> _conditionsFor(String? type) => switch (type) {
        'temperature_humidity_sensor' => const [
            ('temperature_above', 'Температура выше'),
            ('temperature_below', 'Температура ниже'),
            ('humidity_above', 'Влажность выше'),
            ('humidity_below', 'Влажность ниже'),
          ],
        'motion_sensor' => const [
            ('active', 'Движение обнаружено'),
            ('inactive', 'Движение прекратилось'),
          ],
        'leak_sensor' => const [
            ('active', 'Обнаружена протечка'),
            ('inactive', 'Протечка устранена'),
          ],
        'smoke_sensor' => const [
            ('active', 'Обнаружен дым'),
            ('inactive', 'Воздух в норме'),
          ],
        _ => const [],
      };

  String _deviceName(String id) {
    for (final device in widget.devices) {
      if (device.id == id) return device.name;
    }
    return 'устройство';
  }

  String get summary {
    final action = switch (actionType) {
      'turn_off' => 'выключить',
      'toggle' => 'переключить',
      _ => 'включить',
    };
    final condition = _conditionsFor(selectedSensor?.type)
        .firstWhere((item) => item.$1 == triggerCondition,
            orElse: () => const ('active', 'Сработал датчик'))
        .$2
        .toLowerCase();
    final threshold = selectedSensor?.type == 'temperature_humidity_sensor'
        ? ' ${triggerValue.round()}${triggerCondition.startsWith('humidity') ? '%' : '°C'}'
        : '';
    final start = switch (triggerType) {
      'time' => 'В $triggerTime',
      'device' =>
        'Если «${_deviceName(triggerDeviceId)}»: $condition$threshold',
      _ => 'При ручном запуске',
    };
    return '$start — $action «${_deviceName(actionDeviceId)}».';
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> pickTime() async {
    final parts = triggerTime.split(':');
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts.first) ?? 8,
          minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
    );
    if (value != null) {
      setState(() => triggerTime =
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: Text(widget.scene == null
              ? 'Новый сценарий'
              : 'Изменить сценарий'),
        ),
        body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const SizedBox(height: 18),
                TextField(
                    controller: name,
                    onChanged: (_) => setState(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Название')),
                const SizedBox(height: 16),
                const _StepTitle(
                    number: 1, title: 'Событие запуска'),
                const SizedBox(height: 6),
                const Text(
                    'Выберите, когда должен запускаться сценарий',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 9),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'manual', label: Text('Вручную')),
                    ButtonSegment(value: 'time', label: Text('Время')),
                    ButtonSegment(value: 'device', label: Text('Датчик')),
                  ],
                  selected: {triggerType},
                  onSelectionChanged: (value) =>
                      setState(() => triggerType = value.first),
                ),
                if (triggerType == 'time') ...[
                  const SizedBox(height: 10),
                  ListTile(
                    onTap: pickTime,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    tileColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Время запуска'),
                    trailing: Text(triggerTime,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Дни недели',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final day in const [
                        'Пн',
                        'Вт',
                        'Ср',
                        'Чт',
                        'Пт',
                        'Сб',
                        'Вс'
                      ])
                        ChoiceChip(
                          label: Text(day),
                          selected: triggerDays.contains(const [
                            'Пн',
                            'Вт',
                            'Ср',
                            'Чт',
                            'Пт',
                            'Сб',
                            'Вс'
                          ].indexOf(day)),
                          onSelected: (selected) => setState(() {
                            final index = const [
                              'Пн',
                              'Вт',
                              'Ср',
                              'Чт',
                              'Пт',
                              'Сб',
                              'Вс'
                            ].indexOf(day);
                            if (selected) {
                              triggerDays.add(index);
                            } else if (triggerDays.length > 1) {
                              triggerDays.remove(index);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                if (triggerType == 'device') ...[
                  const SizedBox(height: 16),
                  const _FieldLabel(
                      'Какой датчик отслеживать'),
                  const SizedBox(height: 8),
                  if (sensorDevices.isEmpty)
                    const _EditorNotice(
                        'В комнатах пока нет датчиков')
                  else ...[
                    _DeviceChoices(
                      devices: sensorDevices,
                      selectedId: triggerDeviceId,
                      onChanged: (value) => setState(() {
                        triggerDeviceId = value;
                        _normalizeCondition();
                      }),
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel(
                        'При каком состоянии запустить'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final condition
                            in _conditionsFor(selectedSensor?.type))
                          ChoiceChip(
                            label: Text(condition.$2),
                            selected: triggerCondition == condition.$1,
                            onSelected: (_) =>
                                setState(() => triggerCondition = condition.$1),
                          ),
                      ],
                    ),
                    if (selectedSensor?.type ==
                        'temperature_humidity_sensor') ...[
                      const SizedBox(height: 12),
                      _FieldLabel(
                          'Порог: ${triggerValue.round()}${triggerCondition.startsWith('humidity') ? '%' : '°C'}'),
                      Slider(
                        value: triggerValue.clamp(0, 100),
                        min: triggerCondition.startsWith('humidity') ? 0 : 5,
                        max: triggerCondition.startsWith('humidity') ? 100 : 40,
                        divisions:
                            triggerCondition.startsWith('humidity') ? 20 : 35,
                        onChanged: (value) =>
                            setState(() => triggerValue = value),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 28),
                const _StepTitle(number: 2, title: 'Действие'),
                const SizedBox(height: 6),
                const Text(
                    'Выберите устройство, которым нужно управлять',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                if (actionDevices.isEmpty)
                  const _EditorNotice(
                      'Нет устройств, которыми можно управлять')
                else
                  _DeviceChoices(
                    devices: actionDevices,
                    selectedId: actionDeviceId,
                    onChanged: (value) =>
                        setState(() => actionDeviceId = value),
                  ),
                const SizedBox(height: 16),
                const _FieldLabel(
                    'Что сделать с устройством'),
                const SizedBox(height: 8),
                _ActionSelector(
                  value: actionType,
                  onChanged: (value) => setState(() => actionType = value),
                ),
                const SizedBox(height: 22),
                const _StepTitle(
                    number: 3, title: 'Готовое правило'),
                const SizedBox(height: 9),
                _EditorNotice(summary),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: name.text.trim().isEmpty ||
                          actionDeviceId.isEmpty ||
                          (triggerType == 'device' && triggerDeviceId.isEmpty)
                      ? null
                      : () => Navigator.pop(
                            context,
                            SmartScene(
                              id: widget.scene?.id ??
                                  'scene_${DateTime.now().microsecondsSinceEpoch}',
                              name: name.text.trim(),
                              triggerType: triggerType,
                              triggerTime: triggerTime,
                              triggerDeviceId: triggerDeviceId,
                              triggerCondition: triggerCondition,
                              triggerValue: triggerValue,
                              triggerDays: triggerDays.toList()..sort(),
                              actionDeviceId: actionDeviceId,
                              actionType: actionType,
                              enabled: widget.scene?.enabled ?? true,
                              lastRunAt: widget.scene?.lastRunAt,
                            ),
                          ),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: const Text('Сохранить'),
                ),
              ]),
        ),
      );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: _accent, shape: BoxShape.circle),
          child: Text('$number',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ]);
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
}

class _ActionSelector extends StatelessWidget {
  const _ActionSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final action in const [
            ('turn_on', 'Включить', Icons.power_settings_new_rounded),
            ('turn_off', 'Выключить', Icons.power_off_rounded),
            ('toggle', 'Переключить', Icons.sync_rounded),
          ]) ...[
            if (action.$1 != 'turn_on') const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => onChanged(action.$1),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 74,
                  decoration: BoxDecoration(
                    color: value == action.$1
                        ? _accent.withOpacity(.24)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: value == action.$1 ? _accent : Colors.white12,
                        width: value == action.$1 ? 2 : 1),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.$3,
                            size: 22,
                            color:
                                value == action.$1 ? _accent : Colors.white70),
                        const SizedBox(height: 5),
                        Text(action.$2,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                ),
              ),
            ),
          ],
        ],
      );
}

class _EditorNotice extends StatelessWidget {
  const _EditorNotice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}

class _DeviceChoices extends StatelessWidget {
  const _DeviceChoices({
    required this.devices,
    required this.selectedId,
    required this.onChanged,
  });
  final List<LocalRoomDevice> devices;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 112,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: devices.length,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (_, index) {
            final device = devices[index];
            final selected = device.id == selectedId;
            return InkWell(
              onTap: () => onChanged(device.id),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 125,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? _accent : Colors.white12,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Stack(children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 72,
                              height: 62,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.asset(
                                  DeviceAssetCatalog.forType(device.type) ??
                                      DeviceAssetCatalog.hub,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(device.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                  if (selected)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: Icon(Icons.check_circle_rounded,
                          color: _accent, size: 18),
                    ),
                ]),
              ),
            );
          },
        ),
      );
}
