"""Wake-on-LAN packet builder/sender; it reports packet delivery, not device boot."""

from __future__ import annotations

import ipaddress
import re
import socket


def normalize_mac(address: str) -> str:
    compact = re.sub(r"[:-]", "", address.strip())
    if not re.fullmatch(r"[0-9a-fA-F]{12}", compact):
        raise ValueError("Endereço MAC inválido.")
    return ":".join(compact[index:index + 2].lower() for index in range(0, 12, 2))


def magic_packet(address: str) -> bytes:
    mac = bytes.fromhex(normalize_mac(address).replace(":", ""))
    return b"\xff" * 6 + mac * 16


def send_magic_packet(address: str, broadcast: str = "255.255.255.255", port: int = 9) -> None:
    ipaddress.IPv4Address(broadcast)
    if not 1 <= port <= 65535:
        raise ValueError("Porta UDP inválida.")
    payload = magic_packet(address)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(payload, (broadcast, port))
