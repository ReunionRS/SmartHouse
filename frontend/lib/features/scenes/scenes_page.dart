import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../models/home_assistant_room.dart';
import '../../models/local_room_device.dart';
import '../../models/smart_scene.dart';
import '../../services/scene_service.dart';
import '../../ui/device_asset_catalog.dart';

const _accent = Color(0xFFFF7A18);

enum ScenesView { automations, scenes }

IconData _presetIcon(String id) => switch (id) {
      'preset_home' => Icons.home_rounded,
      'preset_away' => Icons.directions_walk_rounded,
      'preset_morning' => Icons.wb_sunny_rounded,
      'preset_night' => Icons.bedtime_rounded,
      'preset_movie' => Icons.movie_rounded,
      'preset_vacation' => Icons.flight_takeoff_rounded,
      _ => Icons.auto_awesome_rounded,
    };

class ScenesPage extends StatefulWidget {
  const ScenesPage({
    super.key,
    required this.userId,
    required this.devices,
    required this.rooms,
    required this.onDevicesChanged,
    this.view = ScenesView.automations,
  });
  final String userId;
  final List<LocalRoomDevice> devices;
  final List<HomeAssistantRoom> rooms;
  final Future<void> Function() onDevicesChanged;
  final ScenesView view;

  @override
  State<ScenesPage> createState() => _ScenesPageState();
}

class _ScenesPageState extends State<ScenesPage> {
  final service = SceneService();
  List<SmartScene> scenes = const [];
  bool loading = true;

