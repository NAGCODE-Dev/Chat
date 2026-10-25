"""Rate limiting em memória por endereço de cliente, com janela deslizante."""

from __future__ import annotations

import time
from collections import deque


class RateLimiter:
    def __init__(
        self,
        requests: int,
        window_seconds: float = 60.0,
        max_clients: int = 4096,
    ) -> None:
        if requests < 1 or window_seconds <= 0:
            raise ValueError("Limite e janela precisam ser positivos.")
        if max_clients < 1:
            raise ValueError("O máximo de clientes precisa ser positivo.")
        self.requests = requests
        self.window_seconds = window_seconds
        self.max_clients = max_clients
        self._events: dict[str, deque[float]] = {}

    def allow(self, key: str, now: float | None = None) -> tuple[bool, int]:
        timestamp = time.monotonic() if now is None else now
        cutoff = timestamp - self.window_seconds
        events = self._events.get(key)
        if events is None:
            if len(self._events) >= self.max_clients:
                expired = [
                    client
                    for client, client_events in self._events.items()
                    if not client_events or client_events[-1] <= cutoff
                ]
                for client in expired:
                    del self._events[client]
            if len(self._events) >= self.max_clients:
                earliest = min(client_events[0] for client_events in self._events.values())
                retry_after = max(
                    1,
                    int(earliest + self.window_seconds - timestamp + 0.999),
                )
                return False, retry_after
            events = self._events[key] = deque()
        while events and events[0] <= cutoff:
            events.popleft()
        if len(events) >= self.requests:
            retry_after = max(1, int(events[0] + self.window_seconds - timestamp + 0.999))
            return False, retry_after
        events.append(timestamp)
        return True, 0


rate_limiter = RateLimiter(requests=120)
