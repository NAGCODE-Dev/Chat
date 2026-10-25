"""Cobertura do loop de ferramentas e da confirmação pelo WebSocket."""

from __future__ import annotations

from collections.abc import AsyncIterator

from chat.api.main import state
from chat.providers.base import ToolCall
from chat.providers.fake_provider import FakeProvider


class _ToolSequenceProvider(FakeProvider):
    def __init__(self, call: ToolCall):
        super().__init__("Item salvo com aprovação." )
        self.call = call
        self.turn = 0

    async def stream_events(self, messages, model, tools=None, options=None) -> AsyncIterator[dict]:
        if self.turn == 0:
            self.turn += 1
            yield {"tool_calls": [self.call]}
        else:
            yield {"content": self.reply}


def _provider(args: dict) -> _ToolSequenceProvider:
    provider = _ToolSequenceProvider(
        ToolCall("call_wishlist_1", "wishlist_update", args)
    )
    state.provider = provider
    state.chat_service.provider = provider
    return provider


def test_confirmed_wishlist_tool_executes_and_is_audited(client):
    _provider({"action": "add", "title": "Teclado"})
    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_json({"message": "Adicione teclado à lista"})
        assert websocket.receive_json()["type"] == "conversation"
        confirmation = websocket.receive_json()
        assert confirmation["type"] == "confirmation_required"
        assert confirmation["tool"] == "wishlist_update"
        websocket.send_json({
            "type": "confirmation", "tool_call_id": "call_wishlist_1", "approved": True,
        })
        events = []
        while True:
            event = websocket.receive_json()
            events.append(event)
            if event["type"] in {"done", "error"}:
                break

    assert events[-1]["type"] == "done"
    assert "Item salvo" in "".join(e.get("content", "") for e in events)
    rows = client.get("/api/conversations").json()["conversations"]
    assert rows
    wishlist = state.db.fetch_one
    import asyncio

    saved = asyncio.run(wishlist("SELECT title FROM wishlist WHERE title='Teclado'"))
    audit = asyncio.run(state.db.fetch_one(
        "SELECT action,confirmed_by_user FROM audit_log ORDER BY id DESC LIMIT 1"
    ))
    assert saved["title"] == "Teclado"
    assert audit == {"action": "wishlist_update", "confirmed_by_user": 1}


def test_rejected_wishlist_tool_is_not_executed(client):
    _provider({"action": "add", "title": "Monitor"})
    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_json({"message": "Adicione monitor à lista"})
        assert websocket.receive_json()["type"] == "conversation"
        confirmation = websocket.receive_json()
        websocket.send_json({
            "type": "confirmation", "tool_call_id": confirmation["tool_call_id"],
            "approved": False,
        })
        events = []
        while True:
            event = websocket.receive_json()
            events.append(event)
            if event["type"] in {"done", "error"}:
                break

    import asyncio

    saved = asyncio.run(state.db.fetch_one("SELECT id FROM wishlist WHERE title='Monitor'"))
    audit = asyncio.run(state.db.fetch_one(
        "SELECT confirmed_by_user,result FROM audit_log ORDER BY id DESC LIMIT 1"
    ))
    assert events[-1]["type"] == "done"
    assert saved is None
    assert audit == {"confirmed_by_user": 0, "result": "Ação recusada pela pessoa."}
