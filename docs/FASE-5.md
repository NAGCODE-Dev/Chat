# Fase 5 — ferramentas com confirmação

## Entrega

- Contrato `Tool` com argumentos validados por Pydantic e campos extras recusados.
- O provider Ollama transmite texto e chamadas de função; providers antigos
  continuam compatíveis pelo método padrão `stream_events`.
- O backend executa até quatro rodadas de ferramentas por turno e guarda
  chamadas/resultados no histórico SQLite.
- `wishlist_query` é somente leitura. `wishlist_update`, `web_search` e
  `open_url` exigem confirmação no app antes da execução.
- As execuções são registradas em `audit_log`, com argumentos, resultado e
  indicação de confirmação. Busca desabilitada até configurar
  `CHAT_WEB_SEARCH_URL`; a consulta é enviada somente depois da aprovação.
- URLs aceitam apenas HTTP/HTTPS, sem credenciais embutidas.

## Configuração da busca

Configure `CHAT_WEB_SEARCH_URL` com a URL base de uma instância SearXNG
administrada por você. A ferramenta chama `/search` com `format=json` e não
usa um serviço público como fallback.

## Limite desta entrega

Ruff e os testes do backend passaram. O Qwen local foi verificado em duas
operações isoladas: consulta real à wishlist e inclusão de um item em banco
temporário após o evento de confirmação; ambos geraram resultado/auditoria.
O widget Flutter passou por analyze/test/build. Ainda falta validar a interação
visual da caixa de confirmação com o app conectado ao backend.
