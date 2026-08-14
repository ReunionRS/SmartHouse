import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../core/i18n.dart';
import '../core/room_localization.dart';
import '../models/session_models.dart';
import '../models/home_assistant_room.dart';
import '../models/local_room_device.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import '../features/settings/profile_page.dart';
import '../features/assistant/ai_chat_page.dart';
import '../features/notifications/smart_notifications_page.dart';
import '../features/rooms/room_detail_page.dart';
import '../features/scenes/scenes_page.dart';
import '../ui/app_routes.dart';
import '../ui/device_asset_catalog.dart';

const _orange = Color(0xFFFF7A18);
const _orangeSoft = Color(0xFFFF8A2A);
const _cream = Color(0xFFFFF7EF);
const _muted = Color(0xFFA99D93);

Color _foreground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? _cream
        : const Color(0xFF191C22);
Color _secondary(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? _muted
        : const Color(0xFF6E737C);

class SmartHomeShell extends StatefulWidget {
  const SmartHomeShell({
    super.key,
    required this.auth,
    required this.session,
    required this.onLogout,
    required this.onReconnectHub,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });
  final AuthService auth;
  final AppSession session;
  final Future<void> Function() onLogout;
  final Future<void> Function() onReconnectHub;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) onThemeModeChanged;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  State<SmartHomeShell> createState() => _SmartHomeShellState();
}

