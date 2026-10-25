#!/usr/bin/env bash
set -euo pipefail

agent_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
venv_dir="$agent_dir/.venv"
config_dir="$HOME/.config/chat-agent"
environment_file="$config_dir/agent.env"
unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/chat-agent.service"

if ! command -v systemctl >/dev/null || ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "systemd --user indisponível nesta sessão." >&2
  exit 1
fi

if [[ ! -x "$venv_dir/bin/python" ]]; then
  python3 -m venv "$venv_dir"
fi
"$venv_dir/bin/pip" install -e "$agent_dir"

install -d -m 700 "$config_dir" "$unit_dir"
chmod 700 "$config_dir" "$unit_dir"
python3 - "$environment_file" <<'PY'
import os
import secrets
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.exists():
    existing = path.read_text(encoding="utf-8").strip()
    if existing.startswith("CHAT_AGENT_TOKEN=") and len(existing.split("=", 1)[1]) >= 32:
        path.chmod(0o600)
        raise SystemExit(0)

token = os.environ.get("CHAT_AGENT_TOKEN") or secrets.token_urlsafe(36)
if len(token) < 32:
    raise SystemExit("CHAT_AGENT_TOKEN precisa ter pelo menos 32 caracteres")
path.write_text(f"CHAT_AGENT_TOKEN={token}\n", encoding="utf-8")
path.chmod(0o600)
PY

cat > "$unit_file" <<EOF
[Unit]
Description=Chat Ubuntu Agent
After=default.target

[Service]
Type=simple
EnvironmentFile=%h/.config/chat-agent/agent.env
WorkingDirectory=$agent_dir
ExecStart=$agent_dir/run_agent.sh
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
RestrictSUIDSGID=true
UMask=0077

[Install]
WantedBy=default.target
EOF
chmod 600 "$unit_file"
systemctl --user daemon-reload
systemctl --user enable --now chat-agent.service
echo "Agente instalado em loopback. Token guardado em $environment_file (modo 600)."
echo "Configure a mesma variável no processo do backend; não publique esta porta."
