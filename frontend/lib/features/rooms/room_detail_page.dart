import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../../core/i18n.dart';
import '../../models/home_assistant_room.dart';
import '../../models/local_room_device.dart';
import '../../services/room_service.dart';
import '../../ui/device_asset_catalog.dart';

const _accent = Color(0xFFFF7A18);

class RoomDetailPage extends StatefulWidget {
  const RoomDetailPage({
    super.key,
    required this.room,
    required this.roomIndex,
    required this.userId,
    required this.service,
  });
  final HomeAssistantRoom room;
  final int roomIndex;
  final String userId;
  final RoomService service;

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  List<LocalRoomDevice> devices = const [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final all = await widget.service.loadDevices(widget.userId);
    if (mounted) {
      setState(() => devices =
          all.where((item) => item.roomId == widget.room.areaId).toList());
    }
  }

  Future<void> addDevice() async {
    final draft = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddDeviceSheet(),
    );
    if (draft == null) return;
    final device = await widget.service.addDevice(
      userId: widget.userId,
      roomId: widget.room.areaId,
      name: draft.$1,
      type: draft.$2,
    );
    await load();
    if (mounted) openDevice(device);
  }

  Future<void> openDevice(LocalRoomDevice device) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SmartLightPage(
        device: device,
        userId: widget.userId,
        service: widget.service,
      ),
    ));
    await load();
  }

  Future<void> deleteDevice(LocalRoomDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(I18n.t(
            'Удалить устройство?', 'Устройствоез быдтыны?', 'Delete device?')),
        content: Text(I18n.t(
          '«${device.name}» будет удалено из комнаты «${widget.room.name}» и из избранного.',
          '«${device.name}» быдтоз.',
          '“${device.name}” will be removed from “${widget.room.name}” and favorites.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(I18n.t('Отмена', 'Кошкыны', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(I18n.t('Удалить', 'Быдтыны', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.deleteDevice(widget.userId, device.id);
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 285,
          pinned: true,
          stretch: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          leading: _RoundButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context)),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              RoomAtlasImage(
                  index: widget.roomIndex, roomName: widget.room.name),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black12,
                      Colors.transparent,
                      Colors.black87
                    ],
                    stops: [0, .48, 1],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Text(widget.room.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text('${devices.length} ${_deviceWord(devices.length)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
          sliver: SliverList.list(children: [
            Row(children: [
              Expanded(
                child: Text(I18n.t('Устройства', 'Устройстваос', 'Devices'),
                    style: TextStyle(
                        color: fg, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: addDevice,
                icon: const Icon(Icons.add_rounded),
                label: Text(I18n.t('Добавить', 'Ватсаны', 'Add')),
              ),
            ]),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: _cardDecoration(context),
                child: Column(children: [
                  const Icon(Icons.sensors_off_outlined,
                      color: _accent, size: 34),
                  const SizedBox(height: 12),
                  Text(
                      I18n.t(
                          'В комнате пока нет устройств',
                          'Комнатаын устройстваос ӧвӧл',
                          'No devices in this room yet'),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(
                      I18n.t(
                          'Добавьте лампу, датчик или другое устройство.',
                          'Лампа я датчик ватса.',
                          'Add a light, sensor, or another device.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: addDevice,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(I18n.t('Добавить устройство',
                        'Устройство ватсаны', 'Add device')),
                  ),
                ]),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: devices.length + 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 190,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (_, index) {
                  if (index == devices.length) {
                    return _AddDeviceCard(onTap: addDevice);
                  }
                  final device = devices[index];
                  return _DeviceTile(
                    device: device,
                    onTap: () => openDevice(device),
                    onDelete: () => deleteDevice(device),
                  );
                },
              ),
          ]),
        ),
      ]),
    );
  }
}

class SmartLightPage extends StatefulWidget {
  const SmartLightPage({
    super.key,
    required this.device,
    required this.userId,
    required this.service,
  });
  final LocalRoomDevice device;
  final String userId;
  final RoomService service;

