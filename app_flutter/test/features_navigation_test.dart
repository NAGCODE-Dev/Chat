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
  testWidgets('menu abre telas de listas e dispositivos', (tester) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
    });
    await tester.pumpWidget(ChatApp(tokenStore: _MemoryTokenStore()));
    await tester.pumpAndSettle();

    // A navegação fica na gaveta, junto das conversas; a barra inferior saiu.
    expect(find.byKey(const ValueKey('drawer-nav-explore')), findsNothing);
    await tester.tap(find.byTooltip('Histórico de conversas'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer-nav-explore')), findsOneWidget);

    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    expect(find.text('Lista de desejos'), findsOneWidget);
    expect(find.text('Memórias'), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);

    await tester.tap(find.text('Lista de desejos'));
    await tester.pumpAndSettle();
    expect(find.text('Adicionar'), findsOneWidget);
  });
}
