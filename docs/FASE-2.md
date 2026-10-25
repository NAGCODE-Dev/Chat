# Fase 2 — memória persistente

## O que está entregue

- Memórias ficam no SQLite, separadas do histórico e do provedor de modelo.
- A API `/api/memories` lista, cria, atualiza e apaga memórias; tipos aceitos:
  `personal`, `preference`, `project` e `fact`.
- `/api/memories/search?q=...` consulta o índice FTS5.
- A conversa recupera até cinco memórias lexicalmente relacionadas à mensagem
  atual e inclui os fatos em contexto separado, identificando-os como dados,
  não como instruções.
- O salvamento automático só ocorre quando a mensagem começa com um pedido
  explícito como “lembre que”, “guarde na memória” ou “não esqueça”. Outros
  fatos ditos casualmente não são persistidos automaticamente.
- A exclusão pela API remove o registro e o índice FTS5 correspondente.

## Limites atuais

A busca é lexical e depende de palavras em comum; ainda não interpreta
sinônimos. Memórias podem também ser criadas diretamente pela API. O endpoint
fica disponível apenas no backend local por padrão, que escuta em `127.0.0.1`.
