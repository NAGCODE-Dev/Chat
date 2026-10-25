# Chat — Arquitetura do Assistente Pessoal Local

> Assistente pessoal local-first, modular, por voz, com memória persistente,
> ferramentas e controle remoto do notebook Ubuntu.

Status: **Fases 0–13 locais entregues; Fase 7 WOL local sem Tailscale; Fase 8 MVP; Fase 9 local parcial (mTLS agente, token no keyring e rate limit implementados); Fases 10–13 entregues (arquivos, conversa contínua, relógio, embeddings, assistente Android e Meu Dinheiro local)**
Data: 2026-10-24

---

## 1. Visão geral da arquitetura

O sistema é dividido em **quatro componentes independentes**, cada um substituível
de forma isolada, comunicando-se apenas por contratos bem definidos.

```
┌─────────────────────────────┐        ┌──────────────────────────────────┐
│  1. APP FLUTTER             │        │  2. BACKEND (FastAPI)            │
│  (cliente de voz e UI)      │        │  ("cérebro" local)               │
│                             │        │                                  │
│  · Conversa                 │  HTTP  │  · Orquestração de conversas     │
│  · Microfone / áudio        │  + WS  │  · Memória (SQLite)              │
│  · Histórico, desejos,      │◄──────►│  · Roteamento p/ ModelProvider   │
│    dispositivos, memória    │        │  · Execução de ferramentas       │
│  · Config de modelo e voz   │        │  · Gestão de dispositivos / WoL  │
└─────────────────────────────┘        │  · STT / TTS (provedores)        │
                                       └───────┬───────────────┬──────────┘
                                               │               │
                    HTTP/WS autenticado (Tailscale)            │ API local
                                                               ▼
┌──────────────────────────────────┐        ┌──────────────────────────────┐
│  4. AGENTE UBUNTU (daemon)       │        │  3. PROVEDOR DE MODELO       │
│                                  │        │                              │
│  · Lista de comandos permitidos  │        │  Ollama / OpenAI-compat /    │
│  · Abrir apps e sites            │        │  qualquer backend de chat    │
│  · Ler e gravar arquivos         │        │  (interface ModelProvider)   │
│  · Confirmação explícita         │        │  Completamente intercambiável│
│  · Journal e auditoria           │        │                              │
└──────────────────────────────────┘        └──────────────────────────────┘
```

### Princípios

1. **Modelo desacoplado (obrigatório).** O backend nunca chama Ollama
   diretamente. Só conhece a interface `ModelProvider`. Trocar Ollama por
   llama.cpp-server, LM Studio, llama-server (ggml), ou um serviço externo
   autorizado = escrever/adicionar uma classe, mudar uma linha de config.
   Nada mais muda.
2. **Voz desacoplada.** `STTEngine` e `TTSEngine` são interfaces próprias,
   com implementações independentes (whisper.cpp, faster-whisper, Piper,
   TTS do sistema operacional como fallback).
3. **Memória independente do modelo.** Memória vive no SQLite, com
   recuperação própria. O histórico enviado ao LLM é *contexto*, não
   fonte de verdade. O FTS5 é a base lexical e o fallback obrigatório;
   embeddings são uma segunda via opcional, combinada por RRF.
4. **Backend como único ponto de orquestração.** O app Flutter não fala
   com o modelo, nem com o agente. Tudo passa pelo backend — isso
   centraliza permissões, auditoria e segurança.
5. **Ferramentas com permissão explícita.** O modelo *solicita* ferramentas
   via JSON estruturado; o backend valida, aplica regras de permissão e,
   quando necessário, exige confirmação do usuário antes de executar.
6. **Nada do agente exposto à internet pública.** Comunicação backend →
   agente pela rede Tailscale, com token de autenticação por dispositivo.

### Decisões de alto nível (com justificativa)

