import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_language.dart';
import '../../models/session_models.dart';
import '../../services/auth_service.dart';
import '../../services/home_assistant_connection_service.dart';
import '../../services/push_service.dart';
import '../../smart_home/smart_home_shell.dart';
import 'first_run_experience.dart';
import 'home_assistant_onboarding_screen.dart';
import 'login_screen.dart';

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({
    super.key,
    this.externalSession,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.language,
    required this.onLanguageChanged,
  });

  final ValueNotifier<AppSession?>? externalSession;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  static const _haSkipKeyPrefix = 'home_assistant_setup_skipped_';
  final _auth = AuthService();
  final _connections = HomeAssistantConnectionService();
  bool _loading = true;
  bool _firstRunCompleted = false;
  bool _homeAssistantConnected = false;
  bool _homeAssistantSkipped = false;
  AppSession? _session;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _attachExternalSessionListener();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      _auth.getSession(),
      FirstRunExperience.isCompleted(),
    ]);
    final session = results[0] as AppSession?;
    final firstRunCompleted = results[1] as bool;
    var connected = false;
    var skipped = false;
    if (session != null) {
      await PushService.instance.registerToken(session);
      connected = await _connections.isConnected(session.id);
      final prefs = await SharedPreferences.getInstance();
      skipped = prefs.getBool('$_haSkipKeyPrefix${session.id}') ?? false;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _firstRunCompleted = firstRunCompleted;
      _homeAssistantConnected = connected;
      _homeAssistantSkipped = skipped;
      _loading = false;
    });
  }

  void _attachExternalSessionListener() {
    final notifier = widget.externalSession;
    if (notifier == null) return;
    notifier.addListener(_handleExternalSession);
    final pendingSession = notifier.value;
    if (pendingSession != null) {
      notifier.value = null;
      _acceptSession(pendingSession);
    }
  }

  void _detachExternalSessionListener() {
    widget.externalSession?.removeListener(_handleExternalSession);
  }

  void _handleExternalSession() {
    final session = widget.externalSession?.value;
    if (session == null) return;
    widget.externalSession?.value = null;
    _acceptSession(session);
  }

  @override
  void dispose() {
    _detachExternalSessionListener();
    super.dispose();
  }

  Future<void> _logout() async {
    final current = _session;
    if (current != null) {
      await PushService.instance.unregisterToken(current);
      try {
        await _auth.deleteHomeAssistantConnection();
      } catch (_) {}
    }
    await _auth.clearSession();
    if (!mounted) return;
    setState(() {
      _session = null;
      _homeAssistantConnected = false;
      _homeAssistantSkipped = false;
    });
  }

  Future<void> _acceptSession(AppSession session) async {
    await PushService.instance.registerToken(session);
    final connected = await _connections.isConnected(session.id);
    final prefs = await SharedPreferences.getInstance();
    final skipped = prefs.getBool('$_haSkipKeyPrefix${session.id}') ?? false;
    if (!mounted) return;
    setState(() {
      _session = session;
      _homeAssistantConnected = connected;
      _homeAssistantSkipped = skipped;
    });
  }

  // Called from external deeplink handlers to accept a freshly obtained session
  Future<void> acceptSessionFromExternal(AppSession session) async {
    await _acceptSession(session);
  }

  Future<void> _skipHomeAssistant() async {
    final session = _session;
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_haSkipKeyPrefix${session.id}', true);
    if (mounted) setState(() => _homeAssistantSkipped = true);
  }

  Future<void> _completeHomeAssistant() async {
    final session = _session;
    if (session != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_haSkipKeyPrefix${session.id}');
    }
    if (mounted) setState(() => _homeAssistantConnected = true);
  }

  @override
  void didUpdateWidget(covariant AppEntryPoint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalSession != widget.externalSession) {
      oldWidget.externalSession?.removeListener(_handleExternalSession);
      _attachExternalSessionListener();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_loading) {
      child = const SizedBox.expand(
        key: ValueKey('auth_loading_blank'),
      );
    } else if (!_firstRunCompleted) {
      child = FirstRunExperience(
        key: const ValueKey('first_run'),
        onFinished: () => setState(() => _firstRunCompleted = true),
      );
    } else if (_session == null) {
      child = LoginScreen(
        key: const ValueKey('login_screen'),
        auth: _auth,
        onLoginSuccess: _acceptSession,
      );
    } else if (!_homeAssistantConnected && !_homeAssistantSkipped) {
      child = HomeAssistantOnboardingScreen(
        key: const ValueKey('home_assistant_onboarding'),
        session: _session!,
        onConnected: _completeHomeAssistant,
        onSkip: _skipHomeAssistant,
        onBackToLogin: _logout,
      );
    } else {
      child = SmartHomeShell(
        key: const ValueKey('home_screen'),
        auth: _auth,
        session: _session!,
        onLogout: _logout,
        isDarkMode: widget.isDarkMode,
        onToggleTheme: widget.onToggleTheme,
        language: widget.language,
        onLanguageChanged: widget.onLanguageChanged,
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(animation);
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
