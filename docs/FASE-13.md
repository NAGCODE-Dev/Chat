# Fase 13 — app Android conectado ao backend

## Entrega

- Backend pode escutar fora de loopback com `CHAT_HOST=0.0.0.0`, sempre com
  `CHAT_API_TOKEN` de pelo menos 32 caracteres. HTTP e WebSocket exigem o
  Bearer token.
- Configuração local em `~/.config/chat/backend.env` (modo `600`), carregada
  por `scripts/dev_run.sh`.
- Serviço de usuário `chat-backend.service`, habilitado no login, com
  `Restart=on-failure`.
- App Android aponta para o PC por Wi-Fi (`http://192.168.0.126:8750`) ou USB
  (`http://10.22.184.11:8750`); o token fica no cofre do aparelho.
- Reprodução de áudio no Android via canal nativo `chat/audio` (`MediaPlayer`),
  sem GStreamer; no Linux continua `aplay`/`ffplay`. A gravação usa `record` no
  Android e `pw-record` no Linux.
- `android:usesCleartextTraffic="true"` no manifesto, necessário para falar
  com o backend local por HTTP.
- Token do desktop gravado no Secret Service/keyring com o mesmo schema do
  `flutter_secure_storage`.

## Validação

- `GET /health` sem token: `401`; com token: `200` em `127.0.0.1`,
  `192.168.0.126` e `10.22.184.11`.
- `GET /api/voice/status` e `GET /api/memories/embeddings/status` respondem
  com token nas duas interfaces.
- `chat-backend.service` ativo, escutando em `0.0.0.0:8750`.
- App Linux: `flutter analyze` limpo, 16 testes passando e build release.
- APK debug gerado em `app_flutter/build/app/outputs/flutter-apk/app-debug.apk`.

## Limites

- O tráfego na rede local é HTTP; o token autentica, mas não cifra. Fora de
  casa continua sendo necessário Tailscale/VPN.
- O APK é debug; falta uma build release assinada para distribuição.
- O IP do PC pode mudar por DHCP e exigir atualização da URL no app.
- A conexão por USB depende de tethering ativo e do cabo.
- Tailscale e acesso remoto ainda não foram validados.
