import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_language.dart';
import '../../core/i18n.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({
    super.key,
    required this.themeMode,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onChanged;

  @override
  Widget build(BuildContext context) => _SettingsScaffold(
        title: I18n.t('Тема', 'Тема', 'Theme'),
        children: [
          _SettingsCard(
            child: Column(
              children: ThemeMode.values.map((mode) {
                final title = switch (mode) {
                  ThemeMode.system => I18n.t('Системная', 'Система', 'System'),
                  ThemeMode.light => I18n.t('Светлая', 'Югыт', 'Light'),
                  ThemeMode.dark => I18n.t('Тёмная', 'Пеймыт', 'Dark'),
                };
                return RadioListTile<ThemeMode>(
                  value: mode,
                  groupValue: themeMode,
                  activeColor: const Color(0xFFFF7A18),
                  title: Text(title),
                  onChanged: (value) async {
                    if (value == null) return;
                    await onChanged(value);
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      );
}

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({
    super.key,
    required this.language,
    required this.onChanged,
  });
  final AppLanguage language;
  final Future<void> Function(AppLanguage) onChanged;

  @override
  Widget build(BuildContext context) => _SettingsScaffold(
        title: I18n.t('Язык', 'Кыл', 'Language', tt: 'Тел', ba: 'Тел'),
        children: [
          _SettingsCard(
            child: Column(
              children: AppLanguage.available.map((item) {
                return RadioListTile<AppLanguage>(
                  value: item,
                  groupValue: language,
                  activeColor: const Color(0xFFFF7A18),
                  title: Text(item.ruLabel),
                  onChanged: (value) async {
                    if (value == null) return;
                    await onChanged(value);
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      );
}

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  static const _biometricKey = 'biometric_unlock_enabled';
  final biometrics = BiometricService();
  bool loading = true;
  bool processing = false;
  bool biometric = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        biometric = prefs.getBool(_biometricKey) ?? false;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> toggleBiometric(bool value) async {
    if (!value) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricKey, false);
      if (mounted) setState(() => biometric = false);
      return;
    }
    try {
      if (!await biometrics.isAvailable()) {
        throw Exception(I18n.t('Биометрия недоступна или не настроена',
            'Биометрия уг луы', 'Biometrics is unavailable or not configured'));
      }
      final ok = await biometrics.authenticate(
          reason: I18n.t('Подтвердите включение биометрического входа',
              'Биометрияез юнматэ', 'Confirm biometric sign-in'));
      if (!ok) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricKey, true);
      if (mounted) setState(() => biometric = true);
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void openPassword() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PasswordSheet(auth: widget.auth),
      );

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _SettingsScaffold(
          title: I18n.t('Безопасность', 'Утинлык', 'Security'),
          children: const [Center(child: CircularProgressIndicator())]);
    }
    return _SettingsScaffold(
      title: I18n.t('Безопасность', 'Утинлык', 'Security'),
      children: [
        _ActionTile(
          icon: Icons.lock_outline_rounded,
          title: I18n.t('Сменить пароль', 'Пароль вошттыны', 'Change password'),
          onTap: openPassword,
        ),
        const SizedBox(height: 10),
        _SettingsCard(
          child: SwitchListTile.adaptive(
            value: biometric,
            onChanged: processing ? null : toggleBiometric,
            secondary: const Icon(Icons.fingerprint_rounded),
            title: Text(I18n.t('Биометрический вход', 'Биометрияен пырон',
                'Biometric sign-in')),
            subtitle: Text(I18n.t('Отпечаток пальца или распознавание лица',
                'Чиньы пус я лице', 'Fingerprint or face recognition')),
          ),
        ),
      ],
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.auth});
  final AuthService auth;
  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final current = TextEditingController();
  final next = TextEditingController();
  final repeat = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (next.text.length < 8 || next.text != repeat.text) {
      setState(() => error = I18n.t('Проверьте новый пароль',
          'Выль парольдэ эскер', 'Check the new password'));
      return;
    }
    setState(() => saving = true);
    try {
      await widget.auth.changePassword(
          currentPassword: current.text, newPassword: next.text);
      if (mounted) Navigator.pop(context);
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
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
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
                  Text(
                      I18n.t('Сменить пароль', 'Пароль вошттыны',
                          'Change password'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  TextField(
                      controller: current,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: I18n.t('Текущий пароль', 'Анысь пароль',
                              'Current password'))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: next,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: I18n.t(
                              'Новый пароль', 'Выль пароль', 'New password'))),
                  const SizedBox(height: 10),
                  TextField(
                      controller: repeat,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: I18n.t('Повторите пароль',
                              'Парольез кабат', 'Repeat password'))),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error!,
                            style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: saving ? null : save,
                      child: Text(I18n.t('Сохранить', 'Утчаны', 'Save'))),
                ]),
          ),
        ),
      );
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: children),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: child,
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => _SettingsCard(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFFFF7A18)),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}
