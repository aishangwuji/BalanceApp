import 'package:flutter/material.dart';

import 'app.dart';
import 'data/services/auth_service.dart';
import 'data/services/chat_storage_service.dart';
import 'data/services/key_store.dart';
import 'data/services/preferences_service.dart';
import 'state/assets_controller.dart';
import 'state/chat_controller.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final PreferencesService prefs = await PreferencesService.load();
  final KeyStore keyStore = KeyStore();
  final SettingsController settings = await SettingsController.load(
    prefs: prefs,
    keyStore: keyStore,
  );
  final ChatStorageService storage = ChatStorageService(prefs);
  final AssetsController assets = AssetsController(
    prefs: prefs,
    keyStore: keyStore,
  );
  final ChatController chat = ChatController(
    storage: storage,
    settings: settings,
    keyStore: keyStore,
    auth: AuthService(),
  );

  runApp(
    BalanceApp(
      settings: settings,
      assets: assets,
      chat: chat,
    ),
  );
}
