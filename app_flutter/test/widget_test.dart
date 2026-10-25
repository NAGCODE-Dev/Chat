import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chat_app/main.dart';
import 'package:chat_app/core/token_store.dart';

class _MemoryTokenStore implements TokenStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? token) async => value = token;
}

void main() {
  testWidgets('Chat mostra a tela inicial em português', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ChatApp(tokenStore: _MemoryTokenStore()));
    await tester.pumpAndSettle();

    expect(find.text('Como posso ajudar?'), findsOneWidget);
    expect(find.text('Escreva uma mensagem'), findsOneWidget);
  });

  testWidgets('token é entregue ao cofre e não às preferências', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
    });
    final tokenStore = _MemoryTokenStore();
    await tester.pumpWidget(ChatApp(tokenStore: tokenStore));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurar conexão'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'secret-test-token');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(tokenStore.value, 'secret-test-token');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'backend_url'});
    expect(preferences.getString('api_token'), isNull);
  });
}