  @override
  State<SmartLightPage> createState() => _SmartLightPageState();
}

class _SmartLightPageState extends State<SmartLightPage> {
  late LocalRoomDevice device = widget.device;

  Future<void> update(LocalRoomDevice value) async {
    setState(() => device = value);
    await widget.service.updateDevice(widget.userId, value);
  }

  Future<void> rename() async {
    final controller = TextEditingController(text: device.name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            I18n.t('Название устройства', 'Устройство ним', 'Device name')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(I18n.t('Отмена', 'Кошкыны', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: Text(I18n.t('Сохранить', 'Утчаны', 'Save'))),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty) {
      await update(device.copyWith(name: value.trim()));
    }
  }

  Future<String?> pickTime(String current) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final selected =
        await showTimePicker(context: context, initialTime: initial);
    if (selected == null) return null;
    return '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
  }

  Future<void> openSchedule() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleSheet(
        device: device,
        onChanged: update,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = Theme.of(context).colorScheme.onSurface;
    final asset = device.type == 'light'
        ? DeviceAssetCatalog.lightForMode(device.mode)
        : DeviceAssetCatalog.forType(device.type) ?? DeviceAssetCatalog.light;
    final isLight = device.type == 'light' ||
        device.type == 'rgb_light' ||
        device.type == 'rgb_strip';
    final isRgb = device.type == 'rgb_light' || device.type == 'rgb_strip';
    final isEnvironment = device.type == 'temperature_humidity_sensor';
    final isSensor =
        device.type == 'motion_sensor' || device.type == 'leak_sensor';
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF151B24) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded)),
        title: Text(device.name),
        actions: [
          IconButton(
              onPressed: rename, icon: const Icon(Icons.more_vert_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          if (device.type == 'light')
            _LightModeTabs(
              value: device.mode,
              onChanged: (value) => update(device.copyWith(mode: value)),
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 330,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xFF313947), Color(0xFF111720)],
                  radius: .82,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  color:
                      device.isOn ? null : Colors.black.withValues(alpha: .48),
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (isEnvironment)
            Row(children: [
              Expanded(
                  child: _SensorValueCard(
                icon: MdiIcons.thermometer,
                label: I18n.t('Температура', 'Температура', 'Temperature'),
                value: '${device.temperature.toStringAsFixed(1)}°C',
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: _SensorValueCard(
                icon: MdiIcons.waterPercent,
                label: I18n.t('Влажность', 'Влажность', 'Humidity'),
                value: '${device.humidity.round()}%',
              )),
            ])
          else if (!isSensor)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: _cardDecoration(context),
              child: Row(children: [
                IconButton.filledTonal(
                  onPressed: () => update(device.copyWith(isOn: !device.isOn)),
                  icon: const Icon(Icons.power_settings_new_rounded),
                ),
                if (isLight)
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 9,
                        activeTrackColor: _accent,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: _accent,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 12),
                      ),
                      child: Slider(
                        value: device.brightness,
                        min: 1,
                        max: 100,
                        onChanged: (value) => setState(() => device =
                            device.copyWith(brightness: value, isOn: true)),
                        onChangeEnd: (value) => widget.service.updateDevice(
                          widget.userId,
                          device.copyWith(brightness: value, isOn: true),
                        ),
                      ),
                    ),
                  ),
                if (isLight)
                  SizedBox(
                    width: 44,
                    child: Text('${device.brightness.round()}%',
                        textAlign: TextAlign.end,
                        style:
                            TextStyle(color: fg, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          if (isRgb) ...[
            const SizedBox(height: 18),
            Text(I18n.t('Настройки RGB', 'RGB келянъёс', 'RGB settings'),
                style: TextStyle(
                    color: fg, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              decoration: _cardDecoration(context),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color:
                          HSVColor.fromAHSV(1, device.rgbHue, 1, 1).toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(I18n.t(
                        'Цвет свечения', 'Югытлэн тусыз', 'Light color')),
                  ),
                  Text('${device.rgbHue.round()}°',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                ]),
                Slider(
                  value: device.rgbHue,
                  min: 0,
                  max: 360,
                  activeColor:
                      HSVColor.fromAHSV(1, device.rgbHue, 1, 1).toColor(),
                  onChanged: (value) =>
                      setState(() => device = device.copyWith(rgbHue: value)),
                  onChangeEnd: (value) => widget.service.updateDevice(
                      widget.userId, device.copyWith(rgbHue: value)),
                ),
                DropdownButtonFormField<String>(
                  value: device.rgbEffect,
                  decoration: InputDecoration(
                    labelText: I18n.t(
                        'Эффект свечения', 'Югыт эффект', 'Lighting effect'),
                  ),
                  items: [
                    DropdownMenuItem(
                        value: 'steady',
                        child: Text(
                            I18n.t('Постоянный свет', 'Ӵужон югыт', 'Steady'))),
                    DropdownMenuItem(
                        value: 'pulse',
                        child: Text(I18n.t('Пульсация', 'Пульсация', 'Pulse'))),
                    DropdownMenuItem(
                        value: 'rainbow',
                        child: Text(I18n.t('Радуга', 'Вуон', 'Rainbow'))),
                    DropdownMenuItem(
                        value: 'music',
                        child: Text(I18n.t(
                            'В ритм музыке', 'Крезь ритм', 'Music rhythm'))),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      update(device.copyWith(rgbEffect: value));
                    }
                  },
                ),
              ]),
            ),
          ],
          const SizedBox(height: 22),
          if (isSensor)
            _SensorStatusTile(
              icon: device.type == 'leak_sensor'
                  ? MdiIcons.waterCheckOutline
                  : MdiIcons.motionSensor,
              label: I18n.t(
                  'Состояние датчика', 'Датчиклэн интые', 'Sensor status'),
              title: device.type == 'leak_sensor'
                  ? (device.isOn
                      ? I18n.t(
                          'Обнаружена протечка', 'Ву ортчиз', 'Leak detected')
                      : I18n.t('Протечек не обнаружено', 'Ву ӧвӧл',
                          'No leak detected'))
                  : (device.isOn
                      ? I18n.t('Обнаружено движение', 'Кошкон вань',
                          'Motion detected')
                      : I18n.t('Движение не обнаружено', 'Кошкон ӧвӧл',
                          'No motion detected')),
              active: device.isOn,
            )
          else if (isEnvironment)
            _SensorStatusTile(
              icon: Icons.cloud_sync_outlined,
              label: I18n.t('Источник данных', 'Дата источник', 'Data source'),
              title:
                  I18n.t('Home Assistant', 'Home Assistant', 'Home Assistant'),
              active: true,
            )
          else if (isLight)
            OutlinedButton.icon(
              onPressed: openSchedule,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(I18n.t('Настроить расписание', 'Расписание келяны',
                  'Configure schedule')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: _accent,
              ),
            ),
        ],
      ),
    );
  }
}