| Decisão | Escolha | Por quê |
|---|---|---|
| Linguagem do backend | Python 3.11+ / FastAPI | Ecossistema maduro para STT/TTS/modelos; você já especificou |
| Banco | SQLite (FTS5 + tabela estruturada + embeddings opcionais) | Local, zero administração, FTS5 cobre busca em pt-BR e continua como fallback |
| STT local | whisper.cpp (via binário) com interface; faster-whisper como alternativa | Melhor qualidade/CPU em pt; binário isolado = modular |
| TTS local | Piper (binário + voz pt_BR) | Leve, rápido em CPU, pt-BR nativo |
| Modelo inicial | Qwen2.5 3B Instruct Q4_K_M (ou Llama 3.2 3B / Gemma 3 4B) | Cabe em 16 GB sem GPU dedicada, suporta tool calling |
| Comunicação remota | Tailscale + HTTP bearer token | Rede privada, criptografia do WireGuard, zero exposição pública |
| Dispositivo do app | Notebook **e** celular Android | Voz processada no backend (funciona nos dois); fallback de TTS do SO no app |
| STT inicial | whisper.cpp (binário isolado) | Modular e de alta qualidade em pt-BR; faster-whisper documentado como alternativa |
| Escolha do modelo | Qwen2.5 3B mantido após benchmark local na Fase 1 | Resposta correta e única chamada de ferramenta válida entre os candidatos testados |
| Flutter ↔ Backend | REST (ações) + WebSocket (streaming de tokens e eventos) | Streaming de respostas e estados de tarefas |
| Agente | Daemon Python no notebook, systemd service | Controle fino de permissões e auditoria |

---

## 2. Limitações do hardware (Dell Inspiron 15 3520 — 16 GB, Intel integrada)

| Limitação | Impacto | Mitigação |
|---|---|---|
| Sem GPU dedicada | Sem CUDA/ROCm; Ollama roda em CPU (com Vulkan/iGPU parcial) | Modelos 3B Q4 (~1,8–2,2 GB): 8–15 tokens/s em CPU. Usar contexto curto (2–4k) |
| 16 GB RAM compartilhada | Modelo + STT + TTS + backend juntos | Orçamento de memória: modelo ~2,5 GB, whisper small int8 ~600 MB, Piper ~150 MB. Evitar 7B simultâneo com STT grande |
| Velocidade de geração | Respostas longas ficam lentas | Respostas concisas por padrão no prompt de sistema; streaming obrigatório p/ UX |
| Whisper em CPU | Transcrição ~0,3–1× tempo real com modelo small | Modelo `small` ou `base` int8, VAD para cortar silêncio |
| WoL no estado S3/S4/S5 | Notebooks nem sempre suportam magic packet desligados | Módulo WoL registra e testa cada estado; não assume suporte |
| Intel iGPU (Vulkan) | Aceleração possível mas instável conforme driver | Mantido como otimização futura, nunca como requisito |

**Candidatos avaliados no benchmark local da Fase 1:**

- `qwen2.5:3b-instruct-q4_K_M` — melhor equilíbrio geral, tool calling nativo.
- `llama3.2:3b-instruct-q4_K_M` — alternativa rápida.
- `gemma3:4b-it-q4_K_M` — melhor qualidade em pt-BR, um pouco mais lento.
- Embeddings (opcional): `nomic-embed-text` ou `multilingual-e5-small` via
  ONNX/Ollama, sempre com o FTS5 como fallback.

---

## 3. Estrutura de diretórios (monorepo)

