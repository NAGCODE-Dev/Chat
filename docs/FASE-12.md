# Fase 12 — memória semântica com embeddings

## Entrega

- Novo contrato `EmbeddingProvider` em `backend/chat/memory/embeddings.py`,
  independente do `ModelProvider` e do banco.
- Implementação `OllamaEmbeddingProvider`, que usa o endpoint local
  `/api/embed` e valida quantidade, dimensão, valores finitos e JSON.
- Migração SQLite v3 com a tabela `memory_embeddings` (vetor `float32` em
  BLOB, modelo, dimensão, hash do conteúdo e data). A exclusão da memória
  remove o embedding por chave estrangeira.
- `MemoryStore.recall` executa sempre a busca lexical no FTS5 e, quando há
  embeddings indexados, combina os resultados com Reciprocal Rank Fusion
  (RRF). O FTS5 continua sendo o fallback obrigatório.
- Se o provedor estiver ausente, o modelo não estiver instalado, a consulta
  falhar ou não houver vetores, a busca lexical responde normalmente.
- Quando não existe nenhum vetor indexado para o modelo atual, a consulta nem
  chama o provedor: a via lexical responde na hora, sem esperar timeout.
- `CHAT_EMBEDDING_MIN_SIMILARITY` descarta resultados semânticos fracos antes
  do RRF. O valor `0` desliga o corte; o `dev_run.sh` usa `0.6` com `bge-m3`.
  O status informa o corte em `min_similarity`.
- Memórias alteradas têm o embedding invalidado. `reindex` gera embeddings
  apenas para memórias novas ou alteradas, salvo `force=true`.
- Endpoints novos:
  - `GET /api/memories/embeddings/status`
  - `POST /api/memories/embeddings/reindex?force=false`
- O `MemoryStore` é compartilhado entre o serviço de chat e as rotas, para
  que a indexação e a busca usem o mesmo provedor.

## Configuração

O recurso começa desligado na configuração base. O script
`scripts/dev_run.sh` habilita Ollama com `bge-m3` por padrão. Para habilitar
manualmente com Ollama:

```bash
ollama pull bge-m3
```

No ambiente do backend:

```bash
export CHAT_EMBEDDING_PROVIDER=ollama
export CHAT_EMBEDDING_MODEL=bge-m3
# opcional: CHAT_EMBEDDING_BASE_URL=http://127.0.0.1:11434
# opcional: CHAT_EMBEDDING_TIMEOUT_SECONDS=10
# opcional: CHAT_EMBEDDING_MIN_SIMILARITY=0.6  (0 desliga)
```

Reinicie o backend e indexe as memórias existentes. No app, abra **Memórias** e
use **Indexar**; o cartão mostra quantas estão indexadas e quantas estão
pendentes. Também é possível usar a API:

```bash
curl -X POST http://127.0.0.1:8750/api/memories/embeddings/reindex
curl http://127.0.0.1:8750/api/memories/embeddings/status
```

Se `CHAT_API_TOKEN` estiver configurado, inclua
`-H "Authorization: Bearer <token>"` nas chamadas.

O status informa `enabled`, `provider`, `model`, `available`, `total`,
`indexed`, `stale`, `pending`, `dimensions` e `min_similarity`.
`available=false` normalmente significa que o modelo ainda não foi baixado no
Ollama.

## Validação

- 44 testes do backend, incluindo:
  - recall semântico de uma memória sem termo lexical em comum;
  - fallback lexical com provedor ausente e com provedor que falha;
  - nenhuma chamada ao provedor quando ainda não há vetores indexados;
  - corte de similaridade descartando memórias fracamente relacionadas;
  - reindexação incremental, invalidação ao editar e remoção em cascata;
  - parsing da resposta do Ollama e recusa de resposta malformada;
  - status e reindexação pelas rotas, incluindo `409` sem provedor.
- Migração v3 idempotente e `ruff` limpo.

## Limites

- A similaridade é calculada em Python, com custo linear no número de
  memórias indexadas. Para uso pessoal é suficiente; uma etapa futura pode
  usar `sqlite-vec` ou um índice ANN.
- Cada memória guarda um embedding do modelo atual. Trocar de modelo exige
  reindexação.
- A reindexação é manual. Memórias novas só entram na via semântica depois de
  um `reindex` (a via lexical funciona imediatamente).
- O modelo `bge-m3` foi escolhido para este ambiente e é habilitado pelo
  `scripts/dev_run.sh`; a configuração base continua desligada para não exigir
  o modelo em qualquer ambiente.
- Embeddings são gerados localmente pelo Ollama; nenhum conteúdo de memória é
  enviado a serviço externo.