class _SmartHomeShellState extends State<SmartHomeShell> {
  int index = 0;
  int tabSlideDirection = 1;
  late String userFio = widget.session.fio;
  String? error;
  List<HomeAssistantRoom> rooms = const [];
  List<LocalRoomDevice> localDevices = const [];
  bool initialHomeLoading = true;
  final RoomService roomService = RoomService();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await Future.wait([loadEntities(), loadRoomsAndDevices()]);
  }

  void openAiAssistant() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.42),
      builder: (_) => const AiChatSheet(),
    );
  }

  Future<void> loadEntities() async {
    try {
      await widget.auth.fetchSystemStatus();
      if (mounted) {
        setState(() {
          error = null;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> loadRoomsAndDevices() async {
    try {
      final values = await Future.wait([
        roomService.load(widget.session.id),
        roomService.loadDevices(widget.session.id),
      ]);
      if (mounted) {
        setState(() {
          rooms = values[0] as List<HomeAssistantRoom>;
          localDevices = values[1] as List<LocalRoomDevice>;
          initialHomeLoading = false;
        });
      }
    } finally {
      if (mounted && initialHomeLoading) {
        setState(() => initialHomeLoading = false);
      }
    }
  }

  Future<void> openCreateRoom() async {
    final created = await showModalBottomSheet<HomeAssistantRoom>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateRoomSheet(
        onReconnectHub: widget.onReconnectHub,
        onCreate: (name, icon, roomType) => roomService.create(
          userId: widget.session.id,
          name: name,
          icon: icon,
          roomType: roomType,
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() {
        rooms = [
          ...rooms.where((room) => room.areaId != created.areaId),
          created,
        ];
        index = 1;
      });
      loadRoomsAndDevices();
    }
  }

  Future<void> openRoom(HomeAssistantRoom room, int roomIndex) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RoomDetailPage(
        room: room,
        roomIndex: roomIndex,
        userId: widget.session.id,
        service: roomService,
      ),
    ));
    await loadRoomsAndDevices();
  }

  void openNotifications() => Navigator.of(context).push(
        slideUpRoute(const SmartNotificationsPage()),
      );

  Future<void> editFavorites() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FavoritePickerSheet(
        devices: localDevices,
        rooms: rooms,
        selectedIds: localDevices
            .where((device) => device.isFavorite)
            .map((device) => device.id)
            .toSet(),
      ),
    );
    if (selected == null) return;
    setState(() {
      localDevices = [
        for (final device in localDevices)
          device.copyWith(isFavorite: selected.contains(device.id)),
      ];
    });
    await roomService.setFavoriteDevices(widget.session.id, selected);
  }

  Future<void> deleteRoom(HomeAssistantRoom room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            I18n.t('Удалить комнату?', 'Комнатаез быдтыны?', 'Delete room?')),
        content: Text(I18n.t(
          'Комната «${localizedRoomName(room)}» и добавленные в неё устройства будут удалены.',
          '«${localizedRoomName(room)}» комната но соын устройствaос быдтозы.',
          'The room “${localizedRoomName(room)}” and its devices will be deleted.',
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
    final previousRooms = rooms;
    final previousDevices = localDevices;
    setState(() {
      rooms = rooms.where((item) => item.areaId != room.areaId).toList();
      localDevices =
          localDevices.where((device) => device.roomId != room.areaId).toList();
    });
    try {
      await roomService.delete(widget.session.id, room.areaId);
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        rooms = previousRooms;
        localDevices = previousDevices;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(exception.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      _HomePage(
          session: AppSession(
            id: widget.session.id,
            token: widget.session.token,
            email: widget.session.email,
            fio: userFio,
            avatarUrl: widget.session.avatarUrl,
          ),
          localDevices: localDevices,
          rooms: rooms,
          error: error,
          onRefresh: load,
          onAddRoom: openCreateRoom,
          onOpenRoom: openRoom,
          onOpenRooms: () => setState(() => index = 1),
          onOpenEvents: openNotifications,
          onEditFavorites: editFavorites),
      _RoomsPage(
          rooms: rooms,
          onAddRoom: openCreateRoom,
          onOpenRoom: openRoom,
          onDeleteRoom: deleteRoom,
          onRefresh: load),
      ScenesPage(
        userId: widget.session.id,
        devices: localDevices,
        rooms: rooms,
        onDevicesChanged: loadRoomsAndDevices,
      ),
      _EmptyPage(
          title: I18n.t('События', 'Луэмъёс', 'Events'),
          text: I18n.t(
              'Здесь появятся важные уведомления и история дома.',
              'Татын кулэ иворъёс но корка историез потоз.',
              'Important notifications and home history will appear here.'),
          icon: Icons.notifications_none_rounded),
      ProfilePage(
        session: AppSession(
          id: widget.session.id,
          token: widget.session.token,
          email: widget.session.email,
          fio: userFio,
          avatarUrl: widget.session.avatarUrl,
        ),
        auth: widget.auth,
        isDarkMode: widget.isDarkMode,
        onToggleTheme: widget.onToggleTheme,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
        onLogout: widget.onLogout,
        onReconnectHub: widget.onReconnectHub,
        onNameChanged: (value) => setState(() => userFio = value),
      ),
    ];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset(
            dark
                ? 'assets/images/backgrounds/smart_home_interior.jpg'
                : 'assets/images/rooms/room_living_light.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            opacity: AlwaysStoppedAnimation(dark ? 1 : .10),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [
                        Color(0xB3141922),
                        Color(0xD90A1118),
                        Color(0xF2051119),
                      ]
                    : const [
                        Color(0xEFFFFFFF),
                        Color(0xF5F7F8FA),
                        Color(0xFFF6F8FB),
                      ],
                stops: const [0, .48, 1],
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              transitionBuilder: (child, animation) {
                final childIndex = (child.key as ValueKey<int>).value;
                final isIncoming = childIndex == index;
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(
                      isIncoming
                          ? tabSlideDirection.toDouble()
                          : -tabSlideDirection.toDouble(),
                      0,
                    ),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                );
              },
              child: KeyedSubtree(key: ValueKey(index), child: pages[index])),
        ),
        if (initialHomeLoading && index <= 2)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.7,
                      color: _orange,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    I18n.t('Синхронизация с хабом…', 'Хабен ӵош синхронизация…',
                        'Syncing with hub…'),
                    style: TextStyle(
                      color: _secondary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
      bottomNavigationBar: _GlassDock(
        index: index,
        onChanged: (value) => setState(() {
          tabSlideDirection = value > index ? 1 : -1;
          index = value;
        }),
        onAssistant: openAiAssistant,
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage(
      {required this.session,
      required this.localDevices,
      required this.rooms,
      required this.error,
      required this.onRefresh,
      required this.onAddRoom,
      required this.onOpenRoom,
      required this.onOpenRooms,
      required this.onOpenEvents,
      required this.onEditFavorites});
  final AppSession session;
  final List<LocalRoomDevice> localDevices;
  final List<HomeAssistantRoom> rooms;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddRoom;
  final void Function(HomeAssistantRoom room, int index) onOpenRoom;
  final VoidCallback onOpenRooms;
  final VoidCallback onOpenEvents;
  final VoidCallback onEditFavorites;

  String get firstName {
    final parts = session.fio.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'друг';
    if (parts.length >= 2) return parts[1];
    return parts.first;
  }

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return I18n.t('Доброе утро', 'Бур ӵукна', 'Good morning');
    }
    if (hour >= 12 && hour < 18) {
      return I18n.t('Добрый день', 'Бур нунал', 'Good afternoon');
    }
    if (hour >= 18 && hour < 23) {
      return I18n.t('Добрый вечер', 'Бур ӝыт', 'Good evening');
    }
    return I18n.t('Доброй ночи', 'Бур уй', 'Good night');
  }

  @override
  Widget build(BuildContext context) {
    final favoriteDevices =
        localDevices.where((device) => device.isFavorite).toList();
    return RefreshIndicator(
      color: _orange,
      onRefresh: onRefresh,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 62, 20, 120),
          children: [
            Row(children: [
              const Spacer(),
              _IconButton(
                  icon: Icons.notifications_none_rounded, onTap: onOpenEvents),
            ]),
            const SizedBox(height: 18),
            const Text('SMART HOUSE', style: _kicker),
            const SizedBox(height: 7),
            Text('$greeting, $firstName',
                style: TextStyle(
                    color: _foreground(context),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.1)),
            const SizedBox(height: 4),
            Text(
                error == null
                    ? I18n.t('В доме всё в порядке', 'Коркаын ваньмыз умой',
                        'Everything is fine at home')
                    : I18n.t(
                        'Устройства пока не подключены',
                        'Устройстваос уг герӟаськы',
                        'Devices are not connected yet'),
                style: TextStyle(color: _secondary(context), fontSize: 13)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: _SectionTitle(
                    I18n.t('Избранное', 'Быръемъёс', 'Favorites')),
              ),
              TextButton(
                onPressed: onEditFavorites,
                child: Text(favoriteDevices.isEmpty
                    ? I18n.t('Добавить', 'Ватсаны', 'Add')
                    : I18n.t('Изменить', 'Воштыны', 'Edit')),
              ),
            ]),
            if (favoriteDevices.isEmpty)
              _AddFavoriteCard(onTap: onEditFavorites)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: favoriteDevices.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 142,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (_, i) {
                  final roomIndex = rooms.indexWhere(
                      (room) => room.areaId == favoriteDevices[i].roomId);
                  return _LocalDeviceCard(
                    device: favoriteDevices[i],
                    roomName: roomIndex >= 0 ? rooms[roomIndex].name : '',
                    onTap: () {
                      if (roomIndex >= 0) {
                        onOpenRoom(rooms[roomIndex], roomIndex);
                      }
                    },
                  );
                },
              ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: rooms.isEmpty ? null : onOpenRooms,
              child: _SectionTitle(I18n.t('Комнаты', 'Комнатъёс', 'Rooms')),
            ),
            if (rooms.isEmpty)
              _RoomsEmptyState(onAdd: onAddRoom)
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rooms.take(6).length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 128,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                ),
                itemBuilder: (_, i) => _RoomCard(
                  room: rooms[i],
                  roomIndex: i,
                  compact: true,
                  onTap: () => onOpenRoom(rooms[i], i),
                ),
              ),
          ]),
    );
  }
}