```
chat/
├── docs/
│   ├── ARCHITECTURE.md              # este documento
│   ├── contracts.md                 # contratos entre módulos
│   ├── TROCAR-MODELO.md             # como trocar o LLM
│   ├── TROCAR-STT-TTS.md            # como trocar voz
│   └── SEGURANCA.md                 # modelo de permissões e auditoria
├── contracts/                       # contrato compartilhado entre componentes
│   ├── schemas/                     # JSON Schema (tools, agent, dispositivo)
│   │   ├── tool_call.schema.json
│   │   ├── agent_command.schema.json
│   │   └── device_state.schema.json
│   └── README.md
├── backend/
│   ├── pyproject.toml
│   ├── chat/                        # pacote principal
│   │   ├── core/
│   │   │   ├── config.py            # configuração (env + settings do SQLite)
│   │   │   ├── logging.py
│   │   │   └── events.py            # barramento de eventos interno
│   │   ├── providers/
│   │   │   ├── base.py              # interface ModelProvider (contrato)
│   │   │   ├── ollama_provider.py
│   │   │   ├── openai_compat_provider.py   # llama.cpp / LM Studio / vLLM / APIs externas
│   │   │   └── registry.py          # resolve provider a partir da config
│   │   ├── memory/
│   │   │   ├── db.py                # conexão/migrações SQLite (v4)
│   │   │   ├── conversations.py     # histórico
│   │   │   ├── personal.py          # memória estruturada + busca híbrida
│   │   │   └── embeddings.py        # EmbeddingProvider + Ollama /api/embed
│   │   ├── finance/
│   │   │   ├── store.py             # lançamentos, renda e investimentos
│   │   │   └── static/              # fork local do PWA Meu Dinheiro
│   │   ├── tools/
│   │   │   ├── base.py              # interface Tool + permissões
│   │   │   ├── wishlist.py          # lista de desejos
│   │   │   ├── web.py               # busca e abertura de URL
│   │   │   ├── phone.py             # ações no celular Android
│   │   │   ├── finance.py           # finance_add / finance_summary
│   │   │   ├── devices.py           # listagem e Wake-on-LAN
│   │   │   └── agent.py             # cliente do daemon Ubuntu
│   │   ├── voice/
│   │   │   ├── base.py              # interfaces STTEngine/TTSEngine
│   │   │   ├── whisper_cpp.py
│   │   │   └── piper_tts.py
│   │   ├── devices/
│   │   │   └── wol.py               # módulo Wake-on-LAN independente
│   │   ├── agent_orchestration/
│   │   │   └── chat_service.py      # pipeline: memória → modelo → ferramentas
│   │   └── api/
│   │       ├── main.py              # FastAPI app
│   │       ├── routes_chat.py
│   │       ├── routes_memory.py
│   │       ├── routes_wishlist.py
│   │       ├── routes_devices.py
│   │       ├── routes_voice.py
│   │       ├── routes_settings.py
│   │       ├── routes_finance.py
│   │       ├── state.py             # estado compartilhado (db, provider, memória)
│   │       └── ws.py                # WebSocket (streaming + eventos)
│   └── tests/
├── agent/
│   ├── pyproject.toml
│   ├── install_user_service.sh       # systemd --user + mTLS/token
│   ├── ubuntu_agent/
│   │   └── server.py                 # daemon, allowlist, permissões, journal
│   └── tests/
├── app_flutter/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart                 # conversa, voz, confirmações, relógio
│   │   └── core/
│   │       ├── backend_client.dart   # REST + WebSocket
│   │       ├── conversation_mode.dart# palavra de ativação e normalização
│   │       ├── clock_format.dart     # hora/data do relógio
│   │       ├── screen_awake.dart     # tela ligada (Linux/Android)
│   │       └── token_store.dart      # keyring
│   └── test/
└── scripts/
    ├── install_agent.sh             # systemd unit do agente
    └── dev_run.sh                   # sobe backend + agente em modo dev
```

---

## 4. Contratos entre módulos

### 4.1 `ModelProvider` (backend) — **contrato obrigatório do projeto**

```python
# backend/chat/providers/base.py
from abc import ABC, abstractmethod
from dataclasses import dataclass

@dataclass
class Message:
    role: str                      # "system" | "user" | "assistant" | "tool"
    content: str
    tool_call_id: str | None = None
    name: str | None = None

@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: dict               # JSON Schema

@dataclass
class ToolCall:
    id: str
    name: str
    arguments: dict

@dataclass
class ModelResponse:
    content: str
    tool_calls: list[ToolCall]     # vazio se resposta final
    finish_reason: str             # "stop" | "tool_calls" | "length"
    raw: dict | None = None        # metadados do provedor

@dataclass
class ModelInfo:
    id: str
    name: str
    context_window: int | None = None

class ModelProvider(ABC):
    """Interface ÚNICA entre a aplicação e qualquer LLM.
    Nenhum módulo fora de providers/ pode importar ollama ou openai."""

    @abstractmethod
    async def chat(self, messages: list[Message],
                   tools: list[ToolSpec] | None = None,
                   *, temperature: float = 0.7,
                   max_tokens: int | None = None) -> ModelResponse: ...

    @abstractmethod
    def stream(self, messages: list[Message],
               tools: list[ToolSpec] | None = None) -> "AsyncIterator[str] | AsyncIterator[ModelResponse]": ...

    @abstractmethod
    async def list_models(self) -> list[ModelInfo]: ...

    @abstractmethod
    async def health(self) -> bool: ...
```

