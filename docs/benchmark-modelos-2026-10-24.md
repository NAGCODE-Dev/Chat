# Benchmark dos modelos locais

## Método

Executado em 24/10/2026 contra o Ollama local 0.40.2. Os modelos foram
avaliados sequencialmente, com uma chamada curta para aquecimento e o mesmo
prompt, semente 42 e temperatura 0. A velocidade usa `eval_count` e
`eval_duration` informados pelo Ollama; as latências abaixo são das chamadas
com o modelo já carregado. O script também registra os tempos de carga e os
resultados completos em [benchmark-modelos-2026-10-24.json](benchmark-modelos-2026-10-24.json).

Os casos testaram uma resposta curta em português (17 × 23) e uma chamada
`wishlist_update` para adicionar “teclado mecânico”. As chamadas foram somente
inspecionadas; nenhuma alteração foi executada. O uso foi CPU, com 16 GiB de
RAM instalada.

## Resultados

| Modelo | Carga inicial | Resposta: latência / tokens/s | Resultado da conta | Ferramenta |
|---|---:|---:|---|---|
| Qwen2.5 3B Q4 | 8,09 s | 8,44 s / 8,37 | Correto (391) | Chamada válida: `action=add`, título correto |
| Llama 3.2 3B Q4 | 8,00 s | 10,03 s / 8,32 | Correto (391) | Inválida para a ferramenta: título veio nulo e o texto foi colocado em `notes` |
| Gemma 3 4B Q4 | 13,33 s | 11,36 s / 6,84 | Correto (391) | Ollama respondeu HTTP 400: modelo não oferece suporte a ferramentas |

## Segunda rodada: Qwen3 4B Instruct 2507

O `qwen3:4b-instruct-2507-q4_K_M` foi baixado e comparado ao Qwen2.5 3B com
o mesmo script, incluindo um caso de raciocínio curto:

| Modelo | Resposta (17 × 23) | Raciocínio (céu azul) | Chamada de ferramenta |
|---|---:|---:|---:|
| Qwen2.5 3B Q4 | 18,6 s / 7,15 tok/s | 9,5 s / 7,41 tok/s | 15,7 s / 6,29 tok/s, chamada válida |
| Qwen3 4B Q4 | 38,1 s / 3,86 tok/s | 23,0 s / 4,54 tok/s | 38,9 s / 3,69 tok/s, chamada válida |

O Qwen3 4B respondeu com mais detalhe (por exemplo, mostrou a decomposição
`17×20 + 17×3`), mas ficou cerca de duas vezes mais lento na CPU. Para uma
conversa por voz, 38 s por resposta curta é impraticável. O modelo também
ocupa ~2,5 GB e reduz a folga de RAM durante o uso.

**Decisão:** manter `qwen2.5:3b-instruct-q4_K_M` como padrão e deixar
`CHAT_MODEL_AUTO=0`. O Qwen3 4B permanece instalado para testes manuais ou
para quem preferir qualidade a latência; para ativá-lo, veja
[`TROCAR-MODELO.md`](TROCAR-MODELO.md).

## Decisão

Manter `qwen2.5:3b-instruct-q4_K_M` como padrão. Neste teste, ele respondeu
corretamente e foi o único que produziu a chamada de ferramenta esperada. A
vantagem é relevante para este app, que usa ferramentas com confirmação.

Este foi um ensaio local pequeno, com uma amostra por caso; os tempos podem
variar com a carga do sistema. A escolha não é uma comparação estatística de
qualidade geral.