class RoomAtlasImage extends StatelessWidget {
  const RoomAtlasImage({super.key, required this.index, this.roomName});
  final int index;
  final String? roomName;

  static const images = [
    'assets/images/room_living.jpg',
    'assets/images/room_kitchen.jpg',
    'assets/images/room_bedroom.jpg',
    'assets/images/room_bathroom.jpg',
    'assets/images/room_office.jpg',
    'assets/images/room_hallway.jpg',
  ];

  int get imageIndex {
    final name = roomName?.toLowerCase() ?? '';
    if (name.contains('гост') || name.contains('living')) return 0;
    if (name.contains('кух') || name.contains('kitchen')) return 1;
    if (name.contains('спаль') || name.contains('bedroom')) return 2;
    if (name.contains('ван') || name.contains('bath')) return 3;
    if (name.contains('кабин') || name.contains('office')) return 4;
    if (name.contains('корид') ||
        name.contains('прихож') ||
        name.contains('hall')) {
      return 5;
    }
    return index % images.length;
  }

  @override
  Widget build(BuildContext context) => Image.asset(
        images[imageIndex],
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFF141A20)),
      );
}

class _AddDeviceSheet extends StatefulWidget {
  const _AddDeviceSheet();
  @override
  State<_AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends State<_AddDeviceSheet> {
  final controller = TextEditingController(text: 'Smart Light');
  String type = 'light';
  static final types = [
    ('light', 'Лампа'),
    ('rgb_light', 'RGB лампочка'),
    ('rgb_strip', 'RGB подсветка'),
    ('temperature_humidity_sensor', 'Температура и влажность'),
    ('socket', 'Умная розетка'),
    ('leak_sensor', 'Датчик протечки'),
    ('motion_sensor', 'Датчик движения'),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Theme.of(context).dividerColor,
                              borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 20),
                  Text(
                      I18n.t('Добавить устройство', 'Устройство ватсаны',
                          'Add device'),
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  TextField(
                      controller: controller,
                      decoration: InputDecoration(
                          labelText: I18n.t('Название', 'Ним', 'Name'))),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: types.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.35,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (_, index) {
                      final item = types[index];
                      final selected = type == item.$1;
                      final asset = DeviceAssetCatalog.forType(item.$1) ??
                          DeviceAssetCatalog.hub;
                      return InkWell(
                        onTap: () => setState(() {
                          type = item.$1;
                          controller.text = item.$2;
                        }),
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? _accent
                                  : Theme.of(context).dividerColor,
                              width: selected ? 2 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: _accent.withValues(alpha: .22),
                                      blurRadius: 14,
                                    )
                                  ]
                                : null,
                          ),
                          child: Stack(children: [
                            Positioned(
                              left: 12,
                              right: 12,
                              top: 7,
                              height: 78,
                              child: Image.asset(
                                asset,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            ),
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 10,
                              child: Text(
                                item.$2,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (selected)
                              const Positioned(
                                right: 8,
                                top: 8,
                                child: Icon(Icons.check_circle_rounded,
                                    color: _accent, size: 20),
                              ),
                          ]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        Navigator.pop(context, (controller.text.trim(), type));
                      }
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(I18n.t('Добавить', 'Ватсаны', 'Add')),
                  ),
                ]),
          ),
        ),
      );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onTap,
    required this.onDelete,
  });
  final LocalRoomDevice device;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  IconData get icon => switch (device.type) {
        'light' => MdiIcons.lightbulbOutline,
        'rgb_light' => MdiIcons.lightbulbOnOutline,
        'rgb_strip' => MdiIcons.ledStripVariant,
        'temperature_humidity_sensor' => MdiIcons.thermometerWater,
        'leak_sensor' => MdiIcons.waterAlertOutline,
        'motion_sensor' => MdiIcons.motionSensor,
        'thermostat' => MdiIcons.thermostat,
        'socket' => MdiIcons.powerSocketEu,
        _ => MdiIcons.motionSensor,
      };

  @override
  Widget build(BuildContext context) {
    final asset = DeviceAssetCatalog.forType(device.type);
    final isEnvironment = device.type == 'temperature_humidity_sensor';
    final isLeak = device.type == 'leak_sensor';
    final isMotion = device.type == 'motion_sensor';
    final status = isEnvironment
        ? '${device.temperature.toStringAsFixed(1)}°C · ${device.humidity.round()}%'
        : isLeak
            ? (device.isOn ? 'Обнаружена протечка' : 'Протечки нет')
            : isMotion
                ? (device.isOn ? 'Есть движение' : 'Движения нет')
                : device.isOn
                    ? I18n.t('Включено', 'Кутэмын', 'On')
                    : I18n.t('Выключено', 'Куштэмын', 'Off');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(context, active: device.isOn),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (asset != null)
              SizedBox(
                height: 100,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  ),
                ),
              )
            else
              Icon(icon, color: device.isOn ? Colors.white : _accent),
            const Spacer(),
            Text(device.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: device.isOn
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: device.isOn
                        ? Colors.white70
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10)),
          ]),
          Positioned(
            right: -8,
            top: -8,
            child: PopupMenuButton<String>(
              tooltip: I18n.t('Действия', 'Лэсьтонъёс', 'Actions'),
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Text(I18n.t('Удалить', 'Быдтыны', 'Delete')),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _AddDeviceCard extends StatelessWidget {
  const _AddDeviceCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: _cardDecoration(context),
          child: const Center(
              child: Icon(Icons.add_rounded, color: _accent, size: 32)),
        ),
      );
}

