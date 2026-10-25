#!/usr/bin/env python3
"""Gera um QR de pareamento temporário para o aplicativo Chat.

O QR contém apenas um código de uso único e as URLs alcançáveis do backend.
O token da API é entregue quando o celular troca o código, nunca vai no QR.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_BACKEND = "http://127.0.0.1:8750"
DEFAULT_ENV_FILE = Path.home() / ".config" / "chat" / "backend.env"


def _read_token() -> str | None:
    token = os.environ.get("CHAT_API_TOKEN")
    if token:
        return token.strip()
    env_file = Path(os.environ.get("CHAT_ENV_FILE", DEFAULT_ENV_FILE)).expanduser()
    try:
        lines = env_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    for line in lines:
        if line.startswith("CHAT_API_TOKEN="):
            return line.split("=", 1)[1].strip()
    return None


def _create_session(backend: str) -> dict:
    request = urllib.request.Request(
        f"{backend.rstrip('/')}/api/pairing/sessions",
        data=b"{}",
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    token = _read_token()
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Backend recusou o pareamento ({error.code}): {detail}")
    except urllib.error.URLError as error:
        raise SystemExit(f"Não foi possível falar com o backend: {error.reason}")


def _print_qr(payload: str, png_path: Path | None) -> None:
    qrencode = shutil.which("qrencode")
    if not qrencode:
        print("Instale 'qrencode' para exibir o QR no terminal.")
        print(payload)
        return
    result = subprocess.run(
        [qrencode, "-t", "ANSIUTF8", "-m", "2", payload],
        check=False,
        text=True,
    )
    if result.returncode != 0:
        print("Não foi possível desenhar o QR no terminal.")
        print(payload)
        return
    if png_path is not None:
        png_path.parent.mkdir(parents=True, exist_ok=True)
        saved = subprocess.run(
            [qrencode, "-o", str(png_path), "-s", "8", "-m", "2", payload],
            check=False,
            text=True,
        )
        if saved.returncode == 0:
            print(f"\nImagem do QR salva em: {png_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend",
        default=os.environ.get("CHAT_PAIRING_BACKEND", DEFAULT_BACKEND),
        help="URL local do backend (padrão: %(default)s)",
    )
    parser.add_argument(
        "--png",
        type=Path,
        default=Path.home() / ".local" / "share" / "chat" / "pairing.png",
        help="Onde salvar a imagem do QR",
    )
    parser.add_argument("--no-png", action="store_true", help="Não salvar imagem")
    args = parser.parse_args()

    session = _create_session(args.backend)
    urls = session.get("urls") or []
    if not urls:
        raise SystemExit("O backend não informou nenhuma URL alcançável.")
    print("Escaneie este QR no Chat do celular.")
    print(f"Validade: {session.get('expires_in', 300)} segundos.\n")
    _print_qr(session["qr_payload"], None if args.no_png else args.png)
    print("\nURLs incluídas no QR:")
    for url in urls:
        print(f"  - {url}")
    print(
        "\nNo celular: abra o Chat, toque no ícone de QR code e aponte a câmera."
    )
    print("O código é de uso único; gere outro se expirar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
