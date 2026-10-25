"""Limite global de corpo HTTP para impedir leitura sem limite de payloads."""

from __future__ import annotations

import json
from collections.abc import Awaitable, Callable
from typing import Any

ASGIApp = Callable[[dict[str, Any], Callable, Callable], Awaitable[None]]


class RequestBodyTooLarge(Exception):
    pass


class RequestBodyLimitMiddleware:
    def __init__(self, app: ASGIApp, max_bytes: int, detail: str) -> None:
        if max_bytes < 1:
            raise ValueError("max_bytes precisa ser positivo")
        self.app = app
        self.max_bytes = max_bytes
        self.detail = detail

    async def __call__(self, scope: dict[str, Any], receive: Callable, send: Callable) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        content_length = dict(scope.get("headers", [])).get(b"content-length")
        if content_length:
            try:
                declared_size = int(content_length)
            except ValueError:
                await self._reject(send, 400, "Content-Length inválido.")
                return
            if declared_size > self.max_bytes:
                await self._reject(send, 413, self.detail)
                return

        received_bytes = 0
        too_large = False
        response_started = False

        async def limited_receive():
            nonlocal received_bytes, too_large
            message = await receive()
            if message["type"] == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > self.max_bytes:
                    too_large = True
                    raise RequestBodyTooLarge
            return message

        async def limited_send(message):
            nonlocal response_started
            if too_large:
                if message["type"] == "http.response.start" and not response_started:
                    response_started = True
                    await self._reject(send, 413, self.detail)
                return
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, limited_send)
        except RequestBodyTooLarge:
            if not response_started:
                await self._reject(send, 413, self.detail)

    @staticmethod
    async def _reject(send: Callable, status: int, detail: str) -> None:
        body = json.dumps({"detail": detail}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})
