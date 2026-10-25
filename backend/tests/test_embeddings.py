"""Memória semântica: embeddings, busca híbrida, fallback e reindexação."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from collections.abc import Sequence

import httpx
import pytest

from chat.api.main import state
from chat.memory.db import Database
from chat.memory.embeddings import EmbeddingError, EmbeddingProvider, OllamaEmbeddingProvider
from chat.memory.personal import MemoryStore

_CONCEPTS = {
    "carro": 0,
    "automovel": 0,
    "veiculo": 0,
    "honda": 0,
    "civic": 0,
    "praia": 1,
    "litoral": 1,
    "mar": 1,
    "trabalho": 2,
    "emprego": 2,
}


def _fold(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text.casefold())
    return "".join(char for char in normalized if not unicodedata.combining(char))


class FakeEmbedder(EmbeddingProvider):
    """Embedder determinístico com conceitos fixos para testar a segunda via."""

    name = "fake"
    model = "fake-embed"

    def __init__(self, *, fail: bool = False) -> None:
        self.fail = fail
        self.dimensions: int | None = None
        self.calls: list[list[str]] = []

    async def embed(self, texts: Sequence[str]) -> list[list[float]]:
        if self.fail:
            raise EmbeddingError("provedor de teste indisponível")
        self.calls.append(list(texts))
        vectors = [self._vector(text) for text in texts]
        self.dimensions = len(vectors[0]) if vectors else self.dimensions
        return vectors

    @staticmethod
    def _vector(text: str) -> list[float]:
        vector = [0.0] * 8
        for token in re.findall(r"[^\W_]+", _fold(text)):
            concept = _CONCEPTS.get(token)
            if concept is not None:
                vector[concept] += 1.0
            else:
                digest = hashlib.sha256(token.encode("utf-8")).digest()[0]
                vector[3 + digest % 5] += 0.05
        if not any(vector):
            vector[7] = 0.01
        return vector


async def _open_store(
    tmp_path,
    embedder: EmbeddingProvider | None,
    min_similarity: float = 0.0,
) -> tuple[Database, MemoryStore]:
    db = Database(str(tmp_path / "memory.db"))
    await db.connect()
    store = MemoryStore(
        db,
        embedder=embedder,
        embedding_model=embedder.model if embedder is not None else None,
        min_similarity=min_similarity,
    )
    return db, store


async def test_semantic_recall_without_lexical_overlap(tmp_path):
    embedder = FakeEmbedder()
    db, store = await _open_store(tmp_path, embedder)
    try:
        car = await store.remember("fact", "carro", "Meu carro é um Honda Civic")
        beach = await store.remember("fact", "praia", "Gosto de ir à praia no litoral")
        await store.reindex()

        # "automóvel" não aparece no texto: o FTS5 sozinho não encontraria.
        assert await store.recall_lexical("automóvel") == []
        results = await store.recall("automóvel", limit=2)
        assert results
        assert results[0]["id"] == car
        assert beach not in [item["id"] for item in results]
    finally:
        await db.close()


async def test_semantic_recall_filters_weak_similarity(tmp_path):
    embedder = FakeEmbedder()
    db, store = await _open_store(tmp_path, embedder, min_similarity=0.6)
    try:
        car = await store.remember("fact", "carro", "Meu carro é um Honda Civic")
        await store.remember("fact", "praia", "Gosto de ir à praia no litoral")
        await store.reindex()

        results = await store.recall("automóvel", limit=5)
        assert [item["id"] for item in results] == [car]
    finally:
        await db.close()


async def test_recall_falls_back_to_lexical_when_embeddings_fail(tmp_path):
    embedder = FakeEmbedder(fail=True)
    db, store = await _open_store(tmp_path, embedder)
    try:
        memory_id = await store.remember(
            "preference", "cor", "Prefere azul marinho"
        )
        results = await store.recall("azul marinho")
        assert [item["id"] for item in results] == [memory_id]
    finally:
        await db.close()


async def test_recall_without_embedder_uses_lexical(tmp_path):
    db, store = await _open_store(tmp_path, None)
    try:
        memory_id = await store.remember("fact", "cidade", "Mora em Belo Horizonte")
        results = await store.recall("Belo Horizonte")
        assert [item["id"] for item in results] == [memory_id]
    finally:
        await db.close()


async def test_recall_skips_embedder_when_nothing_is_indexed(tmp_path):
    embedder = FakeEmbedder()
    db, store = await _open_store(tmp_path, embedder)
    try:
        memory_id = await store.remember("preference", "cor", "Prefere azul marinho")
        results = await store.recall("azul marinho")
        assert [item["id"] for item in results] == [memory_id]
        assert embedder.calls == []

        await store.reindex()
        await store.recall("azul marinho")
        assert embedder.calls
    finally:
        await db.close()


async def test_reindex_skips_unchanged_and_refreshes_changed(tmp_path):
    embedder = FakeEmbedder()
    db, store = await _open_store(tmp_path, embedder)
    try:
        memory_id = await store.remember("fact", "carro", "Meu carro é um Honda Civic")
        status = await store.embedding_status()
        assert status["enabled"] is True
        assert status["total"] == 1
        assert status["indexed"] == 0
        assert status["pending"] == 1

        first = await store.reindex()
        assert first == {"total": 1, "indexed": 1, "skipped": 0, "failed": 0}
        assert (await store.embedding_status())["dimensions"] == 8
        second = await store.reindex()
        assert second == {"total": 1, "indexed": 0, "skipped": 1, "failed": 0}
        forced = await store.reindex(force=True)
        assert forced == {"total": 1, "indexed": 1, "skipped": 0, "failed": 0}

        await store.update(memory_id, "fact", "carro", "Meu carro agora é um Corolla")
        stale = await store.embedding_status()
        assert stale["indexed"] == 0
        assert stale["pending"] == 1

        refreshed = await store.reindex()
        assert refreshed["indexed"] == 1
        current = await store.embedding_status()
        assert current["indexed"] == 1
        assert current["stale"] == 0
    finally:
        await db.close()


async def test_deleting_memory_removes_embedding(tmp_path):
    embedder = FakeEmbedder()
    db, store = await _open_store(tmp_path, embedder)
    try:
        memory_id = await store.remember("fact", "praia", "Gosto do litoral")
        await store.reindex()
        assert await db.fetch_one(
            "SELECT memory_id FROM memory_embeddings WHERE memory_id = ?", (memory_id,)
        )
        await store.delete(memory_id)
        assert await db.fetch_one(
            "SELECT memory_id FROM memory_embeddings WHERE memory_id = ?", (memory_id,)
        ) is None
    finally:
        await db.close()


async def test_ollama_embedding_provider_parses_response():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/embed"
        payload = json.loads(request.content)
        assert payload == {"model": "nomic-embed-text", "input": ["primeiro", "segundo"]}
        return httpx.Response(
            200,
            json={"embeddings": [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]},
        )

    provider = OllamaEmbeddingProvider(
        "nomic-embed-text", transport=httpx.MockTransport(handler)
    )
    vectors = await provider.embed(["primeiro", "segundo"])
    assert vectors == [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    assert provider.dimensions == 3


async def test_ollama_embedding_provider_rejects_invalid_response():
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"embeddings": [[0.1, 0.2]]})

    provider = OllamaEmbeddingProvider(
        "nomic-embed-text", transport=httpx.MockTransport(handler)
    )
    with pytest.raises(EmbeddingError):
        await provider.embed(["um", "dois"])


def test_embedding_routes_report_status_and_reindex(client):
    store = MemoryStore(state.db, embedder=FakeEmbedder(), embedding_model="fake-embed")
    state.memory_store = store
    created = client.post(
        "/api/memories",
        json={"kind": "fact", "key": "carro", "content": "Meu carro é um Honda Civic"},
    )
    assert created.status_code == 201

    status = client.get("/api/memories/embeddings/status").json()
    assert status["enabled"] is True
    assert status["provider"] == "fake"
    assert status["total"] == 1
    assert status["pending"] == 1

    reindexed = client.post("/api/memories/embeddings/reindex")
    assert reindexed.status_code == 200
    assert reindexed.json()["indexed"] == 1

    updated = client.get("/api/memories/embeddings/status").json()
    assert updated["indexed"] == 1
    assert updated["pending"] == 0


def test_reindex_without_embeddings_is_rejected(client):
    assert client.get("/api/memories/embeddings/status").json()["enabled"] is False
    response = client.post("/api/memories/embeddings/reindex")
    assert response.status_code == 409
