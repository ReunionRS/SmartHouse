import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_language.dart';
import '../../core/i18n.dart';
import '../../core/ui_tokens.dart';
import '../../models/session_models.dart';
import '../../services/auth_service.dart';
import '../../ui/app_routes.dart';
import 'account_settings_pages.dart';
import '../notifications/smart_notifications_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.session,
    required this.auth,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    required this.onLogout,
    required this.onReconnectHub,
    required this.onOpenDashboardSettings,
    this.onNameChanged,
    this.onAvatarChanged,
  });

  final AppSession session;
  final AuthService auth;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) onThemeModeChanged;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onReconnectHub;
  final VoidCallback onOpenDashboardSettings;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<String>? onAvatarChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late String avatarUrl = widget.session.avatarUrl;

  void _openMyProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyProfilePage(
          session: AppSession(
            id: widget.session.id,
            token: widget.session.token,
            email: widget.session.email,
            fio: widget.session.fio,
            avatarUrl: avatarUrl,
          ),
          auth: widget.auth,
          onNameChanged: widget.onNameChanged,
          onAvatarChanged: (value) {
            setState(() => avatarUrl = value);
            widget.onAvatarChanged?.call(value);
          },
        ),
      ),
    );
  }

  void _openLanguage() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LanguageSettingsPage(
          language: widget.language,
          onChanged: widget.onLanguageChanged,
        ),
      ));

  void _openSecurity() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SecuritySettingsPage(auth: widget.auth),
      ));

  void _openTheme() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ThemeSettingsPage(
          themeMode: widget.themeMode,
          onChanged: widget.onThemeModeChanged,
        ),
      ));

  void _openNotifications() {
    Navigator.of(context).push(
      slideUpRoute(
        const SmartNotificationsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fio = widget.session.fio.isEmpty
        ? I18n.t(
            'Пользователь',
            'Пользователь',
            'User',
            tt: 'Кулланучы',
            ba: 'Ҡулланыусы',
          )
        : widget.session.fio;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 66, 20, 118),
        children: [
          const Text(
            'SMART HOUSE',
            style: TextStyle(
              color: Color(0xFFFF8A2A),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            I18n.t('Настройки', 'Кельтэтъёс', 'Settings'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 22),
          _ProfileTile(
            icon: Icons.person_outline_rounded,
            title: I18n.t('Мой профиль', 'Мон профиль', 'My profile'),
            trailing: fio,
            onTap: _openMyProfile,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.language_rounded,
            title: I18n.t('Язык', 'Кыл', 'Language'),
            trailing: widget.language.ruLabel,
            onTap: _openLanguage,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.palette_outlined,
            title: I18n.t('Тема', 'Тема', 'Theme'),
            trailing: switch (widget.themeMode) {
              ThemeMode.light => I18n.t('Светлая', 'Югыт', 'Light'),
              ThemeMode.dark => I18n.t('Тёмная', 'Пеймыт', 'Dark'),
              ThemeMode.system => I18n.t('Системная', 'Система', 'System'),
            },
            onTap: _openTheme,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            title: I18n.t('Уведомления', 'Иворъёс', 'Notifications'),
            onTap: _openNotifications,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.dashboard_customize_outlined,
            title: I18n.t(
              'Главный экран',
              'Главной экран',
              'Home dashboard',
            ),
            trailing: I18n.t('Настроить', 'Келян', 'Configure'),
            onTap: widget.onOpenDashboardSettings,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.shield_outlined,
            title: I18n.t('Безопасность', 'Утинлык', 'Security'),
            onTap: _openSecurity,
          ),
          const SizedBox(height: 10),
          _ProfileTile(
            icon: Icons.hub_outlined,
            title: I18n.t(
              'Подключение Smart House Hub',
              'Smart House Hub подключение',
              'Smart House Hub connection',
            ),
            trailing: I18n.t('Переподключить', 'Переподключить', 'Reconnect'),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(I18n.t(
                    'Переподключить хаб?',
                    'Хабез выльысь подключить?',
                    'Reconnect the hub?',
                  )),
                  content: Text(I18n.t(
                    'Текущее подключение будет удалено, после чего откроется поиск Smart House Hub.',
                    'Тырмыт подключение быдтэм луоз, собере Smart House Hub утчан усьтӥськоз.',
                    'The current connection will be removed and Smart House Hub discovery will open.',
                  )),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(I18n.t('Отмена', 'Кошкыны', 'Cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(I18n.t(
                        'Переподключить',
                        'Выль подключить',
                        'Reconnect',
                      )),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await widget.onReconnectHub();
            },
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: () async {
              final navigator = Navigator.of(context);
              await widget.onLogout();
              if (!mounted) return;
              navigator.popUntil((route) => route.isFirst);
            },
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout, color: Color(0xFFFF8B8B), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    I18n.t('Выйти из аккаунта', 'Аккаунтысь потыны', 'Log out',
                        tt: 'Аккаунттан чыгу', ba: 'Аккаунттан сығыу'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFF9A9A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({
    super.key,
    required this.session,
    required this.auth,
    this.onNameChanged,
    this.onAvatarChanged,
    this.onFinished,
  });
  final AppSession session;
  final AuthService auth;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<String>? onAvatarChanged;
  final VoidCallback? onFinished;

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  Uint8List? avatarBytes;
  late String avatarUrl = widget.session.avatarUrl;
  late String name = widget.session.fio.trim().isEmpty
      ? I18n.t('Пользователь', 'Пользователь', 'User')
      : widget.session.fio.trim();
  bool picking = false;

  Future<void> pickAvatar() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw Exception('Не удалось прочитать выбранное изображение');
      }
      setState(() => avatarBytes = file.bytes);
      final value = await widget.auth.uploadAvatar(file: file);
      if (value.isEmpty) {
        throw Exception('Сервер не вернул адрес загруженного аватара');
      }
      if (mounted) {
        setState(() => avatarUrl = value);
        widget.onAvatarChanged?.call(value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> editName() async {
    final controller = TextEditingController(text: name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(I18n.t('Изменить имя', 'Нимез воштыны', 'Change name')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: I18n.t('Имя', 'Ним', 'Name')),
        ),
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
    if (value == null || value.trim().length < 2) return;
    try {
      final updated = await widget.auth.updateProfileName(value);
      if (!mounted) return;
      setState(() => name = updated);
      widget.onNameChanged?.call(updated);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (avatarBytes != null) {
      image = MemoryImage(avatarBytes!);
    } else if (avatarUrl.isNotEmpty) {
      image = NetworkImage(widget.auth.resolveFileUrl(avatarUrl));
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: widget.onFinished == null,
        title: Text(
            widget.onFinished == null ? 'Мой профиль' : 'Настройка профиля'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: pickAvatar,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF8A2A), Color(0xFF9A4310)]),
                    borderRadius: BorderRadius.circular(34),
                    image: image == null
                        ? null
                        : DecorationImage(image: image, fit: BoxFit.cover),
                  ),
                  alignment: Alignment.center,
                  child: image == null
                      ? Text(name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w800))
                      : null,
                ),
                Positioned(
                  right: -7,
                  bottom: -7,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF7A18), shape: BoxShape.circle),
                    child: picking
                        ? const Padding(
                            padding: EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.camera_alt_outlined,
                            color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 30),
          _ProfileInfoCard(
            label: I18n.t('Имя', 'Ним', 'Name'),
            value: name,
            onTap: editName,
            trailing: Icons.edit_outlined,
          ),
          const SizedBox(height: 10),
          _ProfileInfoCard(label: 'Email', value: widget.session.email),
          const SizedBox(height: 16),
          const Text(
            'Нажмите на фотографию, чтобы изменить её.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFA99D93), fontSize: 11),
          ),
          if (widget.onFinished != null) ...[
            const SizedBox(height: 28),
            FilledButton(
              onPressed: picking ? null : widget.onFinished,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Продолжить'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 11)),
                    const SizedBox(height: 6),
                    Text(value,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
            if (trailing != null)
              Icon(trailing, color: const Color(0xFFFF7A18)),
          ]),
        ),
      );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A18).withOpacity(.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFFFF8A2A), size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  color: Color(0xFFFF8A2A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0xFFA99D93)),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet({required this.auth});

  final AuthService auth;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_newController.text.trim().isEmpty ||
        _newController.text != _repeatController.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(I18n.t('Пароли не совпадают', 'Парольёс уг туртто',
                'Passwords do not match',
                tt: 'Серсүзләр туры килми', ba: 'Паролдәр тап килмәй'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.auth.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(I18n.t(
                'Пароль изменён', 'Пароль воштэм', 'Password changed',
                tt: 'Серсүз үзгәртелде', ba: 'Пароль үҙгәртелде'))),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: UiTokens.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                I18n.t('Сменить пароль', 'Пароль вошттыны', 'Change password',
                    tt: 'Серсүзне алыштыру', ba: 'Паролде алмаштырыу'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _currentController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: I18n.t(
                      'Текущий пароль', 'Анысь пароль', 'Current password',
                      tt: 'Хәзерге серсүз', ba: 'Хәҙерге пароль'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: I18n.t(
                      'Новый пароль', 'Выль пароль', 'New password',
                      tt: 'Яңа серсүз', ba: 'Яңы пароль'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _repeatController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: I18n.t(
                      'Повторите пароль', 'Парольез кабат', 'Repeat password',
                      tt: 'Серсүзне кабатлагыз', ba: 'Паролде ҡабатлағыҙ'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(I18n.t('Сохранить', 'Утчаны', 'Save',
                        tt: 'Сакларга', ba: 'Һаҡларға')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
