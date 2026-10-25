# Segurança e limites operacionais

## Estado atual

- O backend inicia em `127.0.0.1` por padrão. Neste ambiente, o serviço
  `chat-backend.service` usa `CHAT_HOST=0.0.0.0` com token, para o app Android
  na rede local. O token fica em `~/.config/chat/backend.env` (modo 600).
- Se `CHAT_API_TOKEN` for definido, HTTP e WebSocket exigem Bearer token. O
  segredo precisa ter ao menos 32 caracteres e o app guarda o valor no cofre
  Secret Service/keyring do sistema. No Linux, o app requer um serviço Secret
  Service ativo; gravação, leitura e remoção foram verificadas no keyring
  GNOME desta sessão. Qualquer bind fora de loopback exige `CHAT_API_TOKEN`.
- No celular, o token fica no cofre local do Android. A conexão usa HTTP na
  rede de casa ou no USB: o token autentica, mas não cifra o tráfego. Não
  exponha a porta `8750` à internet; para acesso fora de casa, use Tailscale ou
  outra VPN. O manifesto Android permite cleartext HTTP apenas para falar com
  o backend local.
- O agente exige Bearer token de pelo menos 32 caracteres, usa allowlist fixa,
  executa sem shell e grava `journal.jsonl` com permissão 600 em diretório 700.
- Cada `command_id` é reivindicado uma única vez em
  `journal.jsonl.commands.sqlite3`, com chave única e modo 600. Na primeira
  execução, IDs históricos são migrados do journal protegido; a deduplicação
  continua após reinício.
- Backend limita a taxa de HTTP e de novas conexões WebSocket por IP, com
  `CHAT_RATE_LIMIT_PER_MINUTE` (padrão 120). O limite é mantido em memória por
  processo, com teto de 4096 origens e limpeza de entradas expiradas. Cada
  conexão WebSocket tem ainda um limite próprio de frames recebidos
  (`CHAT_WS_MESSAGE_RATE_PER_MINUTE`, padrão 30/min); ao exceder, o servidor
  envia erro, fecha com código 1013 e descarta o frame.
- O daemon limita também a 60 requisições por minuto por IP, incluindo
  tentativas não autenticadas, em memória por processo e até 4096 origens.
- Corpos HTTP do daemon são limitados a 128 KiB inclusive sem `Content-Length`;
  ações de arquivo aceitam somente `path` e, quando aplicável, `content`. O
  conteúdo é limitado a 32 KiB por operação e o caminho a 1024 caracteres;
  demais comandos aceitam apenas um par chave/valor de até 2048 caracteres.
- O acesso a arquivos usa duas listas de raízes explícitas:
  `CHAT_AGENT_ALLOWED_DIRS` para leitura e `CHAT_AGENT_WRITE_DIRS` para
  escrita. Uma raiz de leitura não autoriza gravação. Caminhos são resolvidos
  antes da checagem; `..`, links simbólicos e destinos fora das raízes são
  recusados. Listagens limitam-se a 200 entradas; leituras, a 64 KiB de texto
  UTF-8. Arquivos binários são recusados.
- Escritas usam arquivo temporário no mesmo diretório, `fsync` e `os.replace`,
  com limites de 32 KiB por operação e 64 KiB por arquivo resultante. O
  destino não pode ser link simbólico e a pasta pai precisa existir. Toda ação
  exige `requires_confirmation=true`. O journal registra caminho, status,
  tamanho e resumo, mas nunca o conteúdo lido ou escrito.
- Não há movimentação, cópia ou exclusão de arquivos. Essas operações exigem
  um contrato de permissões próprio e não estão expostas.
- Mensagens de chat têm limite de 12000 caracteres antes de entrar no fluxo de
  inferência, tanto no endpoint HTTP quanto no WebSocket.
- Corpos HTTP do backend são limitados globalmente a 26 MiB, incluindo corpos
  chunked; o limite acomoda o upload de áudio de até 25 MiB.
- Frames do chat WebSocket são limitados a 64 KiB na rota e no Uvicorn iniciado
  por `scripts/dev_run.sh`.
- O agente recusa comandos de abertura sem `requires_confirmation=true`.
  O backend só define esse campo depois da resposta afirmativa do app.
- Processos iniciados pela allowlist não herdam variáveis `CHAT_AGENT_*` do
  daemon, que podem conter o token e caminhos de arquivos mTLS.
- Ferramentas do modelo têm schemas fechados; abrir URL, buscar na web, alterar
  a lista de desejos, ativar dispositivos e controlar apps exigem confirmação.
- Conteúdo retornado por ferramentas é marcado como dado externo no histórico
  e no contexto do modelo.
- O pacote WOL não confirma que o dispositivo ligou; só informa que o datagrama
  foi entregue ao socket local.
- A conversa contínua só mantém o microfone aberto enquanto o modo está ativo.
  Na hibernação do modo relógio, microfone, fala, rede e timers de conversa
  param; o despertar é por toque ou tecla. Não há escuta da palavra de ativação
  durante a hibernação, por decisão de consumo.
- Embeddings são gerados localmente pelo Ollama. O conteúdo das memórias não é
  enviado a serviços externos. Os endpoints de status e reindexação seguem a
  mesma autenticação Bearer do restante da API.
- O journal do agente não registra conteúdo de arquivo; o banco de memória
  guarda o texto apenas localmente, em `~/.local/share/chat/chat.db`.

## Ainda não liberado para uso remoto

Tailscale não está instalado neste computador. mTLS local está ativo entre
backend e agente, com CA privada em `~/.config/chat-agent/tls`; o status foi
verificado pelo cliente e o daemon recusou conexão sem certificado de cliente.
Não exponha a porta à rede pública. O token da API protege o app quando configurado,
mas não substitui HTTPS/Tailscale em redes não confiáveis. A API local confia
que chamadas vêm do próprio usuário; o campo `confirmed` do endpoint WOL sozinho
não é autenticação.

Antes de habilitar acesso remoto, provisionar o token no app e configurar
Tailscale ou TLS, limites de taxa e revisão de logs. Acesso remoto não foi
validado neste ambiente. A leitura e a escrita de arquivos pelo agente também
não foram liberadas para uso remoto; mantenha as raízes autorizadas restritas
e revise o journal antes de expor o daemon além do loopback.
