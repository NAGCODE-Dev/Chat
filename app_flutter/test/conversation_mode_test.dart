import 'package:flutter_test/flutter_test.dart';

import 'package:chat_app/core/conversation_mode.dart';

void main() {
  test('normaliza caixa, acentos e pontuação', () {
    expect(normalizeSpeech('  Olá, CHÁ!  '), 'ola cha');
    expect(normalizeSpeech('Ação — coração'), 'acao coracao');
  });

  test('detecta a palavra de ativação no meio da fala', () {
    expect(containsWakeWord('Ei, Chat, tudo bem?', 'chat'), isTrue);
    expect(containsWakeWord('CHAT', 'chat'), isTrue);
    expect(containsWakeWord('vamos conversar', 'chat'), isFalse);
    expect(containsWakeWord('chatbot', 'chat'), isFalse);
  });

  test('aceita palavra de ativação com várias palavras', () {
    expect(containsWakeWord('Ei Jarvis, abra a agenda', 'ei jarvis'), isTrue);
    expect(
      stripWakeWord('Ei Jarvis, abra a agenda', 'ei jarvis'),
      'abra a agenda',
    );
  });

  test('remove apenas a palavra de ativação', () {
    expect(
      stripWakeWord('Ei, Chat, qual é a previsão?', 'chat'),
      'Ei, qual é a previsão?',
    );
    expect(stripWakeWord('Chat', 'chat'), isEmpty);
    expect(
      stripWakeWord('sem a palavra combinada', 'chat'),
      'sem a palavra combinada',
    );
  });

  test('palavra vazia desliga o portão', () {
    expect(containsWakeWord('qualquer fala', ''), isTrue);
    expect(stripWakeWord('qualquer fala', ''), 'qualquer fala');
  });
}
