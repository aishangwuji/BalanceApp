import 'package:balance_app/core/theme/app_theme.dart';
import 'package:balance_app/data/services/auth_service.dart';
import 'package:balance_app/data/services/chat_storage_service.dart';
import 'package:balance_app/data/services/key_store.dart';
import 'package:balance_app/data/services/preferences_service.dart';
import 'package:balance_app/state/assets_controller.dart';
import 'package:balance_app/state/chat_controller.dart';
import 'package:balance_app/state/settings_controller.dart';
import 'package:balance_app/ui/pages/assets_page.dart';
import 'package:balance_app/ui/pages/chat_page.dart';
import 'package:balance_app/ui/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> buildApp({required Widget home}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final PreferencesService prefs = await PreferencesService.load();
  final KeyStore keyStore = KeyStore();
  final SettingsController settings = await SettingsController.load(
    prefs: prefs,
    keyStore: keyStore,
  );
  final AssetsController assets = AssetsController(
    prefs: prefs,
    keyStore: keyStore,
  );
  final ChatController chat = ChatController(
    storage: ChatStorageService(prefs),
    settings: settings,
    keyStore: keyStore,
    auth: AuthService(),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<AssetsController>.value(value: assets),
      ChangeNotifierProvider<ChatController>.value(value: chat),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: home,
    ),
  );
}

void main() {
  testWidgets('chat page renders empty state and drawer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(await buildApp(home: const ChatPage()));
    await tester.pumpAndSettle();
    expect(find.text('让想法慢慢展开'), findsOneWidget);
    expect(find.text('输入您的问题...'), findsOneWidget);

    await tester.tapAt(const Offset(34, 28));
    await tester.pumpAndSettle();
    expect(find.text('历史会话'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('settings page renders sections', (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp(home: const SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('应用'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('应用锁'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('资产监控'), findsOneWidget);
    expect(find.text('上下文净化'), findsOneWidget);
  });

  testWidgets('assets page renders empty state', (WidgetTester tester) async {
    await tester.pumpWidget(await buildApp(home: const AssetsPage()));
    await tester.pumpAndSettle();
    expect(find.text('资产监控'), findsOneWidget);
    expect(find.text('暂无服务商'), findsOneWidget);
  });
}
