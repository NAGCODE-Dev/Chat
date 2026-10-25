"""Memória pessoal estruturada: fatos, preferências, projetos.

A memória é independente do modelo: armazenada em SQLite e recuperada por
duas vias. O FTS5 continua sendo a base lexical e o fallback obrigatório;
quando há um provedor de embeddings configurado, a busca semântica entra
como segunda via e os resultados são combinados por Reciprocal Rank Fusion
(RRF).
"""

from __future__ import annotations

import hashlib
import math
import re
import struct

from chat.core.logging import get_logger
from chat.memory.db import Database
from chat.memory.embeddings import (
    EmbeddingError,
    EmbeddingNotConfigured,
    EmbeddingProvider,
)

log = get_logger("chat.memory.personal")

# tipos válidos de memória
KINDS = ("personal", "preference", "project", "fact")
_STOPWORDS = {
    "a",
    "as",
    "o",
    "os",
    "um",
    "uma",
    "de",
    "do",
    "da",
    "dos",
    "das",
    "e",
    "é",
    "em",
    "no",
    "na",
    "nos",
    "nas",
    "que",
    "qual",
    "quais",
    "eu",
    "meu",
    "minha",
    "meus",
    "minhas",
    "pra",
    "para",
    "com",
}
_RRF_K = 60
_DEFAULT_BATCH = 16


def _content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _pack_vector(vector: list[float]) -> bytes:
    return struct.pack(f"<{len(vector)}f", *vector)


def _unpack_vector(blob: bytes) -> list[float]:
    if not blob or len(blob) % 4 != 0:
        return []
    return list(struct.unpack(f"<{len(blob) // 4}f", blob))


def _cosine(left: list[float], right: list[float]) -> float:
    if not left or len(left) != len(right):
        return 0.0
    dot = 0.0
    left_norm = 0.0
    right_norm = 0.0
    for a, b in zip(left, right, strict=True):
        dot += a * b
        left_norm += a * a
        right_norm += b * b
    if left_norm <= 0 or right_norm <= 0:
        return 0.0
    return dot / (math.sqrt(left_norm) * math.sqrt(right_norm))


def _merge_rrf(
    lexical: list[dict], semantic: list[dict], limit: int
) -> list[dict]:
    """Combina duas listas ranqueadas por RRF, preservando campos públicos."""
    scores: dict[int, float] = {}
    items: dict[int, dict] = {}
    for results in (lexical, semantic):
        for rank, item in enumerate(results, start=1):
            memory_id = item["id"]
            items.setdefault(memory_id, item)
            scores[memory_id] = scores.get(memory_id, 0.0) + 1.0 / (_RRF_K + rank)
    ordered = sorted(scores, key=lambda memory_id: (-scores[memory_id], memory_id))
    return [items[memory_id] for memory_id in ordered[:limit]]