class _SensorValueCard extends StatelessWidget {
  const _SensorValueCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _accent),
          const SizedBox(height: 14),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11)),
        ]),
      );
}

class _SensorStatusTile extends StatelessWidget {
  const _SensorStatusTile({
    required this.icon,
    required this.label,
    required this.title,
    required this.active,
  });
  final IconData icon;
  final String label;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (active ? _accent : Colors.white54).withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: active ? _accent : Colors.white54),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10)),
              const SizedBox(height: 3),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: active ? _accent : Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
        ]),
      );
}

class _LightModeTabs extends StatelessWidget {
  const _LightModeTabs({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('cool', Icons.ac_unit_rounded, I18n.t('Холодный', 'Кезьыт', 'Cool')),
      (
        'neutral',
        Icons.light_mode_outlined,
        I18n.t('Нейтральный', 'Шӧр', 'Neutral')
      ),
      (
        'warm',
        Icons.local_fire_department_outlined,
        I18n.t('Тёплый', 'Шуныт', 'Warm')
      ),
    ];
    return Container(
      height: 70,
      padding: const EdgeInsets.all(7),
      decoration: _cardDecoration(context),
      child: Row(
        children: items.map((item) {
          final selected = value == item.$1;
          return Expanded(
            flex: selected ? 12 : 10,
            child: AnimatedScale(
              scale: selected ? 1.04 : 1,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: InkWell(
                onTap: () => onChanged(item.$1),
                borderRadius: BorderRadius.circular(17),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white24 : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                    border: selected
                        ? Border.all(color: Colors.white30, width: 1.3)
                        : Border.all(color: Colors.transparent),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: Offset(0, 4))
                          ]
                        : null,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.$2, size: selected ? 22 : 20),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: selected ? 14 : 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ),
                      ]),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.device, required this.onChanged});
  final LocalRoomDevice device;
  final Future<void> Function(LocalRoomDevice) onChanged;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late LocalRoomDevice device = widget.device;

