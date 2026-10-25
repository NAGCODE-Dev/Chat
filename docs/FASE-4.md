# Fase 4 — voz local

## Entrega

- Contratos substituíveis `STTEngine` e `TTSEngine`.
- Adaptador STT para o executável `whisper-cli` do whisper.cpp, configurado
  para pt-BR, 16 kHz e limite de tempo.
- Adaptador TTS para Piper, produzindo WAV em português brasileiro.
- `POST /api/voice/transcribe` recebe WAV PCM mono de 16 bits, 16 kHz; limite
  de 25 MiB. `POST /api/voice/synthesize` recebe texto de até 4000 caracteres
  e devolve `audio/wav`. `GET /api/voice/status` informa os mecanismos ativos.
- O app grava pelo microfone, envia a transcrição ao chat, reproduz respostas
  quando TTS está configurado e oferece replay. Tocar no microfone durante a
  reprodução para o áudio e inicia uma gravação nova.
- No Linux, captura é feita via `pw-record` e playback usa `aplay`, com fallback
  para `ffplay`; nos demais alvos, a captura usa o plugin Flutter `record`.

## Configuração do backend

Instale a dependência opcional do Piper no ambiente virtual do backend:

```bash
cd backend
.venv/bin/pip install -e '.[voice]'
```

Baixe uma voz e um modelo whisper.cpp e exporte as configurações antes de
iniciar o servidor:

```bash
export CHAT_WHISPER_BINARY=/caminho/para/whisper-cli
export CHAT_WHISPER_MODEL_PATH="$HOME/.local/share/chat/models/whisper/ggml-base.bin"
export CHAT_PIPER_MODEL_PATH="$HOME/.local/share/chat/models/piper/pt_BR-faber-medium.onnx"
```

O STT é habilitado apenas quando `CHAT_WHISPER_MODEL_PATH` é definido; o TTS
apenas quando `CHAT_PIPER_MODEL_PATH` é definido. Esta instalação foi
configurada em `~/.local/share/chat/models` com `ggml-base.bin` e a voz
`pt_BR-faber-medium`.

As instruções upstream estão em [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
e [Piper](https://github.com/OHF-Voice/piper1-gpl). Os pesos permanecem na pasta
de dados do usuário e não são incluídos no repositório.

O pacote Piper upstream é GPL-3.0; confira também a licença do modelo de voz
caso pretenda redistribuir o aplicativo ou os pesos.

## Validação e limite

Foram executados Ruff e os testes do backend (13 aprovados), além de
`flutter analyze`, `flutter test` e `flutter build linux`. A API real sintetizou
fala com Piper e a transcreveu com whisper.cpp. A captura física do microfone e
a audição em alto-falantes dependem do dispositivo de áudio e devem ser
confirmadas ao usar a tela; não foram gravados sons do ambiente durante esta
validação.
