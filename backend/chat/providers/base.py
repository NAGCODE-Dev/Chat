"""Interface abstrata para provedores de modelo.

Define o contrato que qualquer backend de LLM (Ollama, OpenAI-compat, etc.)
precisa implementar. Isso garante que o restante da aplicação nunca dependa
de uma implementação concreta.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Message:
    """Mensagem de conversa padronizada."""

    role: str
    content: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    tool_call_id: str | None = None
    name: str | None = None
    # Imagens em base64 para modelos com visão (formato nativo do Ollama).
    images: list[str] = field(default_factory=list)


@dataclass
class ToolSpec:
    """Especificação de ferramenta que o modelo pode usar."""

    name: str
    description: str
    parameters: dict[str, Any] = field(default_factory=dict)


@dataclass
class ToolCall:
    """Chamada de ferramenta solicitada pelo modelo."""

    id: str
    name: str
    arguments: dict[str, Any]


@dataclass
class ModelResponse:
    """Resposta completa de uma requisição de chat."""

    content: str
    tool_calls: list[ToolCall] = field(default_factory=list)
    finish_reason: str = "stop"
    raw: dict[str, Any] | None = None


@dataclass
class ModelInfo:
    """Informações sobre um modelo disponível."""

    id: str
    name: str
    context_window: int | None = None


class ProviderError(Exception):
    """Erro normalizado de qualquer provedor de LLM."""


class ModelProvider(ABC):
    """Contrato que todos os provedores de modelo devem cumprir."""

    @abstractmethod
    async def chat(
        self,
        messages: list[Message],
        model: str,
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> ModelResponse:
        """Recebe uma lista de mensagens e retorna a resposta completa."""
        ...

    async def stream_events(
        self,
        messages: list[Message],
        model: str,
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        """Emite conteúdo e chamadas de ferramenta; implementações antigas continuam compatíveis."""
        response = await self.chat(messages, model, tools=tools, options=options)
        if response.content:
            yield {"content": response.content}
        if response.tool_calls:
            yield {"tool_calls": response.tool_calls}

    @abstractmethod
    def stream(
        self,
        messages: list[Message],
        model: str,
        options: dict[str, Any] | None = None,
    ) -> AsyncIterator[str]:
        """Gera uma resposta em streaming (token a token)."""
        ...

    @abstractmethod
    async def list_models(self) -> list[ModelInfo]:
        """Lista os modelos disponíveis no backend de inferência."""
        ...

    @abstractmethod
    async def health(self) -> bool:
        """Verifica se o backend de inferência está respondendo."""
        ...

    async def loaded_models(self) -> dict[str, int]:
        """Modelos carregados e tamanho aproximado em MiB.

        Provedores que não expõem esse estado retornam um dicionário vazio.
        """
        return {}

    async def unload(self, model: str) -> None:
        """Pede ao provedor que libere um modelo, quando suportado."""