  Future<void> save(List<DeviceSchedule> schedules) async {
    final next = device.copyWith(schedules: schedules);
    setState(() => device = next);
    await widget.onChanged(next);
  }

  Future<void> edit([DeviceSchedule? existing]) async {
    final result = await showModalBottomSheet<DeviceSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleEditor(schedule: existing),
    );
    if (result == null) return;
    final schedules = [...device.schedules];
    final index = schedules.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      schedules.add(result);
    } else {
      schedules[index] = result;
    }
    await save(schedules);
  }

  String daysLabel(List<int> days) {
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    if (days.length == 7) return 'Каждый день';
    return days.map((day) => names[day.clamp(0, 6)]).join(', ');
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, 20 + MediaQuery.paddingOf(context).bottom),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: Text(I18n.t('Расписание', 'Расписание', 'Schedule'),
                    style: Theme.of(context).textTheme.headlineSmall)),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 14),
          if (device.schedules.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: _cardDecoration(context),
              child: Column(children: [
                const Icon(Icons.schedule_outlined, color: _accent, size: 32),
                const SizedBox(height: 10),
                Text(I18n.t(
                    'Таймеров пока нет', 'Таймеръёс ӧвӧл', 'No timers yet')),
                const SizedBox(height: 5),
                Text(
                  I18n.t('Добавьте дни и время работы устройства.',
                      'Нунал но вакыт ватса.', 'Add days and operating times.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12),
                ),
              ]),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: device.schedules.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (_, index) {
                  final schedule = device.schedules[index];
                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    decoration: _cardDecoration(context),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(daysLabel(schedule.days),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 5),
                            Text('${schedule.onTime}  —  ${schedule.offTime}',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ])),
                      Switch.adaptive(
                        value: schedule.enabled,
                        onChanged: (value) {
                          final list = [...device.schedules];
                          list[index] = schedule.copyWith(enabled: value);
                          save(list);
                        },
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') edit(schedule);
                          if (value == 'delete') {
                            save([...device.schedules]..removeAt(index));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'edit', child: Text('Изменить')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Удалить')),
                        ],
                      ),
                    ]),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: edit,
            icon: const Icon(Icons.add_rounded),
            label:
                Text(I18n.t('Добавить таймер', 'Таймер ватсаны', 'Add timer')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: _accent,
            ),
          ),
        ]),
      );
}

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({this.schedule});
  final DeviceSchedule? schedule;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late final Set<int> days = {...?widget.schedule?.days};
  late String onTime = widget.schedule?.onTime ?? '08:00';
  late String offTime = widget.schedule?.offTime ?? '09:00';

  Future<String?> pick(String current) async {
    final parts = current.split(':');
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (value == null) return null;
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(I18n.t('Новый таймер', 'Выль таймер', 'New timer'),
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(names.length, (index) {
            final selected = days.contains(index);
            return InkWell(
              onTap: () => setState(
                  () => selected ? days.remove(index) : days.add(index)),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _accent : Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Text(names[index],
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            );
          }),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
              child: _TimePickerCard(
            label: I18n.t('Включить', 'Кутыны', 'Turn on'),
            value: onTime,
            onTap: () async {
              final value = await pick(onTime);
              if (value != null) setState(() => onTime = value);
            },
          )),
          const SizedBox(width: 10),
          Expanded(
              child: _TimePickerCard(
            label: I18n.t('Выключить', 'Куштыны', 'Turn off'),
            value: offTime,
            onTap: () async {
              final value = await pick(offTime);
              if (value != null) setState(() => offTime = value);
            },
          )),
        ]),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: days.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    DeviceSchedule(
                      id: widget.schedule?.id ??
                          'schedule_${DateTime.now().microsecondsSinceEpoch}',
                      days: days.toList()..sort(),
                      onTime: onTime,
                      offTime: offTime,
                      enabled: widget.schedule?.enabled ?? true,
                    ),
                  ),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52), backgroundColor: _accent),
          child: Text(I18n.t('Сохранить', 'Утчаны', 'Save')),
        ),
      ]),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  const _TimePickerCard(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: _cardDecoration(context),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11)),
            const SizedBox(height: 5),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(7),
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          child: IconButton(
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white, size: 18)),
        ),
      );
}

BoxDecoration _cardDecoration(BuildContext context, {bool active = false}) =>
    BoxDecoration(
      gradient: active
          ? const LinearGradient(colors: [Color(0xFFFFA02F), _accent])
          : null,
      color: active ? null : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: active
              ? const Color(0xFFFF8A2A)
              : Theme.of(context).dividerColor),
      boxShadow: active
          ? [BoxShadow(color: _accent.withValues(alpha: .25), blurRadius: 20)]
          : null,
    );

String _deviceWord(int count) {
  if (count % 10 == 1 && count % 100 != 11) return 'устройство';
  if (count % 10 >= 2 &&
      count % 10 <= 4 &&
      (count % 100 < 12 || count % 100 > 14)) {
    return 'устройства';
  }
  return 'устройств';
}
