import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chat_app/core/screen_awake.dart';
import 'package:chat_app/core/token_store.dart';
import 'package:chat_app/main.dart';

class _MemoryTokenStore implements TokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String? token) async {}
}

Finder _clockText() => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data != null &&
      RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data!),
);

void main() {
  testWidgets('relógio gigante aparece e volta à conversa ao tocar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
      'clock_mode_enabled': true,
      'hibernation_minutes': 5,
      'clock_24h': true,
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChatApp(tokenStore: _MemoryTokenStore(), screenAwake: NoopScreenAwake()),
    );
    await tester.pumpAndSettle();

    expect(_clockText(), findsOneWidget);
    expect(find.text('Toque na tela para conversar'), findsOneWidget);
    expect(find.textContaining('Hibernação ativa'), findsOneWidget);

    await tester.tap(find.text('Toque na tela para conversar'));
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão com o notebook'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('F11 alterna tela cheia sem sair do relógio', (tester) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
      'clock_mode_enabled': true,
      'hibernation_minutes': 5,
      'clock_24h': true,
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const channel = MethodChannel('chat/window');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      ChatApp(tokenStore: _MemoryTokenStore(), screenAwake: NoopScreenAwake()),
    );
    await tester.pumpAndSettle();
    expect(find.text('F11 alterna a tela cheia'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(calls, isNotEmpty);
    expect(calls.last.method, 'setFullscreen');
    expect(calls.last.arguments, isTrue);
    expect(_clockText(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(calls.last.arguments, isFalse);
    expect(_clockText(), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inatividade entra em hibernação no tempo configurado', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
      'clock_mode_enabled': true,
      'hibernation_minutes': 1,
      'clock_24h': true,
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChatApp(tokenStore: _MemoryTokenStore(), screenAwake: NoopScreenAwake()),
    );
    await tester.pumpAndSettle();
    expect(_clockText(), findsOneWidget);

    await tester.tap(find.byKey(const Key('clock-screen')));
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão com o notebook'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(_clockText(), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('preferências do relógio são persistidas e ativam o modo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://127.0.0.1:1',
    });
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChatApp(tokenStore: _MemoryTokenStore(), screenAwake: NoopScreenAwake()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Modo relógio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('clock_mode_enabled'), isTrue);
    expect(preferences.getInt('hibernation_minutes'), 5);
    expect(preferences.getBool('clock_24h'), isTrue);
    expect(_clockText(), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
