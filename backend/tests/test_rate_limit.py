from __future__ import annotations

import pytest
from starlette.websockets import WebSocketDisconnect

from chat.api.rate_limit import RateLimiter
from chat.api.state import state


def test_rate_limiter_blocks_until_oldest_request_expires():
    limiter = RateLimiter(requests=2, window_seconds=10)
    assert limiter.allow("client", now=1) == (True, 0)
    assert limiter.allow("client", now=2) == (True, 0)
    allowed, retry_after = limiter.allow("client", now=3)
    assert not allowed
    assert retry_after == 8
    assert limiter.allow("client", now=11) == (True, 0)


def test_rate_limiter_tracks_clients_separately():
    limiter = RateLimiter(requests=1, window_seconds=10)
    assert limiter.allow("one", now=1)[0]
    assert limiter.allow("two", now=1)[0]
    assert not limiter.allow("one", now=2)[0]


def test_rate_limiter_bounds_client_memory_and_reclaims_expired_clients():
    limiter = RateLimiter(requests=2, window_seconds=10, max_clients=2)
    assert limiter.allow("one", now=1)[0]
    assert limiter.allow("two", now=2)[0]
    assert limiter.allow("three", now=3) == (False, 8)
    assert limiter.allow("three", now=12) == (True, 0)
    assert len(limiter._events) <= 2


def test_http_middleware_returns_429_and_retry_after(client, monkeypatch):
    monkeypatch.setattr("chat.api.main.rate_limiter", RateLimiter(requests=2, window_seconds=60))
    state.settings.rate_limit_per_minute = 2
    assert client.get("/health").status_code == 200
    assert client.get("/health").status_code == 200
    limited = client.get("/health")
    assert limited.status_code == 429
    assert int(limited.headers["retry-after"]) > 0


def test_websocket_limits_inbound_messages_per_connection():
    import asyncio
    import json
    from collections import deque

    from chat.api import routes_chat

    class FakeWebSocket:
        def __init__(self) -> None:
            self.frames = deque([json.dumps({"message": "oi"})])
            self.sent: list[dict] = []
            self.closed: tuple[int, str] | None = None

        async def receive_text(self) -> str:
            return self.frames.popleft()

        async def send_json(self, payload: dict) -> None:
            self.sent.append(payload)

        async def close(self, code: int = 1000, reason: str = "") -> None:
            self.closed = (code, reason)

    websocket = FakeWebSocket()
    limiter = RateLimiter(requests=1, window_seconds=60)

    async def exercise() -> None:
        assert await routes_chat._receive_limited(websocket, limiter) == {"message": "oi"}
        with pytest.raises(WebSocketDisconnect) as error:
            await routes_chat._receive_limited(websocket, limiter)
        assert error.value.code == 1013

    asyncio.run(exercise())
    assert websocket.sent[-1]["type"] == "error"
    assert websocket.closed is not None and websocket.closed[0] == 1013


def test_websocket_connection_is_rate_limited(client, monkeypatch):
    from starlette.websockets import WebSocketDisconnect

    from chat.api import routes_chat
    from chat.api.state import state

    monkeypatch.setattr(routes_chat, "rate_limiter", RateLimiter(requests=1, window_seconds=60))
    state.settings.rate_limit_per_minute = 1
    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_json({"message": "primeira"})
        while websocket.receive_json().get("type") != "done":
            pass
    try:
        with client.websocket_connect("/api/ws/chat"):
            raise AssertionError("A segunda conexão deveria ter sido recusada")
    except WebSocketDisconnect as error:
        assert error.code == 1013