**Implementações previstas:** `OllamaProvider`, `OpenAICompatProvider`
(cobre llama.cpp-server, LM Studio, vLLM e serviços externos autorizados).
A escolha e os parâmetros vivem em `settings` (config), nunca em código.

> Detalhe documentado em `docs/TROCAR-MODELO.md`.

### 4.2 STT e TTS (backend)

```python
class STTEngine(ABC):
    @abstractmethod
    async def transcribe(self, audio: bytes, sample_rate: int) -> str: ...
    @abstractmethod
    def interrupt(self) -> None: ...          # cancela transcrição em andamento

class TTSEngine(ABC):
    @abstractmethod
    async def synthesize(self, text: str) -> bytes: ...   # wav/pcm
    @abstractmethod
    def stop(self) -> None: ...               # interrupção da fala (barge-in)
```

Implementações: `WhisperCppSTT`, `FasterWhisperSTT` / `PiperTTS`.
O app Flutter também mantém um provedor de fallback: TTS do sistema
operacional, para funcionar quando o backend de voz não estiver disponível.

### 4.2.1 Embeddings de memória (backend)

```python
class EmbeddingProvider(ABC):
    name: str
    model: str

    @abstractmethod
    async def embed(self, texts: Sequence[str]) -> list[list[float]]: ...

    async def health(self) -> bool: ...
```

Implementação inicial: `OllamaEmbeddingProvider` (`/api/embed`). O vetor é
guardado como `float32` em BLOB, junto do modelo e do hash do conteúdo. A
busca combina FTS5 e similaridade de cosseno por RRF; o FTS5 é sempre
executado e nunca é substituído.

### 4.3 Ferramentas (backend)

```python
class Permission(str, Enum):
    SAFE      = "safe"        # executa direto (ex.: consultar desejos)
    CONFIRM   = "confirm"     # exige confirmação do usuário no app
    RESTRICTED = "restricted" # só com permissão previamente habilitada

class Tool(ABC):
    name: str
    description: str
    permission: Permission
    parameters: dict                     # JSON Schema (vira ToolSpec p/ o modelo)

    @abstractmethod
    async def run(self, args: dict) -> "ToolResult": ...
```

Fluxo: modelo devolve `tool_calls` → backend valida JSON contra o schema →
aplica `Permission` (pede confirmação via WebSocket se `CONFIRM`) → executa →
devolve resultado como mensagem `role="tool"` → modelo continua.
**O modelo nunca executa nada; só pede.**

Ferramentas iniciais: `wishlist_query`, `wishlist_update`,
`web_search`, `open_url`, `phone_action`, `finance_add`, `finance_summary`,
`device_status`, `agent_exec`.

### 4.4 Protocolo agente ↔ backend

- Transporte: HTTPS sobre Tailscale (IP 100.x.x.x), porta dedicada.
- Autenticação: token gerado no notebook, configurado no backend; header
  `Authorization: Bearer <token>`; opcionalmente mTLS na fase de endurecimento.
- Comandos (definidos em `contracts/schemas/agent_command.schema.json`):

```json
{
  "command_id": "uuid",
  "action": "open_app | open_url | run_allowed | file_read | file_write | status",
  "params": { },
  "requires_confirmation": false,
  "expires_at": "ISO-8601"
}
```

- Respostas: `ok | denied | needs_confirmation | failed`, com payload e
  `command_id` para rastrear no histórico e no log de auditoria.
- Endpoint `/status` informa conectividade e versão do agente.
- **Allowlist**: o agente só executa ações da sua tabela de comandos
  permitidos (ex.: `xdg-open`, `code`, `nautilus` com args validados).
  Ações destrutivas/administrativas (`apt`, `rm`, systemctl) exigem
  confirmação explícita registrada no journal.

### 4.5 App Flutter ↔ Backend

