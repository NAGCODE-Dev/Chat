import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chat_app/core/token_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Secret Service grava, lê e apaga credencial', (tester) async {
    final key =
        'chat-integration-test-${DateTime.now().microsecondsSinceEpoch}';
    final tokenStore = KeyringTokenStore(key: key);
    addTearDown(() => tokenStore.write(null));

    await tokenStore.write('ephemeral-integration-token');
    expect(await tokenStore.read(), 'ephemeral-integration-token');

    await tokenStore.write(null);
    expect(await tokenStore.read(), isNull);
  });
}
