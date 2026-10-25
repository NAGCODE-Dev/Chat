# Execução local

O script `scripts/dev_run.sh` inicia o backend em `127.0.0.1:8750` por padrão,
usando Ollama/Qwen e os modelos locais de voz quando estão instalados.
Configure `CHAT_PROVIDER` e `CHAT_MODEL` para trocar o provider e o modelo.

Neste ambiente, `~/.config/chat/backend.env` (modo 600) define
`CHAT_HOST=0.0.0.0`, `CHAT_PORT=8750` e um `CHAT_API_TOKEN`. O token ativa
autenticação Bearer para HTTP e WebSocket. O app do desktop guarda o token no
cofre Secret Service/keyring; o app Android guarda no cofre do aparelho.
Qualquer bind fora de loopback recusa iniciar sem token.

### Modelo maior sob demanda

O backend pode alternar entre um modelo padrão e um modelo maior conforme a
memória disponível. A configuração fica no mesmo `backend.env`:

```bash
CHAT_MODEL_AUTO=1
CHAT_MODEL=qwen2.5:3b-instruct-q4_K_M
CHAT_MODEL_LARGE=qwen3:4b-instruct-2507-q4_K_M
CHAT_MODEL_AUTO_MIN_FREE_MB=4600
CHAT_MODEL_AUTO_KEEP_FREE_MB=1024
CHAT_MODEL_KEEP_ALIVE=5m
CHAT_MODEL_LARGE_KEEP_ALIVE=2m
```

O modelo maior só é carregado quando `MemAvailable` atinge o mínimo, o swap
está livre e não há pressão de memória. Depois de carregado, ele é mantido até
a memória cair abaixo de `CHAT_MODEL_AUTO_KEEP_FREE_MB`; nesse caso o backend o
descarrega e volta ao modelo padrão. O endpoint `/health` mostra
`model_auto` e `model_large`.

## Backend como serviço

O backend está habilitado como serviço de usuário e sobe no login:

```bash
systemctl --user status chat-backend.service
systemctl --user restart chat-backend.service
journalctl --user -u chat-backend.service -f
```

Se preferir rodar manualmente, pare o serviço antes para não ocupar a porta:

```bash
systemctl --user stop chat-backend.service
scripts/dev_run.sh
```

Com Flutter instalado, compile e execute:

```bash
cd app_flutter
flutter build linux
./build/linux/x64/release/bundle/chat_app
```

O banco padrão é `~/.local/share/chat/chat.db`. A migração para esquema v3
(histórico, memória, FTS5 e embeddings) é aplicada automaticamente na
inicialização. O backup anterior à migração para v2 está em
`~/.local/share/chat/chat.db-before-phase-continuation-20261024`.

No Linux, `flutter_secure_storage_linux_secret_service` usa Secret Service via
D-Bus. A gravação, leitura e remoção de uma credencial temporária foram
verificadas no keyring desta sessão.

Se o agente foi instalado com `agent/install_user_service.sh`, o script de
execução carrega o token local modo 600 e conecta ao daemon em
`http://127.0.0.1:8765`.

Para liberar acesso a arquivos pelo agente, acrescente as raízes ao arquivo
`~/.config/chat-agent/agent.env` (modo 600), com caminhos absolutos. Neste
ambiente, leitura e escrita estão liberadas apenas em `~/Documentos/Chat`:

```bash
CHAT_AGENT_ALLOWED_DIRS=/home/nikolas/Documentos/Chat
CHAT_AGENT_WRITE_DIRS=/home/nikolas/Documentos/Chat
```

Depois reinicie o serviço:

```bash
systemctl --user restart chat-agent.service
```

A leitura é somente de texto UTF-8 até 64 KiB, exige confirmação no app e
recusa caminhos fora das raízes, inclusive por `..` ou link simbólico. A
escrita aceita até 32 KiB por operação, grava de forma atômica e limita o
arquivo resultante a 64 KiB; a pasta de destino precisa existir. O conteúdo não
é gravado no journal. A pasta `~/Documentos/Chat` foi criada com modo 700 e
configurada no serviço real.

## Conversa contínua e modo relógio

No app, o ícone de ouvido abre as preferências de conversa contínua. Ative a
escuta automática e escolha a palavra de ativação (padrão `chat`). Depois da
primeira fala com a palavra, a conversa segue sem repeti-la até o modo ser
desligado.

O ícone de relógio abre o modo de quarto. Ao ativar, o app passa a mostrar hora
gigante e data por extenso, mantém a tela ligada e entra em hibernação após o
tempo escolhido (padrão: 5 minutos). Em hibernação o microfone e os timers de
conversa param; toque na tela ou pressione qualquer tecla para voltar.

## Memória semântica (opcional)

O FTS5 funciona sem configuração. O script `scripts/dev_run.sh` já habilita a
busca semântica com Ollama e `bge-m3`. Se iniciar o backend manualmente,
exporte as variáveis:

```bash
ollama pull bge-m3
export CHAT_EMBEDDING_PROVIDER=ollama
export CHAT_EMBEDDING_MODEL=bge-m3
export CHAT_EMBEDDING_MIN_SIMILARITY=0.6  # 0 desliga o corte
```

Depois indexe as memórias existentes. No app, abra **Memórias** e use
**Indexar**; ou use a API:

```bash
curl -X POST http://127.0.0.1:8750/api/memories/embeddings/reindex
curl http://127.0.0.1:8750/api/memories/embeddings/status
```

Se `CHAT_API_TOKEN` estiver definido, envie o header `Authorization: Bearer`.
Sem modelo instalado ou com o Ollama fora do ar, a busca lexical continua
respondendo. A indexação não é automática: memórias novas entram na via
semântica no próximo `reindex`. Neste ambiente o `bge-m3` já está baixado e a
memória existente foi indexada com 1024 dimensões.

## Celular Android

O app Android conecta ao backend por Wi-Fi (`http://192.168.0.126:8750`) ou
USB (`http://10.22.184.11:8750`). Gere o APK com:

```bash
cd app_flutter
flutter build apk --debug
```

O arquivo fica em `app_flutter/build/app/outputs/flutter-apk/app-debug.apk`.
No app, abra a engrenagem **Configurar conexão**, informe a URL e o token de
`~/.config/chat/backend.env`. O passo a passo completo, incluindo troca de
token e verificação com `curl`, está em
[`CONEXAO-CELULAR.md`](CONEXAO-CELULAR.md).

Para rodar os testes de cada componente:

```bash
backend/.venv/bin/python -m pytest backend/tests
agent/.venv/bin/pip install -e 'agent[dev]'
agent/.venv/bin/python -m pytest agent/tests
cd app_flutter && flutter analyze && flutter test
```