  List<SmartScene> get visibleScenes => scenes
      .where((scene) => widget.view == ScenesView.scenes
          ? ['manual', 'preset'].contains(scene.triggerType)
          : !['manual', 'preset'].contains(scene.triggerType))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final values = await Future.wait([
      service.load(widget.userId),
      service.loadHomeAssistant(),
      service.loadPresets(),
    ]);
    if (mounted) {
      setState(() {
        scenes = [...values[2], ...values[1], ...values[0]];
        loading = false;
      });
    }
  }

  Future<void> persist(List<SmartScene> value) async {
    setState(() => scenes = value);
    await service.save(
        widget.userId,
        value
            .where((item) =>
                item.triggerType != 'home_assistant' &&
                item.triggerType != 'preset' &&
                item.settings['source'] != 'smart_house')
            .toList());
  }

  Future<void> edit([SmartScene? scene]) async {
    if (widget.devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сначала добавьте устройство в комнату')));
      return;
    }
    final result = await Navigator.of(context).push<SmartScene>(
      MaterialPageRoute(
        builder: (_) => _SceneEditor(
          scene: scene,
          devices: widget.devices,
          manualOnly: widget.view == ScenesView.scenes,
        ),
      ),
    );
    if (result == null) return;
    if (scene?.settings['source'] == 'smart_house') {
      await service.updateLocalAutomation(result);
      await load();
      await widget.onDevicesChanged();
      return;
    }
    final value = [...scenes];
    final index = value.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      value.add(result);
    } else {
      value[index] = result;
    }
    await persist(value);
  }

  Future<void> toggleScene(SmartScene scene) async {
    final updated = scene.copyWith(enabled: !scene.enabled);
    if (scene.settings['source'] == 'smart_house') {
      await service.updateLocalAutomation(updated);
      await load();
      await widget.onDevicesChanged();
      return;
    }
    await persist([
      for (final item in scenes)
        if (item.id == scene.id) updated else item,
    ]);
  }

  Future<void> deleteScene(SmartScene scene) async {
    if (scene.settings['source'] == 'smart_house') {
      await service.deleteLocalAutomation(scene.id);
      await load();
      await widget.onDevicesChanged();
      return;
    }
    await persist(scenes.where((item) => item.id != scene.id).toList());
  }

  Future<void> configurePreset(SmartScene scene) async {
    if (scene.id == 'preset_away') {
      await _configureAway(scene);
      return;
    }
    final config = switch (scene.id) {
      'preset_home' => (
          'brightness',
          'Яркость основного света',
          'Свет включится с выбранной яркостью.',
          1.0,
          255.0,
          180.0
        ),
      'preset_morning' => (
          'brightness',
          'Утренняя яркость',
          'Основной свет включится мягко, без резкого перепада.',
          1.0,
          255.0,
          180.0
        ),
      'preset_night' => (
          'nightBrightness',
          'Яркость ночников',
          'Остальной свет будет выключен, ночники останутся включёнными.',
          1.0,
          255.0,
          35.0
        ),
      'preset_movie' => (
          'brightness',
          'Яркость подсветки',
          'Основной свет выключится, фоновая подсветка останется включённой.',
          1.0,
          255.0,
          45.0
        ),
      'preset_vacation' => (
          'temperature',
          'Температура отопления',
          'Минимальная температура для защиты дома во время отъезда.',
          8.0,
          22.0,
          16.0
        ),
      _ => null,
    };
    if (config == null) return;
    var selected = (scene.triggerValue > 0 ? scene.triggerValue : config.$6)
        .clamp(config.$4, config.$5);
    final value = await showDialog<num>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                title: Text(scene.name),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(config.$2,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(config.$3,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 13)),
                      const SizedBox(height: 20),
                      Center(
                          child: Text(
                              config.$1 == 'temperature'
                                  ? '${selected.round()} °C'
                                  : config.$5 > 100
                                      ? '${selected.round()} из 255'
                                      : '${selected.round()}%',
                              style: const TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.w700))),
                      Slider(
                          value: selected,
                          min: config.$4,
                          max: config.$5,
                          divisions: (config.$5 - config.$4).round(),
                          onChanged: (value) =>
                              setDialogState(() => selected = value)),
                    ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, selected),
                      child: const Text('Сохранить')),
                ],
              )),
    );
    if (value == null) return;
    await service.savePresetSettings(scene.id, {config.$1: value});
    await load();
  }

  Future<void> _configureAway(SmartScene scene) async {
    var lights = scene.settings['turnOffLights'] != false;
    var sockets = scene.settings['turnOffSockets'] != false;
    var lock = scene.settings['lockDoor'] != false;
    final result = await showDialog<Map<String, bool>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Я ушёл'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Выберите, что должен сделать дом при запуске сцены.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Выключить весь свет'),
                value: lights,
                onChanged: (value) => setDialogState(() => lights = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Выключить безопасные розетки'),
                subtitle: const Text('Защищённые устройства не отключаются.'),
                value: sockets,
                onChanged: (value) => setDialogState(() => sockets = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Закрыть входной замок'),
                subtitle: const Text('Приложение попросит подтверждение.'),
                value: lock,
                onChanged: (value) => setDialogState(() => lock = value),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'turnOffLights': lights,
                'turnOffSockets': sockets,
                'lockDoor': lock,
              }),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await service.savePresetSettings(scene.id, result);
    await load();
  }

  Future<void> run(SmartScene scene) async {
    try {
      var report = await service.run(widget.userId, scene);
      if (report?.status == 'confirmation_required' && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Подтвердите действие'),
            content: const Text(
                'Сцена содержит чувствительное действие, например управление входным замком.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Подтвердить')),
            ],
          ),
        );
        if (confirmed == true)
          report = await service.run(widget.userId, scene, confirmed: true);
        if (confirmed != true) return;
      }
      final index = scenes.indexWhere((item) => item.id == scene.id);
      final value = [...scenes];
      value[index] = scene.copyWith(lastRunAt: DateTime.now());
      await persist(value);
      await widget.onDevicesChanged();
      if (mounted) {
        final failed =
            report?.results.where((item) => item.status != 'success').length ??
                0;
        final message = report == null || report.status == 'success'
            ? 'Сцена «${scene.name}» выполнена'
            : 'Сцена выполнена частично: проблем — $failed';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
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
    return index < 0 ? 'Устройство удалено' : widget.devices[index].name;
  }

  String subtitle(SmartScene scene) {
    if (scene.triggerType == 'preset') return scene.triggerCondition;
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
          Text(widget.view == ScenesView.scenes ? 'СЦЕНЫ' : 'АВТОМАТИЗАЦИИ',
              style: const TextStyle(
                  color: Color(0xFFFF8A2A),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: Text(
                  widget.view == ScenesView.scenes
                      ? I18n.t('Сцены', 'Сценарийёс', 'Scenes')
                      : I18n.t(
                          'Автоматизации', 'Автоматизациос', 'Automations'),
                  style: const TextStyle(
                      fontSize: 29, fontWeight: FontWeight.w700)),
            ),
            IconButton.filled(
                onPressed: edit, icon: const Icon(Icons.add_rounded)),
          ]),
          const SizedBox(height: 8),
          Text(
            widget.view == ScenesView.scenes
                ? I18n.t(
                    'Запускайте готовые действия одним касанием.',
                    'Дась действиеосты одӥг басылӥськонэн кутты.',
                    'Run prepared actions with one tap.')
                : I18n.t(
                    'Автоматизируйте устройства по времени или показаниям датчиков.',
                    'Устройстваосты автоматизируй.',
                    'Automate devices by time or sensor state.'),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (loading)
            _ScenesLoading(scenesOnly: widget.view == ScenesView.scenes)
          else if (visibleScenes.isEmpty)
            _EmptyScenes(
              onAdd: edit,
              scenesOnly: widget.view == ScenesView.scenes,
            )
          else
            ...visibleScenes.map((scene) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Row(children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                            color: _accent.withOpacity(.14),
                            borderRadius: BorderRadius.circular(17)),
                        child: Icon(_presetIcon(scene.id),
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
                          if (value == 'settings') configurePreset(scene);
                          if (value == 'edit') edit(scene);
                          if (value == 'toggle') {
                            toggleScene(scene);
                          }
                          if (value == 'delete') {
                            deleteScene(scene);
                          }
                        },
                        itemBuilder: (_) => [
                          if (scene.triggerType == 'preset')
                            const PopupMenuItem(
                                value: 'settings', child: Text('Настроить'))
                          else if (scene.triggerType != 'home_assistant') ...[
                            const PopupMenuItem(
                                value: 'edit', child: Text('Изменить')),
                            PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                    scene.enabled ? 'Отключить' : 'Включить')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Удалить')),
                          ] else
                            const PopupMenuItem(
                                enabled: false,
                                child: Text('Управляется Home Assistant')),
                        ],
                      ),
                    ]),
                  ),
                )),
        ],
      );
}

