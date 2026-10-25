# Fase 6 — agente Ubuntu (MVP)

## Entrega

- API do agente com autenticação Bearer obrigatória em todas as rotas.
- Recusa iniciar sem `CHAT_AGENT_TOKEN` com pelo menos 32 caracteres.
- Bind padrão local; a exposição em Tailscale precisa ser configurada pelo
  operador, mantendo o token secreto.
- Allowlist fechada para `browser`, `files`, `terminal` e `editor`. O modelo
  nunca envia shell, executável ou argumentos livres.
- Abertura de app exige `requires_confirmation=true`; o backend só envia esse
  sinal após a confirmação no app. O journal JSONL registra comando, parâmetros,
  resultado e identificador em `~/.local/share/chat-agent/journal.jsonl`.
- A ferramenta `agent_exec` só é exposta ao modelo quando `CHAT_AGENT_URL` e
  `CHAT_AGENT_TOKEN` estão configurados no backend.
- `device_status` consulta o endpoint autenticado sem pedir confirmação; não é
  necessário enviar uma solicitação de status como ação de controle.

## Execução manual

```bash
cd agent
python -m venv .venv
.venv/bin/pip install -e .
export CHAT_AGENT_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(36))')"
.venv/bin/uvicorn ubuntu_agent.server:app --host 127.0.0.1 --port 8765
```

Configure no backend `CHAT_AGENT_URL=http://127.0.0.1:8765` e o mesmo token.
Não configure o host em `0.0.0.0` nem exponha a porta diretamente à internet.

Para instalar como serviço `systemd --user`, execute
`agent/install_user_service.sh`. Ele cria um venv do agente, grava o token em
arquivo modo 600, habilita o serviço e mantém o bind em `127.0.0.1`. Remova com
`agent/uninstall_user_service.sh`; o token é preservado. `scripts/dev_run.sh`
reutiliza esse arquivo para conectar o backend ao agente local.

## Estado neste computador

O serviço `chat-agent.service` está habilitado e ativo em loopback. O backend
local iniciou com `agent_configured=true`, e `device_status` consultou o daemon
com sucesso. O Qwen pediu `agent_exec` para abrir o editor, a confirmação foi
validada e o editor foi iniciado; o journal registrou sucesso. O alias de
navegador falhou corretamente: Firefox está empacotado como Snap, mas o Snap
Firefox não está instalado. A tentativa e sua correção também estão no journal.

## Limite desta fase

O agente implementa abertura de aplicativos e, desde a Fase 10, leitura de
pastas e arquivos dentro de raízes autorizadas. Escrita, movimentação e
exclusão de arquivos continuam fora do escopo, assim como execução de comandos
arbitrários. A integração Tailscale segue pendente. Ruff e os testes do daemon
passaram. O agente só retorna sucesso quando o launcher não falha imediatamente.