class _RoomsPage extends StatelessWidget {
  const _RoomsPage({
    required this.rooms,
    required this.onAddRoom,
    required this.onOpenRoom,
    required this.onDeleteRoom,
    required this.onRefresh,
  });
  final List<HomeAssistantRoom> rooms;
  final VoidCallback onAddRoom;
  final void Function(HomeAssistantRoom room, int index) onOpenRoom;
  final ValueChanged<HomeAssistantRoom> onDeleteRoom;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: _orange,
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 72, 20, 120),
          children: [
            const Text('SMART HOUSE', style: _kicker),
            const SizedBox(height: 9),
            Text(I18n.t('Комнаты', 'Комнатъёс', 'Rooms'),
                style: _pageTitle(context)),
            const SizedBox(height: 9),
            Text(
                I18n.t('Комнаты вашего дома', 'Коркась комнатъёс',
                    'Rooms in your home'),
                style: TextStyle(color: _secondary(context))),
            const SizedBox(height: 22),
            if (rooms.isEmpty)
              _RoomsEmptyState(onAdd: onAddRoom)
            else ...[
              ...rooms.indexed.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RoomCard(
                      room: entry.$2,
                      roomIndex: entry.$1,
                      onTap: () => onOpenRoom(entry.$2, entry.$1),
                      onDelete: () => onDeleteRoom(entry.$2),
                    ),
                  )),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: onAddRoom,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить комнату'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _orangeSoft,
                  side: BorderSide(color: _orange.withOpacity(.45)),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ],
          ],
        ),
      );
}

