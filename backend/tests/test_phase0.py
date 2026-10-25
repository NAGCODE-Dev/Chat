"""Testes da Fase 0: API mínima, contrato de provider e migrações do banco."""

from __future__ import annotations

from pathlib import Path

import pytest

from chat.api.main import state
from chat.memory.db import Database
from chat.providers.base import Message, ModelProvider
from chat.providers.fake_provider import FakeProvider
from chat.providers.registry import available_providers, create_provider

# --- API ---


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["provider"] == "fake"
    assert body["provider_healthy"] is True


def test_chat_endpoint_persists_user_and_assistant_messages(client):
    response = client.post("/api/chat", json={"message": "Oi, Chat"})
    assert response.status_code == 200
    body = response.json()
    assert body["reply"] == "Olá! Sou o Chat (provider de teste)."
    messages = client.get(f"/api/conversations/{body['conversation_id']}/messages").json()[
        "messages"
    ]
    assert [message["role"] for message in messages] == ["user", "assistant"]


def test_chat_endpoint_rejects_unknown_conversation(client):
    response = client.post("/api/chat", json={"message": "Oi", "conversation_id": 999999})
    assert response.status_code == 404


def test_websocket_streams_tokens_then_done(client):
    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_json({"message": "Oi por streaming"})
        events = []
        while True:
            event = websocket.receive_json()
            events.append(event)
            if event["type"] in {"done", "error"}:
                break

    assert events[-1]["type"] == "done"
    assert events[0]["type"] == "conversation"
    assert "".join(
        event["content"] for event in events if event["type"] == "token"
    ) == "Olá! Sou o Chat (provider de teste)."
    conversation_id = events[-1]["conversation_id"]
    messages = client.get(f"/api/conversations/{conversation_id}/messages").json()["messages"]
    assert [message["role"] for message in messages] == ["user", "assistant"]


# --- contrato ModelProvider ---


def test_fake_provider_contract():
    provider: ModelProvider = FakeProvider()
    resp = provider.__class__  # satisfaz a checagem de tipo
    import asyncio

    out = asyncio.run(provider.chat([Message(role="user", content="oi")]))
    assert out.finish_reason == "stop"
    assert out.content
    assert out.tool_calls == []

    async def collect():
        return [c async for c in provider.stream([Message(role="user", content="oi")])]

    chunks = asyncio.run(collect())
    assert "".join(chunks) == out.content

    assert isinstance(resp, type)


def test_registry_registers_fake():
    assert "fake" in available_providers()
    assert isinstance(create_provider("fake"), FakeProvider)


def test_registry_unknown_raises():
    with pytest.raises(KeyError):
        create_provider("nao-existe")


# --- banco / migrações ---


async def test_migrations_and_tables(tmp_path: Path):
    db = Database(str(tmp_path / "test.db"))
    await db.connect()
    try:
        tables = {
            r["name"]
            for r in await db.fetch_all(
                "SELECT name FROM sqlite_master WHERE type='table' OR type='trigger'"
            )
        }
        for expected in (
            "conversations",
            "messages",
            "memories",
            "memories_fts",
            "wishlist",
            "devices",
            "audit_log",
            "settings",
            "memory_embeddings",
            "finance_transactions",
            "finance_state",
        ):
            assert expected in tables, f"falta tabela/trigger {expected}"

        # migração idempotente
        await db.migrate()
        row = await db.fetch_one("SELECT MAX(version) v FROM schema_version")
        assert row["v"] == 5

        # FTS indexa inserções
        await db.execute(
            "INSERT INTO memories(kind, key, content) VALUES ('fact','teste','teste fts')"
        )
        hits = await db.fetch_all("SELECT rowid FROM memories_fts WHERE memories_fts MATCH 'fts'")
        assert len(hits) == 1
    finally:
        await db.close()


async def test_db_state_matches_app_db(client):
    # com o TestClient ativo, o lifespan já conectou o banco
    assert state.db is not None
    row = await state.db.fetch_one("SELECT MAX(version) v FROM schema_version")
    assert row is not None and row["v"] >= 1
