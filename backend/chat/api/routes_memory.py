"""CRUD da memória pessoal persistida no SQLite."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from chat.api.state import state
from chat.memory.embeddings import EmbeddingError, EmbeddingNotConfigured
from chat.memory.greeting import build_greeting
from chat.memory.importer import parse_memory_dump
from chat.memory.personal import MemoryStore

router = APIRouter(prefix="/api/memories", tags=["memory"])
MemoryKind = Literal["personal", "preference", "project", "fact"]


class MemoryInput(BaseModel):
    kind: MemoryKind
    key: str = Field(min_length=1, max_length=120)
    content: str = Field(min_length=1, max_length=4000)


class MemoryImportInput(BaseModel):
    text: str = Field(min_length=1, max_length=200_000)
    kind: MemoryKind | None = None


def get_store() -> MemoryStore:
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco de dados não inicializado")
    if state.memory_store is not None:
        return state.memory_store
    return MemoryStore(state.db, embedder=state.embedder)


@router.get("")
async def list_memories(kind: MemoryKind | None = None) -> dict:
    return {"memories": await get_store().list_all(kind)}


@router.get("/greeting")
async def personalized_greeting() -> dict:
    """Frase curta e diferente a cada novo chat, baseada na memória."""
    return build_greeting(await get_store().stats())


@router.post("/import")
async def import_memories(payload: MemoryImportInput) -> dict:
    """Importa uma lista colada do ChatGPT, uma memória por linha."""
    store = get_store()
    parsed = parse_memory_dump(payload.text)
    if not parsed:
        raise HTTPException(
            status_code=422,
            detail="Nenhuma memória reconhecida. Cole uma lista com uma "
            "informação por linha.",
        )
    imported = 0
    skipped = 0
    for item in parsed:
        kind = payload.kind or item["kind"]
        content = item["content"].strip()
        if not content:
            skipped += 1
            continue
        await store.remember(kind, item["key"].strip(), content)
        imported += 1
    return {
        "imported": imported,
        "skipped": skipped,
        "total": len(parsed),
        "memory_count": (await store.stats())["total"],
    }


@router.get("/search")
async def search_memories(q: str = Query(min_length=1, max_length=500)) -> dict:
    return {"memories": await get_store().recall(q)}


@router.get("/embeddings/status")
async def embedding_status() -> dict:
    return await get_store().embedding_status()


@router.post("/embeddings/reindex")
async def reindex_embeddings(force: bool = False) -> dict:
    try:
        return await get_store().reindex(force=force)
    except EmbeddingNotConfigured as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    except EmbeddingError as error:
        raise HTTPException(
            status_code=502, detail=f"Falha ao gerar embeddings: {error}"
        ) from error


@router.post("", status_code=201)
async def create_memory(memory: MemoryInput) -> dict:
    store = get_store()
    memory_id = await store.remember(memory.kind, memory.key.strip(), memory.content.strip())
    return {"id": memory_id, **memory.model_dump()}


@router.put("/{memory_id}")
async def update_memory(memory_id: int, memory: MemoryInput) -> dict:
    store = get_store()
    updated = await store.update(memory_id, memory.kind, memory.key.strip(), memory.content.strip())
    if not updated:
        raise HTTPException(status_code=404, detail="Memória não encontrada")
    return {"id": memory_id, **memory.model_dump()}


@router.delete("/{memory_id}")
async def delete_memory(memory_id: int) -> dict:
    store = get_store()
    existing = await state.db.fetch_one("SELECT id FROM memories WHERE id = ?", (memory_id,))
    if existing is None:
        raise HTTPException(status_code=404, detail="Memória não encontrada")
    await store.delete(memory_id)
    return {"deleted": memory_id}
