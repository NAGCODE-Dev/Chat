# Chat

Assistente pessoal local-first para Ubuntu, com conversa por voz, memória
persistente, ferramentas e controle do notebook. O modelo de linguagem é
totalmente desacoplado do restante da aplicação.

## Componentes

| Componente | Pasta | Papel |
|---|---|---|
| App Flutter | `app_flutter/` | Conversa, voz, histórico, desejos, memória, dispositivos e configurações (Linux e Android) |
| Backend | `backend/` | FastAPI, orquestração, memória SQLite, voz, ferramentas e permissões |
| Agente Ubuntu | `agent/` | Daemon local com allowlist, journal, abertura de apps e leitura/escrita de arquivos autorizados |
| Provider de modelo | `backend/chat/providers/` | Contrato `ModelProvider`; Ollama é a implementação inicial |
| Embeddings | `backend/chat/memory/embeddings.py` | Segunda via de memória; Ollama local, com fallback lexical obrigatório |
| Meu Dinheiro | `backend/chat/finance/static/` | Fork local do PWA de finanças, servido em `/finance/` |

## Recursos de uso diário

- Conversa por texto e voz em pt-BR, com streaming e histórico persistente.
- Busca na internet sem chave de API (Bing HTML ou SearXNG) e leitura de
  páginas com proteção contra SSRF.
- Memória pessoal com FTS5 e, opcionalmente, busca semântica por embeddings.
- Lista de desejos, lembretes, notas e documentos.
- Leitura e escrita de arquivos de texto em pastas explicitamente autorizadas,
  sempre com confirmação no app.
- Conversa contínua com palavra de ativação configurável.
- Modo relógio de quarto: hora gigante, tela ligada e hibernação de baixo
  consumo após inatividade (apenas no desktop).
- App Android conectado ao backend por Wi-Fi ou USB, com token e áudio nativo.
- Android como assistente padrão, com leitura opcional de notificações e ações
  no aparelho: abrir apps, tocar música, controlar mídia e abrir links.
- Tema claro/escuro/sistema mantendo o azul do app, botão de silêncio e
  exclusão de conversas.
- Meu Dinheiro local: o assistente registra gastos, receitas e aportes por
  comando, em segundo plano, e o PWA lê os dados do backend.
- Controle local do notebook pela allowlist do agente, sem shell arbitrário.

## Início rápido

Pré-requisitos: Python 3.12+, Flutter, Ollama com um modelo local e, para voz,
`whisper.cpp` e Piper. Por padrão o backend escuta em `127.0.0.1:8750`; neste
ambiente ele está em `0.0.0.0:8750` com token, como serviço de usuário
`chat-backend.service`.

```bash
# backend
python3 -m venv backend/.venv
backend/.venv/bin/pip install -e 'backend[dev]'
scripts/dev_run.sh

# app (outro terminal)
cd app_flutter
flutter build linux
./build/linux/x64/release/bundle/chat_app
```

Detalhes de configuração, token, voz e agente em
[`docs/EXECUCAO-LOCAL.md`](docs/EXECUCAO-LOCAL.md).

## Testes

```bash
backend/.venv/bin/python -m pytest backend/tests
agent/.venv/bin/pip install -e 'agent[dev]'
agent/.venv/bin/python -m pytest agent/tests
cd app_flutter && flutter analyze && flutter test
```

## Segurança

- Dados ficam locais por padrão; o banco é `~/.local/share/chat/chat.db`.
- Ferramentas com efeito externo exigem confirmação no app.
- O agente só executa ações da allowlist, sem shell, e registra tudo em
  `~/.local/share/chat-agent/journal.jsonl`. O conteúdo lido ou escrito não
  entra no journal.
- Leitura e escrita usam raízes separadas (`CHAT_AGENT_ALLOWED_DIRS` e
  `CHAT_AGENT_WRITE_DIRS`), com limites de tamanho e gravação atômica.
- O backend recusa bind fora de loopback sem `CHAT_API_TOKEN`. Neste ambiente,
  o token fica em `~/.config/chat/backend.env` (modo 600) e é exigido também
  pelo app do celular.
- Na rede local o tráfego é HTTP; o token autentica, mas não cifra. Fora de
  casa, use Tailscale/VPN e não exponha as portas à internet.
- Embeddings, quando habilitados, são gerados localmente pelo Ollama; a
  memória não é enviada a serviços externos.
- Leia [`docs/SEGURANCA.md`](docs/SEGURANCA.md) e
  [`docs/CONEXAO-CELULAR.md`](docs/CONEXAO-CELULAR.md).

## Documentação

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — arquitetura, contratos e plano de fases
- [`docs/FASE-1.md`](docs/FASE-1.md) … [`docs/FASE-13.md`](docs/FASE-13.md) — entregas por fase
- [`docs/CONEXAO-CELULAR.md`](docs/CONEXAO-CELULAR.md) — app Android, pareamento por QR, Tailscale e URLs
- [`docs/ASSISTENTE-CELULAR.md`](docs/ASSISTENTE-CELULAR.md) — assistente padrão, notificações, apps, música e tema
- [`docs/MEU-DINHEIRO.md`](docs/MEU-DINHEIRO.md) — integração financeira local, API e PWA
- [`docs/TROCAR-MODELO.md`](docs/TROCAR-MODELO.md) — como trocar o LLM
- [`docs/SEGURANCA.md`](docs/SEGURANCA.md) — permissões, limites e auditoria
- [`docs/benchmark-modelos-2026-10-24.md`](docs/benchmark-modelos-2026-10-24.md) — benchmark local dos modelos

## Estado atual

Fases 0–13 entregues localmente. O app conversa por texto e voz, mantém
memória lexical com embeddings (`bge-m3`), lê e grava arquivos autorizados,
conversa continuamente com palavra de ativação e funciona como relógio de
quarto com hibernação. O celular Android conecta por Wi-Fi, USB ou Tailscale, com pareamento por QR
code e token guardado no cofre do aparelho. Pode ser definido como assistente
padrão, lê notificações com permissão e executa ações fechadas no aparelho
(apps, música, mídia e links). O modelo padrão é
`qwen2.5:3b-instruct-q4_K_M`; o Qwen3 4B foi testado, mas ficou cerca de duas
vezes mais lento na CPU e o modo automático segue desligado. O assistente
registra lançamentos no Meu Dinheiro local em segundo plano, e o PWA lê os
dados do backend. O notebook já tem Tailscale ativo; falta instalar o
Tailscale no celular para validar o acesso fora de casa. Escuta em segundo
plano e a instalação do PWA local como app standalone (HTTPS) ainda ficam
pendentes. A hospedagem recomendada continua local (notebook + Ollama);
PaaS como o Render não é adequado para Ollama em CPU com SQLite persistente.
