import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/auth/app_entry_point.dart';
import 'models/session_models.dart';
import 'services/auth_service.dart';
import 'core/app_language.dart';
import 'core/ui_tokens.dart';

class SmartHouseApp extends StatefulWidget {
  const SmartHouseApp({super.key});

  @override
  State<SmartHouseApp> createState() => _SmartHouseAppState();
}

class _SmartHouseAppState extends State<SmartHouseApp> {
  static const _languageKey = 'app_language';
  static const _themeKey = 'app_theme_mode';
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey _appEntryKey = GlobalKey();
  final ValueNotifier<AppSession?> _pendingExternalSession =
      ValueNotifier(null);
  final AppLinks _appLinks = AppLinks();
  AppLanguage _language = AppLanguage.ru;
  ThemeMode _themeMode = ThemeMode.system;
  bool _bootstrapped = false;

  bool get _isDark =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initDeepLinkListener();
  }

  StreamSubscription? _sub;

  Future<void> _initDeepLinkListener() async {
    // handle initial uri
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleIncomingUri(initial);
    } catch (_) {}
    // listen for subsequent links
    _sub = _appLinks.uriLinkStream.listen((uri) async {
      await _handleIncomingUri(uri);
    }, onError: (_) {});
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    try {
      // Web redirect handled elsewhere; here we care about native scheme smarthouse://
      if ((uri.scheme == 'smarthouse' && uri.host == 'one-time-login') ||
          (uri.path == '/one-time-login' &&
              uri.queryParameters['token'] != null)) {
        final token = uri.queryParameters['token'];
        if (token == null || token.isEmpty) return;
        final auth = AuthService();
        final session = await auth.oneTimeLogin(token);
        _pendingExternalSession.value = session;
        // pass session to AppEntryPoint if available
        final entryState = _appEntryKey.currentState;
        try {
          if (entryState != null) {
            // call dynamically to avoid private state typing
            (entryState as dynamic).acceptSessionFromExternal(session);
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pendingExternalSession.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_languageKey) ?? 'ru';
    final themeRaw = prefs.getString(_themeKey) ?? ThemeMode.system.name;
    if (!mounted) return;
    setState(() {
      _language = AppLanguage.fromCode(raw);
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == themeRaw,
        orElse: () => ThemeMode.system,
      );
      _bootstrapped = true;
    });
    AppLanguageStore.set(_language);
  }

  void _toggleTheme() {}

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> _setLanguage(AppLanguage language) async {
    if (_language == language) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.code);
    if (!mounted) return;
    setState(() => _language = language);
    AppLanguageStore.set(language);
  }

  static const List<String> _fontFallback = <String>[
    'Noto Sans',
    'sans-serif',
  ];

  TextTheme _withFallback(TextTheme theme) {
    TextStyle? apply(TextStyle? style) =>
        style?.copyWith(fontFamilyFallback: _fontFallback);
    return theme.copyWith(
      displayLarge: apply(theme.displayLarge),
      displayMedium: apply(theme.displayMedium),
      displaySmall: apply(theme.displaySmall),
      headlineLarge: apply(theme.headlineLarge),
      headlineMedium: apply(theme.headlineMedium),
      headlineSmall: apply(theme.headlineSmall),
      titleLarge: apply(theme.titleLarge),
      titleMedium: apply(theme.titleMedium),
      titleSmall: apply(theme.titleSmall),
      bodyLarge: apply(theme.bodyLarge),
      bodyMedium: apply(theme.bodyMedium),
      bodySmall: apply(theme.bodySmall),
      labelLarge: apply(theme.labelLarge),
      labelMedium: apply(theme.labelMedium),
      labelSmall: apply(theme.labelSmall),
    );
  }

  ThemeData _buildDarkTheme() {
    const primary = UiTokens.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    final baseText = _withFallback(GoogleFonts.dmSansTextTheme(
      ThemeData.dark().textTheme,
    ));
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: primary,
        surface: UiTokens.cardDark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      scaffoldBackgroundColor: UiTokens.backgroundDark,
      cardTheme: CardTheme(
        color: UiTokens.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: UiTokens.cardDark,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      dividerColor: UiTokens.borderDark,
      textTheme: _withFallback(baseText.copyWith(
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          textStyle: const TextStyle(fontFamilyFallback: _fontFallback),
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          textStyle: const TextStyle(fontFamilyFallback: _fontFallback),
        ),
      )),
    );
  }

  ThemeData _buildLightTheme() {
    const primary = UiTokens.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    final baseText = _withFallback(
      GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme),
    );
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: primary,
        surface: Colors.white.withOpacity(.78),
      ),
      scaffoldBackgroundColor: UiTokens.backgroundLight,
      cardTheme: CardTheme(
        color: Colors.white.withOpacity(.72),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        foregroundColor: UiTokens.foregroundLight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(.68),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x66FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      dividerColor: UiTokens.borderLight,
      textTheme: _withFallback(baseText.copyWith(
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          textStyle: const TextStyle(fontFamilyFallback: _fontFallback),
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          textStyle: const TextStyle(fontFamilyFallback: _fontFallback),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        supportedLocales: [
          Locale('ru'),
          Locale('en'),
        ],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Smart House',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
      locale: _language.locale,
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppEntryPoint(
        key: _appEntryKey,
        externalSession: _pendingExternalSession,
        isDarkMode: _isDark,
        onToggleTheme: _toggleTheme,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        language: _language,
        onLanguageChanged: _setLanguage,
      ),
    );
  }
}