class _AddFavoriteCard extends StatelessWidget {
  const _AddFavoriteCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(.16)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
            const SizedBox(width: 16),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _orange.withOpacity(.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: _orangeSoft),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    I18n.t('Добавить устройство', 'Устройство ватсаны',
                        'Add device'),
                    style: TextStyle(
                      color: _foreground(context),
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text(
                  I18n.t('Выберите из добавленных', 'Ватэмъёсысь быръе',
                      'Choose from your devices'),
                  style: TextStyle(color: _secondary(context), fontSize: 11),
                ),
              ],
            ),
          ]),
        ),
      );
}

class _LocalDeviceCard extends StatelessWidget {
  const _LocalDeviceCard({
    required this.device,
    required this.roomName,
    required this.onTap,
  });
  final LocalRoomDevice device;
  final String roomName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final asset = DeviceAssetCatalog.forType(device.type);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF29313C), Color(0xFF121820)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(.14)),
        ),
        child: Stack(children: [
          if (asset != null)
            Positioned(
              left: 18,
              right: 18,
              top: 5,
              height: 82,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
          Positioned(
            left: 12,
            right: 10,
            bottom: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    )),
                Text(
                  roomName.isEmpty
                      ? I18n.t('Комната не указана', 'Комната ӧвӧл',
                          'Room not specified')
                      : roomName,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _FavoritePickerSheet extends StatefulWidget {
  const _FavoritePickerSheet({
    required this.devices,
    required this.rooms,
    required this.selectedIds,
  });
  final List<LocalRoomDevice> devices;
  final List<HomeAssistantRoom> rooms;
  final Set<String> selectedIds;

  @override
  State<_FavoritePickerSheet> createState() => _FavoritePickerSheetState();
}

class _FavoritePickerSheetState extends State<_FavoritePickerSheet> {
  late final Set<String> selected = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xF2171D26)
              : Colors.white.withOpacity(.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: Text(
                I18n.t('Избранные устройства', 'Быръем устройстваос',
                    'Favorite devices'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(I18n.t('Готово', 'Дась', 'Done')),
            ),
          ]),
          const SizedBox(height: 8),
          if (widget.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34),
              child: Text(
                I18n.t(
                  'Сначала добавьте устройство в одной из комнат.',
                  'Азьло устройствоез комнатае ватсаны кулэ.',
                  'Add a device to a room first.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final device = widget.devices[index];
                  final checked = selected.contains(device.id);
                  final roomIndex = widget.rooms
                      .indexWhere((room) => room.areaId == device.roomId);
                  final roomName = roomIndex >= 0
                      ? widget.rooms[roomIndex].name
                      : I18n.t('Комната не указана', 'Комната ӧвӧл',
                          'Room not specified');
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(.04)
                          : const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: CheckboxListTile(
                      value: checked,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          selected.add(device.id);
                        } else {
                          selected.remove(device.id);
                        }
                      }),
                      activeColor: _orange,
                      secondary: SizedBox(
                        width: 44,
                        height: 44,
                        child: Image.asset(
                          DeviceAssetCatalog.forType(device.type) ??
                              DeviceAssetCatalog.hub,
                          fit: BoxFit.contain,
                        ),
                      ),
                      title: Text(device.name,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        roomName,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      );
}

class _RoomsEmptyState extends StatelessWidget {
  const _RoomsEmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => _Glass(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _orange.withOpacity(.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.meeting_room_outlined,
                  color: _orangeSoft, size: 26),
            ),
            const SizedBox(height: 14),
            Text(I18n.t('Комнат пока нет', 'Комнатъёс ӧвӧл', 'No rooms yet'),
                style: TextStyle(
                    color: _foreground(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              I18n.t(
                  'Создайте первую комнату. Устройства можно будет добавить позже.',
                  'Одӥгетӥ комнатаез лэсьты. Устройстваосты бере ватсаны луоз.',
                  'Create your first room. You can add devices later.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _secondary(context), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                  I18n.t('Создать комнату', 'Комната лэсьтыны', 'Create room')),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ]),
        ),
      );
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.roomIndex,
    required this.onTap,
    this.compact = false,
    this.onDelete,
  });
  final HomeAssistantRoom room;
  final int roomIndex;
  final VoidCallback onTap;
  final bool compact;
  final VoidCallback? onDelete;

  IconData get roomIcon {
    final value = room.icon.toLowerCase();
    if (value.contains('bed')) return Icons.bed_outlined;
    if (value.contains('kitchen') || value.contains('silverware')) {
      return Icons.kitchen_outlined;
    }
    if (value.contains('bath') || value.contains('shower')) {
      return Icons.shower_outlined;
    }
    if (value.contains('sofa') || value.contains('living')) {
      return Icons.weekend_outlined;
    }
    if (value.contains('garage')) return Icons.garage_outlined;
    return Icons.meeting_room_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        height: compact ? 128 : 176,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 12, offset: Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(fit: StackFit.expand, children: [
            RoomAtlasImage(
                index: roomIndex,
                roomName: localizedRoomName(room),
                roomIcon: room.icon,
                roomType: room.roomType),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black12, Colors.transparent, Colors.black87],
                  stops: [0, .42, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(roomIcon, color: Colors.white, size: 17),
              ),
            ),
            if (onDelete != null)
              Positioned(
                right: 7,
                top: 7,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: PopupMenuButton<String>(
                    tooltip: I18n.t('Действия', 'Лэсьтонъёс', 'Actions'),
                    icon: const Icon(Icons.more_vert_rounded,
                        color: Colors.white, size: 18),
                    onSelected: (value) {
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent),
                          const SizedBox(width: 10),
                          Text(I18n.t('Удалить комнату', 'Комнатаез быдтыны',
                              'Delete room')),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 8,
              bottom: 8,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(localizedRoomName(room),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
                Container(
                  width: 27,
                  height: 27,
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 19),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet({
    required this.onCreate,
    required this.onReconnectHub,
  });
  final Future<HomeAssistantRoom> Function(
      String name, String icon, String roomType) onCreate;
  final Future<void> Function() onReconnectHub;

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  String icon = 'mdi:sofa-outline';
  bool saving = false;
  String? error;

  Map<String, (String, String)> get icons => {
        'mdi:sofa-outline': (
          'assets/images/rooms/room_living.jpg',
          I18n.t('Гостиная', 'Куно комната', 'Living room', tt: 'Кунак бүлмәсе')
        ),
        'mdi:bed-outline': (
          'assets/images/rooms/room_bedroom.jpg',
          I18n.t('Спальня', 'Узон комната', 'Bedroom', tt: 'Йокы бүлмәсе')
        ),
        'mdi:silverware-fork-knife': (
          'assets/images/rooms/room_dining.png',
          I18n.t('Кухня', 'Кухня', 'Kitchen', tt: 'Аш бүлмәсе')
        ),
        'mdi:shower': (
          'assets/images/rooms/room_bathroom.jpg',
          I18n.t('Ванная', 'Миськон комната', 'Bathroom', tt: 'Юыну бүлмәсе')
        ),
        'mdi:desk': (
          'assets/images/rooms/room_office.jpg',
          I18n.t('Кабинет', 'Уж комната', 'Office', tt: 'Эш бүлмәсе')
        ),
        'mdi:garage': (
          'assets/images/rooms/room_hallway.jpg',
          I18n.t('Гараж', 'Гараж', 'Garage', tt: 'Гараж')
        ),
        'mdi:table-chair': (
          'assets/images/rooms/room_kitchen.jpg',
          I18n.t('Столовая', 'Сиён комната', 'Dining room', tt: 'Аш бүлмәсе')
        ),
        'mdi:baby-face-outline': (
          'assets/images/rooms/room_kids.png',
          I18n.t('Детская', 'Пиналъёс комната', 'Kids room',
              tt: 'Балалар бүлмәсе')
        ),
        'mdi:door-open': (
          'assets/images/rooms/room_entryway.png',
          I18n.t('Прихожая', 'Азьпал', 'Entryway', tt: 'Керү бүлмәсе')
        ),
        'mdi:stairs': (
          'assets/images/rooms/room_corridor.png',
          I18n.t('Коридор', 'Коридор', 'Hallway', tt: 'Коридор')
        ),
        'mdi:washing-machine': (
          'assets/images/rooms/room_laundry.png',
          I18n.t('Прачечная', 'Миськонни', 'Laundry room', tt: 'Кер юу бүлмәсе')
        ),
        'mdi:food-apple-outline': (
          'assets/images/rooms/room_pantry.png',
          I18n.t('Кладовая', 'Келәт', 'Pantry', tt: 'Келәт')
        ),
        'mdi:balcony': (
          'assets/images/rooms/room_balcony.png',
          I18n.t('Балкон', 'Балкон', 'Balcony', tt: 'Балкон')
        ),
        'mdi:flower-outline': (
          'assets/images/rooms/room_terrace.png',
          I18n.t('Терраса', 'Терраса', 'Terrace', tt: 'Терраса')
        ),
        'mdi:greenhouse': (
          'assets/images/rooms/room_garden.png',
          I18n.t('Сад', 'Бакча', 'Garden', tt: 'Бакча')
        ),
        'mdi:home-floor-negative-1': (
          'assets/images/rooms/room_basement.png',
          I18n.t('Подвал', 'Улынъёс', 'Basement', tt: 'Подвал')
        ),
        'mdi:tools': (
          'assets/images/rooms/room_workshop.png',
          I18n.t('Мастерская', 'Ужъянни', 'Workshop', tt: 'Остаханә')
        ),
      };

  Future<void> save() async {
    final name = icons[icon]!.$2;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final room = await widget.onCreate(name, icon, roomTypeForIcon(icon));
      if (mounted) Navigator.of(context).pop(room);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(shrinkWrap: true, children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 22),
          Text(I18n.t('Новая комната', 'Выль комната', 'New room'),
              style: _pageTitle(context)),
          const SizedBox(height: 7),
          Text(
              I18n.t(
                  'Вы сможете добавить устройства позже.',
                  'Устройстваосты бере ватсаны луоз.',
                  'You can add devices later.'),
              style: TextStyle(color: _secondary(context), fontSize: 12)),
          const SizedBox(height: 18),
          Text(I18n.t('Тип комнаты', 'Комната тип', 'Room type'),
              style: TextStyle(
                  color: _foreground(context), fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.75,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: icons.entries.map((entry) {
              final active = icon == entry.key;
              final imagePath = Theme.of(context).brightness == Brightness.dark
                  ? entry.value.$1
                  : entry.value.$1.endsWith('.jpg')
                      ? entry.value.$1.replaceFirst('.jpg', '_light.png')
                      : entry.value.$1.replaceFirst('.png', '_light.png');
              return InkWell(
                onTap: () => setState(() => icon = entry.key),
                borderRadius: BorderRadius.circular(18),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color:
                          active ? _orangeSoft : Theme.of(context).dividerColor,
                      width: active ? 2 : 1,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: _orange.withOpacity(.28),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      Image.asset(imagePath, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black12, Colors.black87],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 34,
                        bottom: 10,
                        child: Text(
                          entry.value.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (active)
                        Positioned(
                          right: 9,
                          top: 9,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: _orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 15),
                          ),
                        ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE9E7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF8B7E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFB42318), size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFF7A271A),
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await widget.onReconnectHub();
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(I18n.t(
                      'Переподключить хаб',
                      'Хабез выль подключить',
                      'Reconnect hub',
                    )),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              disabledBackgroundColor: _orange.withOpacity(.35),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(I18n.t(
                    'Создать комнату', 'Комната лэсьтыны', 'Create room')),
          ),
        ]),
      ),
    );
  }
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage(
      {required this.title, required this.text, required this.icon});
  final String title, text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _EmptyCard(icon: icon, text: text),
        const SizedBox(height: 20),
        Text(title, style: _pageTitle(context))
      ]));
}

class _GlassDock extends StatelessWidget {
  const _GlassDock({
    required this.index,
    required this.onChanged,
    required this.onAssistant,
  });
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onAssistant;

  @override
  Widget build(BuildContext context) {
    const items = [
      (0, Icons.home_outlined, Icons.home_rounded),
      (1, Icons.meeting_room_outlined, Icons.meeting_room_rounded),
      (2, Icons.bolt_outlined, Icons.bolt_rounded),
      (4, Icons.settings_outlined, Icons.settings_rounded),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_orangeSoft, _orange]),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _orange.withOpacity(.35),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Row(
                children: items.map((item) {
                  final selected = index == item.$1;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => onChanged(item.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withOpacity(.18)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: selected
                              ? Border.all(color: Colors.white30)
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            selected ? item.$3 : item.$2,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 12,
            shadowColor: Colors.black54,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAssistant,
              child: const SizedBox(
                width: 68,
                height: 68,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Image(
                    image: AssetImage('assets/images/icons/ai_assistant.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 25, bottom: 12),
      child: Text(text,
          style: TextStyle(
              color: _foreground(context),
              fontSize: 26,
              fontWeight: FontWeight.w700)));
}

class _OrangeIcon extends StatelessWidget {
  const _OrangeIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
          color: _orange.withOpacity(.14),
          borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, color: _orangeSoft, size: 21));
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _Glass(
      onTap: onTap,
      child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: _foreground(context), size: 20)));
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => _Glass(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            _OrangeIcon(icon),
            const SizedBox(height: 18),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: _secondary(context), height: 1.5))
          ])));
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [
                          Colors.white.withOpacity(.11),
                          Colors.white.withOpacity(.045),
                        ]
                      : [
                          Colors.white.withOpacity(.76),
                          Colors.white.withOpacity(.42),
                        ],
                ),
                border: Border.all(
                  color: dark
                      ? Colors.white.withOpacity(.13)
                      : Colors.white.withOpacity(.88),
                ),
                boxShadow: dark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x160E2945),
                          blurRadius: 22,
                          offset: Offset(0, 8),
                        ),
                      ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

const _kicker = TextStyle(
    color: _orangeSoft,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.8);
TextStyle _pageTitle(BuildContext context) => TextStyle(
      color: _foreground(context),
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.1,
    );
