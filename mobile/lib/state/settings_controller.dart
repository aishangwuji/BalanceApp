import 'package:flutter/material.dart';

import '../data/services/key_store.dart';
import '../data/services/jev_service.dart';
import '../data/services/preferences_service.dart';
import '../data/services/topic_gate_service.dart';

const List<double> fontScaleLevels = <double>[
  0.85,
  0.92,
  1.0,
  1.08,
  1.16,
  1.25,
  1.35,
];

class SettingsController extends ChangeNotifier {
  SettingsController({
    required PreferencesService prefs,
    required KeyStore keyStore,
  })  : _prefs = prefs,
        _keyStore = keyStore;

  final PreferencesService _prefs;
  final KeyStore _keyStore;

  String _appearance = 'system';
  int _fontLevel = 3;
  bool _autoCollapseThinking = true;
  String _language = 'zh-CN';
  bool _appLockEnabled = false;
  bool _appLocked = false;
  bool _topicGateEnabled = false;
  double _topicGateThreshold = 0.5;
  String _topicGateChannel = 'typesafe';

  String get appearance => _appearance;
  int get fontLevel => _fontLevel;
  double get fontScale =>
      fontScaleLevels[(_fontLevel - 1).clamp(0, 6).toInt()];
  bool get autoCollapseThinking => _autoCollapseThinking;
  String get language => _language;
  bool get appLockEnabled => _appLockEnabled;
  bool get appLocked => _appLocked;
  bool get topicGateEnabled => _topicGateEnabled;
  double get topicGateThreshold => _topicGateThreshold;
  String get topicGateChannel => _topicGateChannel;

  ThemeMode get themeMode {
    switch (_appearance) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<SettingsController> load({
    required PreferencesService prefs,
    required KeyStore keyStore,
  }) async {
    final SettingsController c = SettingsController(
      prefs: prefs,
      keyStore: keyStore,
    );
    c._appearance = _validAppearance(
      prefs.getString(PreferencesService.keyAppearance, fallback: 'system'),
    );
    final int level = prefs.getInt(PreferencesService.keyFontSizeLevel, fallback: 3);
    c._fontLevel = level.clamp(1, 7);
    c._autoCollapseThinking =
        prefs.getBool(PreferencesService.keyAutoCollapseThinking, fallback: true);
    final String lang =
        prefs.getString(PreferencesService.keyAppLanguage, fallback: 'zh-CN');
    c._language = lang == 'en-US' ? 'en-US' : 'zh-CN';
    c._appLockEnabled =
        prefs.getBool(PreferencesService.keyAppLockEnabled, fallback: false);
    c._appLocked = c._appLockEnabled;
    c._topicGateEnabled =
        prefs.getBool(PreferencesService.keyTopicGateEnabled, fallback: false);
    final double threshold = prefs.getDouble(
      PreferencesService.keyTopicGateThreshold,
      fallback: 0.5,
    );
    c._topicGateThreshold = threshold.clamp(0.0, 1.0);
    c._topicGateChannel = _validChannel(
      prefs.getString(
        PreferencesService.keyTopicGateChannel,
        fallback: 'typesafe',
      ),
    );
    return c;
  }

  static String _validAppearance(String value) {
    if (value == 'light' || value == 'dark' || value == 'system') {
      return value;
    }
    return 'system';
  }

  static String _validChannel(String value) =>
      value == 'openrouter' ? 'openrouter' : 'typesafe';

  Future<void> setAppearance(String value) async {
    _appearance = _validAppearance(value);
    notifyListeners();
    await _prefs.setString(PreferencesService.keyAppearance, _appearance);
  }

  Future<void> setFontSizeLevel(int level) async {
    _fontLevel = level.clamp(1, 7);
    notifyListeners();
    await _prefs.setInt(PreferencesService.keyFontSizeLevel, _fontLevel);
  }

  Future<void> setAutoCollapseThinking(bool enabled) async {
    _autoCollapseThinking = enabled;
    notifyListeners();
    await _prefs.setBool(PreferencesService.keyAutoCollapseThinking, enabled);
  }

  Future<void> setLanguage(String language) async {
    _language = language == 'en-US' ? 'en-US' : 'zh-CN';
    notifyListeners();
    await _prefs.setString(PreferencesService.keyAppLanguage, _language);
  }

  /// Business Rule: disabling the lock clears the current lock immediately;
  /// enabling it takes effect the next time the app leaves the foreground.
  Future<void> setAppLockEnabled(bool enabled) async {
    _appLockEnabled = enabled;
    if (!enabled) {
      _appLocked = false;
    }
    notifyListeners();
    await _prefs.setBool(PreferencesService.keyAppLockEnabled, enabled);
  }

  void lock() {
    if (!_appLockEnabled || _appLocked) {
      return;
    }
    _appLocked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_appLocked) {
      return;
    }
    _appLocked = false;
    notifyListeners();
  }

  Future<void> setTopicGateEnabled(bool enabled) async {
    _topicGateEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(PreferencesService.keyTopicGateEnabled, enabled);
  }

  Future<void> setTopicGateThreshold(double threshold) async {
    _topicGateThreshold = threshold.clamp(0.0, 1.0);
    notifyListeners();
    await _prefs.setDouble(
      PreferencesService.keyTopicGateThreshold,
      _topicGateThreshold,
    );
  }

  Future<void> setTopicGateChannel(String channel) async {
    _topicGateChannel = _validChannel(channel);
    notifyListeners();
    await _prefs.setString(
      PreferencesService.keyTopicGateChannel,
      _topicGateChannel,
    );
  }

  Future<String> readProviderKey(String providerId) =>
      _keyStore.read(KeyStore.providerKey(providerId));

  Future<void> writeProviderKey(String providerId, String key) =>
      _keyStore.write(KeyStore.providerKey(providerId), key);

  Future<void> deleteProviderKey(String providerId) =>
      _keyStore.delete(KeyStore.providerKey(providerId));

  String get systemOneKeyName => _topicGateChannel == 'openrouter'
      ? KeyStore.systemOneOpenRouter
      : KeyStore.systemOneTypesafe;

  Future<String> readSystemOneKey() => _keyStore.read(systemOneKeyName);

  Future<void> writeSystemOneKey(String key) =>
      _keyStore.write(systemOneKeyName, key);

  Future<void> deleteSystemOneKey() => _keyStore.delete(systemOneKeyName);

  Future<TopicGateConfig> buildTopicGateConfig() async {
    final SystemOneChannel? channel =
        findSystemOneChannel(_topicGateChannel);
    return TopicGateConfig(
      enabled: _topicGateEnabled,
      channel: _topicGateChannel,
      apiKey: await readSystemOneKey(),
      threshold: _topicGateThreshold,
      endpoint: channel?.endpoint ?? systemOneDefaultEndpoint,
      model: channel?.model ?? systemOneDefaultModel,
    );
  }
}