| Endpoint | Método | Função |
|---|---|---|
| `/api/chat` | POST | Envia mensagem; resposta via WS (`conversation:{id}`) |
| `/api/conversations` | GET/POST/DELETE | Histórico |
| `/api/memory` | GET/PUT/DELETE | Memória pessoal (visualizar/editar/excluir) |
| `/api/memories/search` | GET | Busca híbrida (FTS5 + embeddings, com fallback) |
| `/api/memories/embeddings/status` | GET | Estado da indexação semântica |
| `/api/memories/embeddings/reindex` | POST | Gera embeddings pendentes (`force` opcional) |
| `/api/wishlist` | CRUD | Lista de desejos |
| `/api/devices` | GET | Dispositivos e estado |
| `/api/devices/wake` | POST | Envia magic packet |
| `/api/voice/transcribe` | POST | Áudio → texto |
| `/api/voice/synthesize` | POST | Texto → áudio |
| `/api/finance/state` | GET/PUT | Renda, investimentos e lançamentos do Meu Dinheiro |
| `/api/finance/transactions` | POST | Cria um lançamento (PWA e assistente) |
| `/api/finance/transactions/{id}` | DELETE | Exclui um lançamento |
| `/api/finance/summary` | GET | Totais do mês ou de todo o histórico |
| `/api/finance/reset` | POST | Apaga lançamentos e volta à renda padrão |
| `/finance/` | GET | PWA local do Meu Dinheiro (arquivos estáticos) |
| `/api/settings` | GET/PUT | Modelo, voz, permissões |
| `/ws` | WebSocket | Streaming de tokens, pedidos de confirmação, estado de tarefas |

---

## 5. Modelo de dados (SQLite)

```sql
-- histórico (fonte de contexto, não de memória)
conversations(id, title, created_at, updated_at)
messages(id, conversation_id, role, content, tool_calls_json, created_at)

-- memória estruturada, independente do modelo
memories(id, kind,            -- "personal" | "preference" | "project" | "fact"
         key, content, source_message_id, created_at, updated_at, active)
memory_embeddings(memory_id, model, dimensions, vector BLOB,
                  content_hash, updated_at)     -- segunda via opcional

wishlist(id, title, notes, priority, status,     -- "aberto" | "comprado" | "descartado"
         url, created_at, updated_at)

devices(id, name, mac, tailscale_ip, last_known_state,
        last_seen, wol_supported_states)          -- p.ex. "S3,S5"

audit_log(id, actor, action, args_json, result,
          confirmed_by_user, created_at)          -- backend e agente mantêm logs próprios

settings(key, value_json)                          -- provider ativo, modelo, voz, permissões
```

Recuperação contextual: as memórias estruturadas são recuperadas via FTS5 e
combinadas com as últimas mensagens. Quando `CHAT_EMBEDDING_PROVIDER=ollama`,
a busca semântica entra como segunda via e os rankings são fundidos por RRF;
sem provedor, sem modelo instalado ou em caso de falha, o FTS5 responde
sozinho. A indexação é feita por `POST /api/memories/embeddings/reindex`.

---

## 6. Segurança e privacidade

1. Dados 100% locais por padrão. Qualquer envio a serviço externo
   (ex.: pesquisa web) exige ferramenta própria e configuração explícita;
   a ferramenta de pesquisa envia **apenas a consulta**, nunca memória.
2. Permissões separadas em leitura / escrita / execução, tanto nas ferramentas
   quanto no agente (tabelas de permissão por ação e por pasta). Leitura e
   escrita usam raízes distintas; gravações são atômicas e limitadas.
3. Nenhum comando arbitrário do modelo: o agente só executa itens da allowlist
   com argumentos validados (sem shell interpolation, sem pipelines).
4. Toda ação do agente e do backend gera registro em `audit_log` / journal.
5. Confirmação explícita no app para ações `CONFIRM`/`RESTRICTED`.
6. Tokens por dispositivo, revogáveis; agente escuta apenas na interface
   Tailscale e localhost — nunca em 0.0.0.0 público.

---

## 7. Plano de implementação incremental

Cada fase entrega algo **executável e testável** antes da seguinte.

