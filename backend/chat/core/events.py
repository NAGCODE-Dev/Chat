"""Barramento de eventos em processo.

Usos: streaming de tokens para o WebSocket, pedidos de confirmação de
ferramentas, atualizações de estado de dispositivos. Desacopla produtores
(providers, tools) de consumidores (rotas HTTP/WS).
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

Handler = Callable[[dict[str, Any]], Awaitable[None]]


@dataclass
class Event:
    type: str
    data: dict[str, Any] = field(default_factory=dict)


class EventBus:
    def __init__(self) -> None:
        self._handlers: dict[str, list[Handler]] = defaultdict(list)

    def subscribe(self, event_type: str, handler: Handler) -> None:
        self._handlers[event_type].append(handler)

    def unsubscribe(self, event_type: str, handler: Handler) -> None:
        self._handlers[event_type].remove(handler)

    async def emit(self, event: Event) -> None:
        for handler in list(self._handlers.get(event.type, [])):
            await handler(event.data)


bus = EventBus()
