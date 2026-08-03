import 'package:flutter/material.dart';

enum AppLanguage {
  ru('ru', 'Русский', 'Кылбур'),
  udm('udm', 'Удмурт кыл', 'Udmurt'),
  tt('tt', 'Татарча', 'Tatar'),
  ba('ba', 'Башҡортса', 'Bashkir'),
  en('en', 'English', 'English');

  const AppLanguage(this.code, this.ruLabel, this.enLabel);

  final String code;
  final String ruLabel;
  final String enLabel;

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
      case 'ba':
        return AppLanguage.ba;
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
