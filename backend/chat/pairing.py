"""Códigos temporários de pareamento entre o notebook e o celular.

O QR code carrega apenas um código aleatório de uso único. O token real da API
só é entregue depois que o aplicativo troca esse código pelo endpoint de
pareamento, e o código expira em poucos minutos.
"""

from __future__ import annotations

import secrets
import time
from collections.abc import Callable
from dataclasses import dataclass


@dataclass(frozen=True)
class PairingSession:
    code: str
    created_at: float
    expires_at: float

    def remaining_seconds(self, now: float | None = None) -> int:
        current = time.time() if now is None else now
        return max(0, int(self.expires_at - current))


class PairingStore:
    """Armazena códigos em memória, com expiração e uso único."""

    def __init__(self, clock: Callable[[], float] = time.time) -> None:
        self._clock = clock
        self._sessions: dict[str, PairingSession] = {}

    def create(self, ttl_seconds: int) -> PairingSession:
        self.prune()
        ttl = max(30, min(int(ttl_seconds), 3600))
        now = self._clock()
        for _ in range(5):
            code = secrets.token_urlsafe(24)
            if code not in self._sessions:
                session = PairingSession(
                    code=code,
                    created_at=now,
                    expires_at=now + ttl,
                )
                self._sessions[code] = session
                return session
        raise RuntimeError("Não foi possível gerar um código de pareamento único.")

    def claim(self, code: str) -> bool:
        """Consome um código válido; devolve False se inválido ou expirado."""
        self.prune()
        session = self._sessions.pop(code, None)
        return session is not None and session.expires_at > self._clock()

    def prune(self) -> None:
        now = self._clock()
        expired = [
            code
            for code, session in self._sessions.items()
            if session.expires_at <= now
        ]
        for code in expired:
            self._sessions.pop(code, None)

    def __len__(self) -> int:
        self.prune()
        return len(self._sessions)