| Fase | Escopo | Critério de validação |
|---|---|---|
| **0** | Scaffolding: monorepo, backend mínimo FastAPI, contrato `ModelProvider`, config, migrações SQLite, `docs/TROCAR-MODELO.md` | `GET /health` responde; provider fake nos testes |
| **1** | Conversa: `OllamaProvider` + `chat_service` + histórico + endpoint `/api/chat` + streaming via WS | Conversa de ponta a ponta por texto com streaming; troca de provider em config sem alterar código |
| **2** | Memória: módulo `memories` + recuperação FTS5 + injeção no prompt + CRUD no backend | Informar um fato numa conversa e vê-lo recuperado em outra, sem estar no histórico |
| **3** | App Flutter mínimo: chat com streaming, histórico, configuração de modelo | App conversa com o backend local |
| **4** | Voz: `WhisperCppSTT` + `PiperTTS` + endpoints + botão de microfone + reprodução + interrupção | Pergunta falada → resposta falada, com barge-in funcionando |
| **5** | Ferramentas: wishlist, web_search, open_url + loop de tool calling + confirmação | "Adiciona X à minha lista" funciona de ponta a ponta com tool call validada |
| **6** | Agente Ubuntu: daemon, allowlist, journal, auth + `agent_exec` + `device_status` | Abrir um programa no notebook a partir do assistente, com log no journal |
| **7** | Comunicação remota + WoL: Tailscale, token por dispositivo, módulo `wol` | **Parcial:** cadastro e envio local testados; falta configurar Tailscale e validar um alvo real |
| **8** | App Flutter completo: desejos, memória, dispositivos, configurações de voz | **MVP Linux entregue:** telas e APIs locais validadas; Android e fluxo remoto pendentes |
| **9** | Endurecimento: testes de segurança, mTLS, revisão de permissões | **Parcial local:** limites, keyring, mTLS backend-agente, allowlist e auditoria testados; falta auditoria final para acesso remoto |
| **10** | Arquivos no agente Ubuntu: listar e ler dentro de raízes autorizadas, com confirmação e journal | **Leitura entregue:** testes do daemon e do backend validados; escrita veio na Fase 11 |
| **11** | Escrita de arquivos, conversa contínua com wake word e modo relógio com hibernação | **Entregue localmente:** 10 testes do daemon e 16 testes Flutter; escrita liberada em `~/Documentos/Chat` |
| **12** | Memória semântica: `EmbeddingProvider`, Ollama, migração v3, RRF e reindexação | **Entregue localmente:** 44 testes do backend; Ollama + `bge-m3` com corte de similaridade no `dev_run.sh` |
| **Futuro** | Tailscale/acesso remoto, despertar por voz na hibernação, índice ANN, iGPU (Vulkan) | A definir após validação local e remota |

---

## 8. Dependências

**Backend (Python):** `fastapi`, `uvicorn`, `httpx`, `pydantic`, `aiosqlite`
ou `sqlite3` padrão, `pytest`, `pytest-asyncio`. Opcionais: `faster-whisper`,
`piper-tts` e voz `pt_BR-faber-medium`, binário `whisper.cpp`.

**Ambiente:** Ollama instalado e modelo 3B baixado; Tailscale nos dois
dispositivos (fase 7); systemd para o agente.

**Flutter:** `http`, `web_socket_channel`, `record` (microfone),
`flutter_secure_storage` + Secret Service (token), `shared_preferences`
(endereço do backend). No Linux, captura usa `pw-record` e playback usa
`aplay` com fallback para `ffplay`.

---

## 9. Documentação de troca de componentes (resumo)

- **Trocar o LLM:** adicionar classe em `backend/chat/providers/`,
  registrar em `providers/registry.py`, mudar `settings.provider` e
  `settings.model`. Nenhum outro módulo é tocado. (Detalhe: `docs/TROCAR-MODELO.md`)
- **Trocar o STT:** nova classe implementando `STTEngine` em `backend/chat/voice/`,
  registrar no `registry.py` e escolher no settings.
- **Trocar o TTS:** mesma lógica com `TTSEngine`.
- **Trocar/adicionar ferramenta:** nova classe `Tool` + registro; o schema é
  exposto automaticamente ao modelo.
