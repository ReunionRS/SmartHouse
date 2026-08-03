import 'app_language.dart';

class I18n {
  static String t(
    String ru,
    String udm,
    String en, {
    String? tt,
    String? ba,
  }) {
    switch (AppLanguageStore.current) {
      case AppLanguage.udm:
        return udm;
      case AppLanguage.tt:
        return tt ?? ru;
      case AppLanguage.ba:
        return ba ?? ru;
      case AppLanguage.en:
        return en;
      case AppLanguage.ru:
        return ru;
    }
  }
}
