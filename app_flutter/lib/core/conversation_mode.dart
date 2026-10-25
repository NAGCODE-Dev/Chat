/// Detecção da palavra de ativação para a conversa contínua.
///
/// A comparação ignora caixa, acentos e pontuação, mas preserva a ordem das
/// palavras. Assim "Ei, Chat!" ativa a palavra "chat" sem exigir digitação
/// exata e sem confundir palavras parecidas no meio de uma frase.
library;

const Map<String, String> _accentMap = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Reduz o texto a palavras minúsculas, sem acentos e sem pontuação.
String normalizeSpeech(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final mapped = _accentMap[character] ?? character;
    final isLetterOrDigit = RegExp(r'[a-z0-9]').hasMatch(mapped);
    buffer.write(isLetterOrDigit ? mapped : ' ');
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<String> _wakeWords(String wakeWord) {
  final normalized = normalizeSpeech(wakeWord);
  return normalized.isEmpty ? const [] : normalized.split(' ');
}

int? _wakeStart(List<String> words, List<String> wakeWords) {
  if (wakeWords.isEmpty || words.length < wakeWords.length) return null;
  for (var start = 0; start <= words.length - wakeWords.length; start++) {
    var matches = true;
    for (var offset = 0; offset < wakeWords.length; offset++) {
      if (words[start + offset] != wakeWords[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return null;
}

/// Indica se a fala contém a palavra de ativação.
///
/// Uma palavra vazia desliga o portão e aceita qualquer fala.
bool containsWakeWord(String transcript, String wakeWord) {
  final wakeWords = _wakeWords(wakeWord);
  if (wakeWords.isEmpty) return true;
  return _wakeStart(normalizeSpeech(transcript).split(' '), wakeWords) != null;
}

/// Remove a primeira ocorrência da palavra de ativação da fala.
///
/// A pontuação original é preservada nas demais palavras; apenas os termos da
/// palavra de ativação são descartados. Se ela não estiver presente, o texto
/// original é devolvido sem alterações relevantes.
String stripWakeWord(String transcript, String wakeWord) {
  final wakeWords = _wakeWords(wakeWord);
  if (wakeWords.isEmpty) return transcript.trim();
  final originalWords = transcript
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final normalizedWords = originalWords.map(normalizeSpeech).toList();
  final start = _wakeStart(normalizedWords, wakeWords);
  if (start == null) return transcript.trim();
  final remaining = <String>[
    ...originalWords.take(start),
    ...originalWords.skip(start + wakeWords.length),
  ];
  return remaining.join(' ').trim();
}
