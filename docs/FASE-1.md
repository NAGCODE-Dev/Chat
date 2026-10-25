# Fase 1 — conversa por texto

## O que está entregue

- `POST /api/chat` recebe `message` e, opcionalmente, `conversation_id`; devolve
  a resposta completa e os metadados do turno.
- `GET /api/conversations` lista conversas; `GET /api/conversations/{id}/messages`
  retorna o histórico; `DELETE /api/conversations/{id}` remove a conversa.
- `WS /api/ws/chat` recebe um JSON com os mesmos campos do POST e envia eventos
  JSON `token` durante a geração, seguidos por `done` com IDs e metadados.
- Mensagens de usuário e assistente são persistidas no SQLite. Conversas
  inexistentes retornam HTTP 404 (ou evento `error` no WebSocket).
- `fake` permite desenvolvimento sem serviço de inferência. `ollama` usa a API
  local e ambos implementam o mesmo contrato.
- O benchmark local de Qwen2.5 3B, Llama 3.2 3B e Gemma 3 4B está registrado em
  [`benchmark-modelos-2026-10-24.md`](benchmark-modelos-2026-10-24.md), com
  método reproduzível em `scripts/benchmark_models.py`. Qwen permanece como
  padrão porque foi o único que gerou a chamada válida da ferramenta usada no
  teste.

## Executar localmente

```bash
cd backend
source .venv/bin/activate
uvicorn chat.api.main:app --host 127.0.0.1 --port 8750
```

Por padrão, a aplicação usa o provedor `fake` e grava o banco em
`~/.local/share/chat/chat.db`. Para selecionar Ollama, veja
[`TROCAR-MODELO.md`](TROCAR-MODELO.md).

## Contrato mínimo de streaming

Cliente envia uma mensagem ao conectar em `/api/ws/chat`:

```json
{"message":"Oi"}
```

Durante a resposta:

```json
{"type":"token","content":"Olá"}
```

Ao terminar, recebe um evento `done` com `conversation_id`, IDs das mensagens,
provedor, modelo e latência. O cliente deve concatenar os tokens; o histórico
persistido permanece a fonte para reabrir conversas.
