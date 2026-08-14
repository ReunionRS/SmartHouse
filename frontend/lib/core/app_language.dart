import 'package:flutter/material.dart';

enum AppLanguage {
  ru('ru', 'Русский', 'Кылбур'),
  udm('udm', 'Удмурт кыл', 'Udmurt'),
  tt('tt', 'Татарча', 'Tatar'),
  ba('ba', 'Башҡортса', 'Bashkir'),
  de('de', 'Deutsch', 'German'),
  fr('fr', 'Français', 'French'),
  be('be', 'Беларуская', 'Belarusian'),
  sr('sr', 'Српски', 'Serbian'),
  zh('zh', '中文', 'Chinese'),
  ko('ko', '한국어', 'Korean'),
  ja('ja', '日本語', 'Japanese'),
  en('en', 'English', 'English');

  const AppLanguage(this.code, this.ruLabel, this.enLabel);

  final String code;
  final String ruLabel;
  final String enLabel;

  static const List<AppLanguage> available = [
    AppLanguage.ru,
    AppLanguage.udm,
    AppLanguage.tt,
    AppLanguage.en,
  ];

  Locale get locale {
    switch (this) {
      case AppLanguage.ru:
        return const Locale('ru');
      case AppLanguage.udm:
        // Framework localizations fallback to Russian while app text is Udmurt.
        return const Locale('ru');
      case AppLanguage.tt:
        // Keep Flutter framework localizations stable (date pickers, material labels)
        // while app-specific texts are translated via I18n.
        return const Locale('ru');
      case AppLanguage.ba:
        return const Locale('ru');
      case AppLanguage.en:
        return const Locale('en');
      case AppLanguage.de:
        return const Locale('de');
      case AppLanguage.fr:
        return const Locale('fr');
      case AppLanguage.be:
        return const Locale('be');
      case AppLanguage.sr:
        return const Locale('sr');
      case AppLanguage.zh:
        return const Locale('zh');
      case AppLanguage.ko:
        return const Locale('ko');
      case AppLanguage.ja:
        return const Locale('ja');
    }
  }

  static AppLanguage fromCode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'udm':
        return AppLanguage.udm;
      case 'en':
        return AppLanguage.en;
      case 'tt':
        return AppLanguage.tt;
      case 'ru':
      default:
        return AppLanguage.ru;
    }
  }
}

class AppLanguageStore {
  static final ValueNotifier<AppLanguage> notifier =
      ValueNotifier<AppLanguage>(AppLanguage.ru);

  static AppLanguage get current => notifier.value;

  static void set(AppLanguage language) {
    if (notifier.value == language) return;
    notifier.value = language;
  }
}
