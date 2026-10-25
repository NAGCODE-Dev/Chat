#!/usr/bin/env bash
set -euo pipefail
agent_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
args=(ubuntu_agent.server:app --host 127.0.0.1 --port 8765)
tls_values=("${CHAT_AGENT_TLS_CA:-}" "${CHAT_AGENT_TLS_SERVER_CERT:-}" "${CHAT_AGENT_TLS_SERVER_KEY:-}")
if [[ -n "${tls_values[0]}${tls_values[1]}${tls_values[2]}" ]]; then
  if [[ -z "${tls_values[0]}" || -z "${tls_values[1]}" || -z "${tls_values[2]}" ]]; then
    echo "mTLS requer CHAT_AGENT_TLS_CA, CHAT_AGENT_TLS_SERVER_CERT e CHAT_AGENT_TLS_SERVER_KEY." >&2
    exit 1
  fi
  args+=(--ssl-certfile "${tls_values[1]}" --ssl-keyfile "${tls_values[2]}" --ssl-ca-certs "${tls_values[0]}" --ssl-cert-reqs 2)
fi
cd "$agent_dir"
exec "$agent_dir/.venv/bin/uvicorn" "${args[@]}"
