#!/usr/bin/env bash
set -euo pipefail

unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/chat-agent.service"
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user disable --now chat-agent.service 2>/dev/null || true
  systemctl --user daemon-reload
fi
rm -f -- "$unit_file"
echo "Serviço removido. O token em ~/.config/chat-agent/agent.env foi preservado."
