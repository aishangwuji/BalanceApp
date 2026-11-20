import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret app preferences.
///
/// Security note: API keys never live here; they are stored through
/// [KeyStore] (Keychain / Android Keystore backed secure storage).
class PreferencesService {
  PreferencesService._(this._prefs);

  final SharedPreferences _prefs;

  static const String keyAppearance = 'app_appearance';
  static const String keyFontSizeLevel = 'app_font_size_level';
  static const String keyAutoCollapseThinking = 'auto_collapse_thinking';
  static const String keyAppLanguage = 'app_language';
  static const String keyAppLockEnabled = 'app_lock_enabled';
  static const String keyAddedProviderIds = 'added_provider_ids';
  static const String keyActiveSessionId = 'active_session_id';

  static const String storeCharacters = 'saved_characters';
  static const String storeIdentities = 'saved_identities';
  static const String storeSessions = 'saved_sessions';

  static Future<PreferencesService> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PreferencesService._(prefs);
  }

  String getString(String key, {String fallback = ''}) =>
      _prefs.getString(key) ?? fallback;

  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  int getInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  double getDouble(String key, {double fallback = 0}) =>
      _prefs.getDouble(key) ?? fallback;

  Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