class _ScenesLoading extends StatelessWidget {
  const _ScenesLoading({required this.scenesOnly});

  final bool scenesOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      decoration: BoxDecoration(
        color: colors.surface.withOpacity(.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withOpacity(.7)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _accent,
              strokeCap: StrokeCap.round,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            scenesOnly ? 'Загружаем сцены' : 'Загружаем автоматизации',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            'Синхронизация со Smart House Hub',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyScenes extends StatelessWidget {
  const _EmptyScenes({required this.onAdd, required this.scenesOnly});
  final VoidCallback onAdd;
  final bool scenesOnly;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(children: [
          const Icon(Icons.auto_awesome_outlined, color: _accent, size: 38),
          const SizedBox(height: 12),
          Text(scenesOnly ? 'Сцен пока нет' : 'Автоматизаций пока нет',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
              scenesOnly
                  ? 'Создайте набор действий для запуска одним касанием.'
                  : 'Создайте первое автоматическое действие для вашего дома.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 17),
          FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label:
                  Text(scenesOnly ? 'Создать сцену' : 'Создать автоматизацию')),
        ]),
      );
}

class _SceneEditor extends StatefulWidget {
  const _SceneEditor({
    required this.devices,
    required this.manualOnly,
    this.scene,
  });
  final List<LocalRoomDevice> devices;
  final SmartScene? scene;
  final bool manualOnly;

  @override
  State<_SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<_SceneEditor> {
  late final name = TextEditingController(text: widget.scene?.name ?? '');
  late String triggerType =
      widget.scene?.triggerType ?? (widget.manualOnly ? 'manual' : 'time');
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
          title: Text(
              widget.scene == null ? 'Новый сценарий' : 'Изменить сценарий'),
        ),
        body: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                const SizedBox(height: 18),
                TextField(
                    controller: name,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Название')),
                const SizedBox(height: 16),
                const _StepTitle(number: 1, title: 'Событие запуска'),
                const SizedBox(height: 6),
                Text('Выберите, когда должен запускаться сценарий',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
                const SizedBox(height: 9),
                if (!widget.manualOnly)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'time', label: Text('Время')),
                      ButtonSegment(value: 'device', label: Text('Датчик')),
                    ],
                    selected: {triggerType},
                    onSelectionChanged: (value) =>
                        setState(() => triggerType = value.first),
                  )
                else
                  const _EditorNotice(
                      'Сцена запускается вручную одним касанием.'),
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
                  const _FieldLabel('Какой датчик отслеживать'),
                  const SizedBox(height: 8),
                  if (sensorDevices.isEmpty)
                    const _EditorNotice('В комнатах пока нет датчиков')
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
                    const _FieldLabel('При каком состоянии запустить'),
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
                Text('Выберите устройство, которым нужно управлять',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
                const SizedBox(height: 12),
                if (actionDevices.isEmpty)
                  const _EditorNotice('Нет устройств, которыми можно управлять')
                else
                  _DeviceChoices(
                    devices: actionDevices,
                    selectedId: actionDeviceId,
                    onChanged: (value) =>
                        setState(() => actionDeviceId = value),
                  ),
                const SizedBox(height: 16),
                const _FieldLabel('Что сделать с устройством'),
                const SizedBox(height: 8),
                _ActionSelector(
                  value: actionType,
                  onChanged: (value) => setState(() => actionType = value),
                ),
                const SizedBox(height: 22),
                const _StepTitle(number: 3, title: 'Готовое правило'),
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
                              settings: widget.scene?.settings ?? const {},
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
                        color: value == action.$1
                            ? _accent
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: value == action.$1 ? 2 : 1),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.$3,
                            size: 22,
                            color: value == action.$1
                                ? _accent
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
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
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                    color: selected
                        ? _accent
                        : Theme.of(context).colorScheme.outlineVariant,
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
