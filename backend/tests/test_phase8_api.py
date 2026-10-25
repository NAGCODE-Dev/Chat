from __future__ import annotations

import asyncio

from chat.api.main import state


def test_wishlist_crud_and_model_settings(client):
    created = client.post(
        "/api/wishlist", json={"title": "Headphones", "notes": "ANC", "priority": 2}
    )
    assert created.status_code == 201
    item_id = created.json()["id"]
    assert created.json()["status"] == "aberto"

    updated = client.patch(f"/api/wishlist/{item_id}", json={"status": "comprado"})
    assert updated.status_code == 200
    assert client.get("/api/wishlist", params={"status": "comprado"}).json()["items"][0]["title"] == "Headphones"
    assert client.delete(f"/api/wishlist/{item_id}").status_code == 200

    initial = client.get("/api/settings")
    assert initial.status_code == 200
    assert "ollama" in initial.json()["providers"]
    assert client.get("/api/settings/models", params={"provider": "fake"}).json()["models"][0]["id"] == "fake-model"
    changed = client.put("/api/settings/model", json={"provider": "fake", "model": "fake-next"})
    assert changed.status_code == 200
    assert client.get("/api/settings").json()["model"] == "fake-next"
    stored = asyncio.run(state.db.fetch_one(
        "SELECT value_json FROM settings WHERE key='model'"
    ))
    assert stored["value_json"] == '"fake-next"'
