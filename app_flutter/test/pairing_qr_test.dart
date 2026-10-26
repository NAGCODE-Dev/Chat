import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:chat_app/app/theme/app_theme.dart';
import 'package:chat_app/core/backend_client.dart';
import 'package:chat_app/features/pairing/pairing_qr_dialog.dart';

class _FakePairingClient extends BackendClient {
  _FakePairingClient() : super('http://127.0.0.1:1');

  @override
  Future<Map<String, dynamic>> createPairingSession() async => {
    'code': 'codigo-seguro',
    'urls': ['http://100.97.209.46:8750'],
    'qr_payload':
        'chatpair://pair?v=1&code=codigo-seguro'
        '&url=http%3A%2F%2F100.97.209.46%3A8750',
    'expires_in': 300,
  };

  @override
  Future<Map<String, dynamic>> pairingStatus() async => {
    'pairing_available': true,
    'lan_available': true,
    'tailscale_installed': true,
    'tailscale_logged_in': true,
    'tailscale_online': true,
  };
}

void main() {
  testWidgets('diálogo mostra QR e Tailscale sem expor o endereço', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showPairingQrDialog(context, _FakePairingClient()),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.text('Tailscale conectado · funciona fora de casa'),
      findsOneWidget,
    );
    expect(find.textContaining('100.97.209.46'), findsNothing);
    expect(find.textContaining('192.168'), findsNothing);
    expect(find.textContaining('http://'), findsNothing);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });
}
