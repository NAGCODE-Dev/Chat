#!/usr/bin/env bash
# Gera o pacote .deb do app Linux a partir do bundle release do Flutter.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app_flutter"
BUNDLE="$APP_DIR/build/linux/x64/release/bundle"
VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$APP_DIR/pubspec.yaml" | head -1 | cut -d+ -f1)"
VERSION="${VERSION:-1.0.0}"
ARCH="$(dpkg --print-architecture)"
PACKAGE="chat-app"
STAGE="$APP_DIR/build/deb/${PACKAGE}_${VERSION}_${ARCH}"
OUT_DIR="$ROOT/dist"
OUT="$OUT_DIR/${PACKAGE}_${VERSION}_${ARCH}.deb"

if [[ "${1:-}" != "--no-build" ]]; then
  (cd "$APP_DIR" && flutter build linux --release)
fi

if [[ ! -x "$BUNDLE/chat_app" ]]; then
  echo "Bundle Linux não encontrado em $BUNDLE" >&2
  exit 1
fi

rm -rf "$STAGE"
install -d \
  "$STAGE/DEBIAN" \
  "$STAGE/opt/chat-app" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps" \
  "$STAGE/usr/share/doc/chat-app"

cp -a "$BUNDLE/." "$STAGE/opt/chat-app/"
ln -s /opt/chat-app/chat_app "$STAGE/usr/bin/chat_app"
install -m 0644 "$APP_DIR/linux/assets/chat_app.png" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps/chat_app.png"
install -m 0644 "$ROOT/README.md" "$STAGE/usr/share/doc/chat-app/README.md"

cat > "$STAGE/usr/share/applications/com.example.chat_app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Chat
GenericName=Assistente de chat
Comment=Assistente de chat local com voz, memória e computador Ubuntu
Exec=chat_app %U
Icon=chat_app
Terminal=false
Categories=Network;Chat;
StartupNotify=true
StartupWMClass=com.example.chat_app
EOF

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: Nikolas <nikolas@localhost>
Depends: libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libstdc++6, libc6 (>= 2.34), pipewire-bin, alsa-utils | ffmpeg, xdg-utils, systemd
Recommends: ffmpeg
Description: Assistente de chat local
 Cliente desktop do Chat para conversar com modelos locais, usar voz,
 anexos, memória, histórico e tarefas no computador Ubuntu.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

install -d "$OUT_DIR"
rm -f "$OUT"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT" >/dev/null
echo "$OUT"
