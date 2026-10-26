#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
backend_path="$project_root/backend"

# Configuração local do backend (token de API, bind, etc.), modo 600.
backend_env="$HOME/.config/chat/backend.env"
if [[ -f "$backend_env" ]]; then
  set -a
  source "$backend_env"
  set +a
fi

export CHAT_PROVIDER="${CHAT_PROVIDER:-ollama}"
export CHAT_MODEL="${CHAT_MODEL:-qwen2.5:3b-instruct-q4_K_M}"
# Modelo maior opcional: só entra quando há memória livre suficiente.
export CHAT_MODEL_AUTO="${CHAT_MODEL_AUTO:-0}"
export CHAT_MODEL_FAST="${CHAT_MODEL_FAST:-qwen2.5:1.5b-instruct-q4_K_M}"
export CHAT_MODEL_FAST_MAX_CHARS="${CHAT_MODEL_FAST_MAX_CHARS:-280}"
export CHAT_MODEL_AUTO_MIN_FREE_MB="${CHAT_MODEL_AUTO_MIN_FREE_MB:-4096}"
export CHAT_MODEL_AUTO_KEEP_FREE_MB="${CHAT_MODEL_AUTO_KEEP_FREE_MB:-1024}"
export CHAT_MODEL_KEEP_ALIVE="${CHAT_MODEL_KEEP_ALIVE:-30m}"
export CHAT_MODEL_LARGE_KEEP_ALIVE="${CHAT_MODEL_LARGE_KEEP_ALIVE:-10m}"
export CHAT_NUM_THREAD="${CHAT_NUM_THREAD:-6}"
export CHAT_MAX_TOKENS="${CHAT_MAX_TOKENS:-1024}"
export CHAT_NUM_CTX="${CHAT_NUM_CTX:-8192}"
export CHAT_EMBEDDING_PROVIDER="${CHAT_EMBEDDING_PROVIDER:-ollama}"
export CHAT_EMBEDDING_MODEL="${CHAT_EMBEDDING_MODEL:-bge-m3}"
export CHAT_EMBEDDING_MIN_SIMILARITY="${CHAT_EMBEDDING_MIN_SIMILARITY:-0.6}"
export CHAT_HOST="${CHAT_HOST:-127.0.0.1}"
export CHAT_PORT="${CHAT_PORT:-8750}"

agent_env="$HOME/.config/chat-agent/agent.env"
if [[ -z "${CHAT_AGENT_TOKEN:-}" && -f "$agent_env" ]]; then
  set -a
  # Este arquivo é criado pelo instalador com modo 600.
  source "$agent_env"
  set +a
fi
if [[ -n "${CHAT_AGENT_TOKEN:-}" ]]; then
  if [[ -n "${CHAT_AGENT_TLS_CA:-}" ]]; then
    : "${CHAT_AGENT_TLS_CLIENT_CERT:?mTLS requer CHAT_AGENT_TLS_CLIENT_CERT}"
    : "${CHAT_AGENT_TLS_CLIENT_KEY:?mTLS requer CHAT_AGENT_TLS_CLIENT_KEY}"
    export CHAT_AGENT_URL="${CHAT_AGENT_URL:-https://127.0.0.1:8765}"
  else
    export CHAT_AGENT_URL="${CHAT_AGENT_URL:-http://127.0.0.1:8765}"
  fi
fi

whisper_path="$HOME/.local/share/chat/whisper.cpp/bin/whisper-cli"
whisper_model="$HOME/.local/share/chat/models/whisper/ggml-base.bin"
piper_model="$HOME/.local/share/chat/models/piper/pt_BR-faber-medium.onnx"
if [[ -x "$whisper_path" && -f "$whisper_model" ]]; then
  export CHAT_WHISPER_BINARY="${CHAT_WHISPER_BINARY:-$whisper_path}"
  export CHAT_WHISPER_MODEL_PATH="${CHAT_WHISPER_MODEL_PATH:-$whisper_model}"
fi
if [[ -f "$piper_model" ]]; then
  export CHAT_PIPER_MODEL_PATH="${CHAT_PIPER_MODEL_PATH:-$piper_model}"
fi

cd "$backend_path"
exec "$backend_path/.venv/bin/uvicorn" chat.api.main:app \
  --host "$CHAT_HOST" --port "$CHAT_PORT" --ws-max-size 65536
