# Fase 9 — endurecimento (parcial)

## Entrega

- Testes para validação de argumentos, recusa de esquemas com extras, bloqueio
  de `file://` e URLs com credenciais, confirmação de ações, trilha de auditoria
  e Bearer token em HTTP/WebSocket. Mensagens de chat têm limite de 12000
  caracteres em HTTP e WebSocket; requisições HTTP têm limite global de 26 MiB,
  inclusive quando o corpo chega em chunks. Frames WebSocket têm teto de 64 KiB
  no app e no servidor Uvicorn iniciado pelo script de desenvolvimento.
- O backend recusa bind fora de loopback sem `CHAT_API_TOKEN` (mínimo 32
  caracteres); o app guarda o token no cofre Secret Service do sistema, não em
  preferências sem proteção.
- Teste de integração Linux gravou, leu e removeu uma credencial temporária no
  Secret Service real via D-Bus.
- O agente registra e rejeita `command_id` já processados em
  `journal.jsonl.commands.sqlite3` (modo 600); a primeira utilização importa
  IDs históricos do journal linha a linha. A deduplicação persiste após
  reinício sem manter o conjunto em RAM.
- A repetição do mesmo comando de status foi testada depois de reiniciar o
  serviço; a segunda chamada recebeu HTTP 409 e não executou outra ação.
- Limites operacionais e pré-requisitos de acesso remoto registrados em
  `docs/SEGURANCA.md`.
- mTLS local entre backend e daemon foi ativado com certificados privados em
  `~/.config/chat-agent/tls`; o cliente Python recebeu status válido e o
  handshake sem certificado de cliente foi recusado.
- Limite configurável por IP (`CHAT_RATE_LIMIT_PER_MINUTE`, padrão 120) protege
  HTTP e novas conexões WebSocket; HTTP retorna 429 com `Retry-After` e o
  WebSocket recusa conexões excedentes com código 1013. O estado de até 4096
  origens é mantido por processo, com limpeza de entradas expiradas.
- Cada conexão WebSocket também tem limite próprio de frames recebidos
  (`CHAT_WS_MESSAGE_RATE_PER_MINUTE`, padrão 30/min). Ao exceder, o servidor
  envia um evento de erro, fecha com código 1013 e não processa o frame.
- O daemon limita endpoints a 60 requisições por minuto por IP, incluindo
  tentativas não autenticadas, responde 429 com `Retry-After` e limita a
  memória do histórico a 4096 origens.
- O daemon rejeita corpos acima de 64 KiB, incluindo requisições sem
  `Content-Length`; `params` aceita no máximo uma chave curta e um valor de até
  64 caracteres.
- Aplicativos abertos pelo daemon não recebem variáveis `CHAT_AGENT_*` no
  ambiente herdado, evitando expor o token Bearer e caminhos de material mTLS
  aos processos gráficos.
- Mantido bind de loopback como padrão; Tailscale continua desativado.
- O backend tem 33 testes aprovados, o daemon 9; Flutter analyze, 3 testes de
  widget, integração do keyring e build Linux release passaram. O binário
  iniciou no desktop sem depender de `libmpv`. Testes cobrem fluxos locais, não
  provam isolamento remoto.

## Pendências

Configurar identidade Tailscale e revisar as superfícies de rede continuam
necessários antes de habilitar acesso remoto. O usuário ainda precisa inserir
no app o mesmo token configurado no backend. Os limitadores são locais ao
processo; o limite de frames por conexão WebSocket agora existe, mas não há
limite de conexões simultâneas por origem.
