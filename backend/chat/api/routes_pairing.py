"""Pareamento por QR code entre o aplicativo e este backend."""

from __future__ import annotations

import asyncio
import ipaddress
import socket
import subprocess
from urllib.parse import urlencode, urlparse

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from chat.api.state import state
from chat.core.logging import get_logger
from chat.pairing import PairingStore

router = APIRouter(prefix="/api/pairing", tags=["pairing"])
log = get_logger("chat.routes_pairing")
pairing_store = PairingStore()


class PairingClaim(BaseModel):
    code: str = Field(min_length=16, max_length=120)


def _is_loopback(host: str | None) -> bool:
    if not host:
        return False
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return host == "localhost"


def is_public_pairing_request(request: Request) -> bool:
    """Libera só a troca do código e a criação local de sessões."""
    path = request.url.path
    if path == "/api/pairing/claim" and request.method == "POST":
        return True
    return (
        path == "/api/pairing/sessions"
        and request.method == "POST"
        and _is_loopback(request.client.host if request.client else None)
    )


def _local_ipv4_addresses() -> list[str]:
    """Lista IPv4 físicas, com USB/LAN antes do Wi-Fi e sem a VPN."""
    entries: list[tuple[int, str]] = []
    try:
        result = subprocess.run(
            ["ip", "-4", "-o", "addr", "show"],
            capture_output=True,
            check=False,
            text=True,
            timeout=3,
        )
        for line in result.stdout.splitlines():
            fields = line.split()
            if len(fields) < 4:
                continue
            interface = fields[1]
            if interface == "lo" or interface.startswith(
                ("virbr", "docker", "br-", "veth", "tailscale", "tun")
            ):
                continue
            address = fields[3].split("/", 1)[0]
            if not address:
                continue
            if interface.startswith(("usb", "rndis", "enx")):
                rank = 0
            elif interface.startswith(("en", "eth", "wl", "wlan")):
                rank = 1
            else:
                rank = 2
            entries.append((rank, address))
    except (OSError, subprocess.SubprocessError):
        pass
    if entries:
        return list(dict.fromkeys(address for _, address in sorted(entries)))

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        address = sock.getsockname()[0]
        if address and not address.startswith("127."):
            return [address]
    except OSError:
        pass
    finally:
        sock.close()
    return []


def _tailscale_ipv4() -> str | None:
    """Obtém o IP atual do Tailscale; None quando ele não está instalado."""
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True,
            check=False,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    for line in result.stdout.splitlines():
        address = line.strip()
        if address:
            return address
    return None


async def _candidate_urls(request: Request) -> list[str]:
    """Monta URLs alcançáveis pelo celular, da mais rápida para a mais ampla.

    USB e LAN vêm antes do Tailscale: em casa o pareamento termina em
    milissegundos. Fora de casa, o app tenta as primeiras com timeout curto e
    cai para o endereço da VPN.
    """
    if state.settings is None:
        raise HTTPException(status_code=503, detail="Configuração não inicializada.")
    port = state.settings.port
    urls: list[str] = []

    def add(value: str) -> None:
        normalized = value.rstrip("/")
        if normalized and normalized not in urls:
            urls.append(normalized)

    request_base = str(request.base_url).rstrip("/")
    request_host = urlparse(request_base).hostname
    if request_host and not _is_loopback(request_host):
        add(request_base)

    for local_ip in _local_ipv4_addresses():
        add(f"http://{local_ip}:{port}")

    tailscale_ip = await asyncio.to_thread(_tailscale_ipv4)
    if tailscale_ip:
        add(f"http://{tailscale_ip}:{port}")

    if not urls:
        add(request_base)
    return urls


def _qr_payload(code: str, urls: list[str]) -> str:
    query = urlencode(
        [("v", "1"), ("code", code), *[("url", url) for url in urls]]
    )
    return f"chatpair://pair?{query}"


@router.post("/sessions", status_code=201)
async def create_pairing_session(request: Request) -> dict:
    if state.settings is None:
        raise HTTPException(status_code=503, detail="Configuração não inicializada.")
    session = pairing_store.create(state.settings.pairing_ttl_seconds)
    urls = await _candidate_urls(request)
    log.info(
        "sessão de pareamento criada | expira_em=%ds | urls=%s",
        session.remaining_seconds(),
        urls,
    )
    return {
        "code": session.code,
        "urls": urls,
        "qr_payload": _qr_payload(session.code, urls),
        "expires_in": session.remaining_seconds(),
    }


@router.post("/claim")
async def claim_pairing(payload: PairingClaim, request: Request) -> dict:
    if not pairing_store.claim(payload.code):
        raise HTTPException(
            status_code=404,
            detail="Código de pareamento inválido ou expirado.",
        )
    token = state.settings.api_token if state.settings else None
    base = str(request.base_url).rstrip("/")
    log.info("pareamento concluído | cliente=%s", request.client.host if request.client else "?")
    return {"url": base, "token": token}
