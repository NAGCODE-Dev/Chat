# Como trocar o modelo

O backend depende apenas do contrato `ModelProvider`, definido em
`backend/chat/providers/base.py`. O provedor ativo e o nome do modelo são
configuráveis por variáveis de ambiente, sem alterar o serviço de conversa.

## Usar Ollama

Inicie o Ollama e baixe um modelo compatível com a API de chat. Depois, no
diretório `backend`, configure:

```bash
export CHAT_PROVIDER=ollama
export CHAT_MODEL=qwen2.5:3b
export CHAT_PROVIDER_BASE_URL=http://127.0.0.1:11434
uvicorn chat.api.main:app --host 127.0.0.1 --port 8750
```

`CHAT_PROVIDER` aceita `fake` (padrão de desenvolvimento) ou `ollama`.
`CHAT_MODEL` é encaminhado ao provedor ativo. `CHAT_PROVIDER_BASE_URL` permite
apontar para outra instância local compatível com a API nativa do Ollama.

## Modelo maior só quando há memória sobrando

O backend pode manter um modelo padrão (menor) e usar um segundo modelo
(maior) apenas quando o notebook tem folga. A decisão é feita a cada turno,
com histerese para não ficar trocando de modelo:

```bash
export CHAT_MODEL=qwen2.5:3b-instruct-q4_K_M
export CHAT_MODEL_LARGE=qwen3:4b-instruct-2507-q4_K_M
export CHAT_MODEL_AUTO=1
export CHAT_MODEL_AUTO_MIN_FREE_MB=4600
export CHAT_MODEL_AUTO_KEEP_FREE_MB=1024
export CHAT_MODEL_KEEP_ALIVE=5m
export CHAT_MODEL_LARGE_KEEP_ALIVE=2m
```

- `CHAT_MODEL_AUTO_MIN_FREE_MB` é o mínimo de `MemAvailable` para *carregar*
  o modelo maior. Inclua o tamanho do modelo, o embedding e uma folga.
- `CHAT_MODEL_AUTO_KEEP_FREE_MB` é o mínimo para *manter* o modelo maior já
  carregado. Se a memória cair abaixo disso, o backend descarrega o modelo
  maior e volta ao padrão.
- A checagem também recusa o modelo maior quando o swap livre está abaixo de
  256 MiB ou quando o PSI de memória (`/proc/pressure/memory`) está alto.
- `CHAT_MODEL_LARGE_KEEP_ALIVE` controla por quanto tempo o Ollama mantém o
  modelo maior após o último turno. Um valor curto devolve a RAM quando você
  para de conversar.

Em um notebook de 16 GiB, um modelo 7B Q4 (~4,7 GB) não cabe com folga ao lado
do desktop e do embedding; o modo automático deve ser usado com um modelo que
caiba no orçamento, como o Qwen3 4B Q4 (~2,5 GB). O endpoint `/health` expõe
`model_auto` e `model_large` para conferir a configuração.

Neste ambiente o modo automático está **desligado** (`CHAT_MODEL_AUTO=0`). O
Qwen3 4B foi baixado e testado, mas respondeu a ~3,7–4,5 tokens/s contra
~6,3–7,4 tokens/s do Qwen2.5 3B, com latências de 23–39 s por resposta curta.
Veja [`benchmark-modelos-2026-10-24.md`](benchmark-modelos-2026-10-24.md).
Para priorizar qualidade em vez de velocidade, ative manualmente:

```bash
# em ~/.config/chat/backend.env
CHAT_MODEL_AUTO=1
```

Depois reinicie `chat-backend.service` e confira `model_auto` em `/health`.

## Adicionar outro provedor

1. Implemente `chat`, `stream`, `list_models` e `health` em uma classe que
   herde de `ModelProvider`.
2. Registre uma fábrica em `chat/api/main.py` usando `register`.
3. Escolha o novo nome em `CHAT_PROVIDER` e informe seu modelo em `CHAT_MODEL`.

O `ChatService` recebe apenas `ModelProvider`; histórico e rotas não importam
nem conhecem classes concretas de provedores.
