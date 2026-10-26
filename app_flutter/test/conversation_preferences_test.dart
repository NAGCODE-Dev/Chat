import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chat_app/core/token_store.dart';
import 'package:chat_app/main.dart';

class _MemoryTokenStore implements TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String? token) async {}
}

void main() {
  testWidgets('preferências de conversa contínua são persistidas', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChatApp(tokenStore: _MemoryTokenStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Conversa contínua'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'jarvis');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('continuous_mode'), isTrue);
    expect(preferences.getString('wake_word'), 'jarvis');
    expect(find.textContaining('STT não está configurado'), findsOneWidget);
  });

  testWidgets('modo contínuo salvo é restaurado ao abrir o app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
      'continuous_mode': true,
      'wake_word': 'jarvis',
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChatApp(tokenStore: _MemoryTokenStore()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Conversa contínua ativa'), findsOneWidget);
    await tester.tap(find.byTooltip('Conversa contínua'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, 'jarvis');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}
