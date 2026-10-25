"""Cobertura da memória explícita, do CRUD e da recuperação entre conversas."""

from __future__ import annotations

from chat.api.main import state
from chat.providers.fake_provider import FakeProvider


def test_explicit_memory_is_recalled_in_a_new_conversation(client):
    assert isinstance(state.provider, FakeProvider)
    saved = client.post("/api/chat", json={"message": "Lembre que minha cor favorita é azul."})
    assert saved.status_code == 200
    first_conversation = saved.json()["conversation_id"]

    asked = client.post("/api/chat", json={"message": "Qual é minha cor favorita?"})
    assert asked.status_code == 200
    assert asked.json()["conversation_id"] != first_conversation
    system_context = "\n".join(
        message.content for message in state.provider.last_messages if message.role == "system"
    )
    assert "minha cor favorita é azul" in system_context


def test_memory_crud_and_fts_search(client):
    created = client.post(
        "/api/memories",
        json={"kind": "preference", "key": "cor", "content": "Prefere azul marinho"},
    )
    assert created.status_code == 201
    memory_id = created.json()["id"]

    listed = client.get("/api/memories", params={"kind": "preference"})
    assert any(item["id"] == memory_id for item in listed.json()["memories"])

    recalled = client.get("/api/memories/search", params={"q": "azul marinho?"})
    assert any(item["id"] == memory_id for item in recalled.json()["memories"])

    updated = client.put(
        f"/api/memories/{memory_id}",
        json={"kind": "preference", "key": "cor", "content": "Prefere verde"},
    )
    assert updated.status_code == 200
    assert (
        "prefere verde"
        in " ".join(
            item["content"] for item in client.get("/api/memories").json()["memories"]
        ).casefold()
    )

    deleted = client.delete(f"/api/memories/{memory_id}")
    assert deleted.status_code == 200
    assert client.delete(f"/api/memories/{memory_id}").status_code == 404
