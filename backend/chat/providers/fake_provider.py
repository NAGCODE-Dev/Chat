"""Provedor fictício para testes e desenvolvimento sem Ollama.

Responde de forma determinística: ecoa a última mensagem do usuário.
Usado pela Fase 0 e por toda a suíte de testes.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from typing import Any

from chat.providers.base import (
    Message,
    ModelInfo,
    ModelProvider,
    ModelResponse,
    ToolSpec,
)


class FakeProvider(ModelProvider):
    def __init__(self, reply: str = "Olá! Sou o Chat (provider de teste).") -> None:
        self.reply = reply
        self.last_messages: list[Message] = []

    async def chat(
        self,
        messages: list[Message],
        model: str = "fake-model",
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> ModelResponse:
        self.last_messages = list(messages)
        return ModelResponse(content=self.reply, finish_reason="stop")

    async def stream(
        self,
        messages: list[Message],
        model: str = "fake-model",
        options: dict[str, Any] | None = None,
    ) -> AsyncIterator[str]:
        self.last_messages = list(messages)
        for chunk in (self.reply[:12], self.reply[12:24], self.reply[24:]):
            if chunk:
                yield chunk

    async def list_models(self) -> list[ModelInfo]:
        return [ModelInfo(id="fake-model", name="Fake Model")]

    async def health(self) -> bool:
        return True

    # extras para testes
    async def chat_raw(self, messages: list[dict[str, Any]]) -> dict[str, Any]:  # pragma: no cover
        return {"content": self.reply}
