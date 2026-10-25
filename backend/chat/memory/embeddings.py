"""Embeddings para a segunda via de recuperação da memória.

O contrato `EmbeddingProvider` é independente do modelo de linguagem e do
banco. A implementação Ollama usa a API local de embeddings. A memória
continua funcionando sem embeddings: a busca lexical por FTS5 é sempre
executada e serve de fallback quando o provedor não está configurado ou
falha.
"""

from __future__ import annotations

import math
from abc import ABC, abstractmethod
from collections.abc import Sequence

import httpx

from chat.core.logging import get_logger

log = get_logger("chat.memory.embeddings")


class EmbeddingError(Exception):
    """Falha normalizada ao gerar embeddings."""


class EmbeddingNotConfigured(EmbeddingError):
    """Não há provedor de embeddings configurado."""


class EmbeddingProvider(ABC):
    """Contrato mínimo para transformar textos em vetores."""

    name: str
    model: str

    @abstractmethod
    async def embed(self, texts: Sequence[str]) -> list[list[float]]:
        """Gera um vetor por texto, preservando a ordem de entrada."""
        ...

    async def health(self) -> bool:
        """Indica se o provedor está pronto para gerar embeddings."""
        return True


class OllamaEmbeddingProvider(EmbeddingProvider):
    """Gera embeddings pelo endpoint local `/api/embed` do Ollama."""

    name = "ollama"

    def __init__(
        self,
        model: str,
        base_url: str = "http://127.0.0.1:11434",
        timeout: float = 30.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        if not model.strip():
            raise ValueError("Informe o modelo de embeddings.")
        self.model = model.strip()
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._transport = transport
        self.dimensions: int | None = None

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(timeout=self.timeout, transport=self._transport)

    async def embed(self, texts: Sequence[str]) -> list[list[float]]:
        if not texts:
            return []
        payload = {"model": self.model, "input": list(texts)}
        try:
            async with self._client() as client:
                response = await client.post(f"{self.base_url}/api/embed", json=payload)
                response.raise_for_status()
        except httpx.HTTPError as error:
            raise EmbeddingError(f"Ollama indisponível ou erro HTTP: {error}") from error
        try:
            data = response.json()
        except ValueError as error:
            raise EmbeddingError("Resposta de embeddings não é JSON válido.") from error
        vectors = data.get("embeddings")
        if not isinstance(vectors, list) or len(vectors) != len(texts):
            raise EmbeddingError("Resposta de embeddings com quantidade inesperada de vetores.")
        converted: list[list[float]] = []
        for vector in vectors:
            if not isinstance(vector, list) or not vector:
                raise EmbeddingError("Resposta de embeddings com vetor vazio.")
            try:
                values = [float(value) for value in vector]
            except (TypeError, ValueError) as error:
                raise EmbeddingError("Vetor de embedding contém valor inválido.") from error
            if any(not math.isfinite(value) for value in values):
                raise EmbeddingError("Vetor de embedding contém valor não finito.")
            if converted and len(values) != len(converted[0]):
                raise EmbeddingError("Vetores de embedding com dimensões diferentes.")
            converted.append(values)
        if self.dimensions is None:
            self.dimensions = len(converted[0])
        return converted

    async def health(self) -> bool:
        try:
            async with self._client() as client:
                response = await client.get(f"{self.base_url}/api/tags")
                response.raise_for_status()
                models = response.json().get("models", [])
        except (httpx.HTTPError, ValueError, AttributeError):
            return False
        names = {item.get("name", "") for item in models if isinstance(item, dict)}
        wanted = self.model
        return wanted in names or any(
            name.split(":")[0] == wanted.split(":")[0] for name in names if name
        )