class MemoryStore:
    def __init__(
        self,
        db: Database,
        embedder: EmbeddingProvider | None = None,
        embedding_model: str | None = None,
        batch_size: int = _DEFAULT_BATCH,
        min_similarity: float = 0.0,
    ) -> None:
        self.db = db
        self.embedder = embedder
        self.embedding_model = embedding_model or (
            getattr(embedder, "model", None) if embedder is not None else None
        )
        self.batch_size = max(1, min(batch_size, 64))
        self.min_similarity = max(0.0, min(min_similarity, 1.0))

    async def remember(
        self, kind: str, key: str, content: str, source_message_id: int | None = None
    ) -> int:
        """Cria ou atualiza uma memória (por kind + key)."""
        if kind not in KINDS:
            raise ValueError(f"tipo de memória inválido: {kind}")
        existing = await self.db.fetch_one(
            "SELECT id, content FROM memories WHERE kind = ? AND key = ?", (kind, key)
        )
        if existing:
            await self.db.execute(
                "UPDATE memories SET content = ?, updated_at = datetime('now'), "
                "source_message_id = ?, active = 1 WHERE id = ?",
                (content, source_message_id, existing["id"]),
            )
            if existing["content"] != content:
                await self._invalidate_embedding(existing["id"])
            return existing["id"]
        return await self.db.execute(
            "INSERT INTO memories(kind, key, content, source_message_id) VALUES (?, ?, ?, ?)",
            (kind, key, content, source_message_id),
        )

    async def recall(
        self, query: str, limit: int = 5, semantic: bool = True
    ) -> list[dict]:
        """Recupera memórias relevantes combinando FTS5 e embeddings.

        A busca lexical sempre roda. Se o provedor de embeddings estiver
        ausente ou falhar, o resultado lexical é devolvido sem interrupção.
        ``semantic=False`` evita a chamada ao modelo de embeddings em turnos
        simples, priorizando latência.
        """
        limit = max(1, min(limit, 20))
        lexical = await self.recall_lexical(query, limit=max(limit * 3, limit))
        if not semantic or self.embedder is None or not self.embedding_model:
            return lexical[:limit]
        indexed = await self.db.fetch_one(
            "SELECT 1 FROM memory_embeddings WHERE model = ? LIMIT 1",
            (self.embedding_model,),
        )
        if indexed is None:
            # Sem nenhum vetor indexado, não há segunda via a consultar.
            return lexical[:limit]
        try:
            semantic = await self._recall_semantic(query, limit=max(limit * 3, 10))
        except Exception as error:  # noqa: BLE001 - a segunda via nunca derruba a primeira
            log.warning("busca semântica indisponível; usando FTS5: %s", error)
            return lexical[:limit]
        if not semantic:
            return lexical[:limit]
        return _merge_rrf(lexical, semantic, limit)

    async def recall_lexical(self, query: str, limit: int = 5) -> list[dict]:
        """Recupera memórias relevantes por busca textual (FTS5)."""
        # Cria uma expressão FTS segura: não aceita operadores/sintaxe fornecidos
        # pelo usuário e limita o custo da busca.
        terms = [
            term
            for term in dict.fromkeys(re.findall(r"[^\W_]+", query.casefold(), flags=re.UNICODE))
            if term not in _STOPWORDS and len(term) > 1
        ][:8]
        if not terms:
            return []
        expression = " OR ".join(f'"{term}"' for term in terms)
        return await self.db.fetch_all(
            "SELECT m.id, m.kind, m.key, m.content FROM memories m "
            "JOIN memories_fts f ON m.id = f.rowid "
            "WHERE memories_fts MATCH ? AND m.active = 1 "
            "ORDER BY f.rank LIMIT ?",
            (expression, max(1, min(limit, 20))),
        )

    async def _recall_semantic(self, query: str, limit: int) -> list[dict]:
        if self.embedder is None or not self.embedding_model:
            return []
        vectors = await self.embedder.embed([query])
        if len(vectors) != 1 or not vectors[0]:
            raise EmbeddingError("O provedor não gerou um vetor para a consulta.")
        query_vector = vectors[0]
        rows = await self.db.fetch_all(
            "SELECT m.id, m.kind, m.key, m.content, e.vector "
            "FROM memories m JOIN memory_embeddings e ON e.memory_id = m.id "
            "WHERE m.active = 1 AND e.model = ?",
            (self.embedding_model,),
        )
        scored: list[tuple[float, dict]] = []
        for row in rows:
            vector = _unpack_vector(row["vector"])
            if len(vector) != len(query_vector):
                continue
            score = _cosine(query_vector, vector)
            if score <= 0 or score < self.min_similarity:
                continue
            scored.append((score, row))
        scored.sort(key=lambda item: (-item[0], item[1]["id"]))
        return [
            {key: row[key] for key in ("id", "kind", "key", "content")}
            for _, row in scored[:limit]
        ]

    async def list_all(self, kind: str | None = None) -> list[dict]:
        if kind:
            return await self.db.fetch_all(
                "SELECT id, kind, key, content, updated_at FROM memories "
                "WHERE kind = ? AND active = 1 ORDER BY updated_at DESC",
                (kind,),
            )
        return await self.db.fetch_all(
            "SELECT id, kind, key, content, updated_at FROM memories "
            "WHERE active = 1 ORDER BY updated_at DESC"
        )

    async def forget(self, memory_id: int) -> None:
        """Desativa a memória (exclusão lógica)."""
        await self.db.execute("UPDATE memories SET active = 0 WHERE id = ?", (memory_id,))
        await self._invalidate_embedding(memory_id)

    async def delete(self, memory_id: int) -> None:
        """Exclui definitivamente."""
        await self._invalidate_embedding(memory_id)
        await self.db.execute("DELETE FROM memories WHERE id = ?", (memory_id,))

    async def update(self, memory_id: int, kind: str, key: str, content: str) -> bool:
        if kind not in KINDS:
            raise ValueError(f"tipo de memória inválido: {kind}")
        current = await self.db.fetch_one(
            "SELECT id, content FROM memories WHERE id = ?", (memory_id,)
        )
        if current is None:
            return False
        await self.db.execute(
            "UPDATE memories SET kind = ?, key = ?, content = ?, active = 1, "
            "updated_at = datetime('now') WHERE id = ?",
            (kind, key, content, memory_id),
        )
        if current["content"] != content:
            await self._invalidate_embedding(memory_id)
        return True

    async def _invalidate_embedding(self, memory_id: int) -> None:
        await self.db.execute(
            "DELETE FROM memory_embeddings WHERE memory_id = ?", (memory_id,)
        )

    async def _save_embedding(
        self, memory_id: int, content: str, vector: list[float]
    ) -> None:
        if self.embedder is None or not self.embedding_model:
            raise EmbeddingNotConfigured("Embeddings não estão configurados.")
        if not vector:
            raise EmbeddingError("Vetor de embedding vazio.")
        await self.db.execute(
            "INSERT INTO memory_embeddings(memory_id, model, dimensions, vector, content_hash) "
            "VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT(memory_id) DO UPDATE SET model = excluded.model, "
            "dimensions = excluded.dimensions, vector = excluded.vector, "
            "content_hash = excluded.content_hash, updated_at = datetime('now')",
            (
                memory_id,
                self.embedding_model,
                len(vector),
                _pack_vector(vector),
                _content_hash(content),
            ),
        )

    async def reindex(
        self, force: bool = False, batch_size: int | None = None
    ) -> dict:
        """Gera embeddings para memórias novas ou alteradas.

        Sem `force`, memórias cujo conteúdo e modelo não mudaram são puladas.
        """
        if self.embedder is None or not self.embedding_model:
            raise EmbeddingNotConfigured("Embeddings não estão configurados.")
        batch_size = max(1, min(batch_size or self.batch_size, 64))
        rows = await self.db.fetch_all(
            "SELECT m.id, m.content, e.model, e.content_hash "
            "FROM memories m LEFT JOIN memory_embeddings e ON e.memory_id = m.id "
            "WHERE m.active = 1 ORDER BY m.id"
        )
        pending = [
            row
            for row in rows
            if force
            or row["model"] != self.embedding_model
            or row["content_hash"] != _content_hash(row["content"])
        ]
        indexed = 0
        for start in range(0, len(pending), batch_size):
            batch = pending[start : start + batch_size]
            vectors = await self.embedder.embed([row["content"] for row in batch])
            if len(vectors) != len(batch):
                raise EmbeddingError("O provedor devolveu uma quantidade inesperada de vetores.")
            for row, vector in zip(batch, vectors, strict=True):
                await self._save_embedding(row["id"], row["content"], vector)
                indexed += 1
        return {
            "total": len(rows),
            "indexed": indexed,
            "skipped": len(rows) - len(pending),
            "failed": 0,
        }

    async def embedding_status(self) -> dict:
        total_row = await self.db.fetch_one(
            "SELECT COUNT(*) AS total FROM memories WHERE active = 1"
        )
        total = int(total_row["total"]) if total_row else 0
        enabled = self.embedder is not None and bool(self.embedding_model)
        indexed = 0
        stale = 0
        if enabled:
            rows = await self.db.fetch_all(
                "SELECT m.id, m.content, e.model, e.content_hash "
                "FROM memories m LEFT JOIN memory_embeddings e ON e.memory_id = m.id "
                "WHERE m.active = 1"
            )
            for row in rows:
                if row["model"] != self.embedding_model:
                    continue
                if row["content_hash"] == _content_hash(row["content"]):
                    indexed += 1
                else:
                    stale += 1
        available = False
        if self.embedder is not None:
            try:
                available = await self.embedder.health()
            except Exception as error:  # noqa: BLE001 - status nunca falha pelo provedor
                log.warning("saúde dos embeddings indisponível: %s", error)
        dimensions = getattr(self.embedder, "dimensions", None) if enabled else None
        if dimensions is None and enabled:
            stored = await self.db.fetch_one(
                "SELECT dimensions FROM memory_embeddings WHERE model = ? LIMIT 1",
                (self.embedding_model,),
            )
            if stored:
                dimensions = int(stored["dimensions"])
        return {
            "enabled": enabled,
            "provider": self.embedder.name if self.embedder is not None else None,
            "model": self.embedding_model if enabled else None,
            "available": available,
            "total": total,
            "indexed": indexed,
            "stale": stale,
            "pending": max(0, total - indexed),
            "dimensions": dimensions,
            "min_similarity": self.min_similarity if enabled else None,
        }

    async def stats(self) -> dict:
        """Resumo usado pela saudação e por telas de acompanhamento."""
        rows = await self.db.fetch_all(
            "SELECT kind, COUNT(*) AS count FROM memories "
            "WHERE active = 1 GROUP BY kind"
        )
        kinds = {row["kind"]: int(row["count"]) for row in rows}
        total = sum(kinds.values())
        latest = await self.db.fetch_one(
            "SELECT key, content FROM memories WHERE active = 1 "
            "ORDER BY updated_at DESC, id DESC LIMIT 1"
        )
        return {"total": total, "kinds": kinds, "latest": latest}

    async def remember_explicit_instruction(self, text: str, source_message_id: int) -> int | None:
        """Salva fatos apenas quando a pessoa pede explicitamente para lembrar."""
        match = re.match(
            r"^\s*(?:lembre(?:-se)?(?:\s+de)?|guarde(?:\s+na\s+mem[oó]ria)?|"
            r"memorize|n[aã]o\s+esque[cç]a)(?:\s+que)?\s*[:,—-]?\s*(.+?)\s*[.!?]*\s*$",
            text,
            flags=re.IGNORECASE | re.DOTALL,
        )
        if not match:
            return None
        content = match.group(1).strip()
        if not content:
            return None
        key = f"explicit:{content.casefold()[:120]}"
        return await self.remember("fact", key, content, source_message_id)
