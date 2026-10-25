from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect

from chat.api.main import app, state
from chat.tools.agent import AgentArgs
from chat.tools.base import ToolError
from chat.tools.web import OpenURL
from chat.tools.wishlist import WishlistUpdate


def test_agent_args_require_parameters_matching_the_action():
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "open_app"})
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "read_file"})
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "read_file", "path": "relativo.txt"})
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "status", "path": "/tmp"})
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "write_file", "path": "/tmp/nota.txt"})
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "create_dir", "path": "/tmp/pasta", "content": "x"})
    assert AgentArgs.model_validate({"action": "open_app", "app": "terminal"}).app == "terminal"
    assert AgentArgs.model_validate(
        {"action": "read_file", "path": "/home/pessoa/nota.txt"}
    ).path == "/home/pessoa/nota.txt"
    note = AgentArgs.model_validate(
        {
            "action": "write_file",
            "path": "/home/pessoa/nota.txt",
            "content": "  lembrete com espaços  \n",
        }
    )
    assert note.content == "  lembrete com espaços  \n"


def test_tool_schemas_reject_extra_or_unsafe_arguments():
    with pytest.raises(ValidationError):
        AgentArgs.model_validate({"action": "open_app", "app": "terminal", "command": "rm -rf"})
    with pytest.raises(ToolError):
        WishlistUpdate.__new__(WishlistUpdate).validate_arguments(
            {"action": "add", "title": "Teclado", "unexpected": True}
        )
    url_tool = OpenURL()
    with pytest.raises(ToolError):
        url_tool.validate_arguments({"url": "file:///etc/passwd"})
    with pytest.raises(ToolError):
        url_tool.validate_arguments({"url": "https://user:secret@example.com"})
    assert url_tool.validate_arguments({"url": "https://example.com"}) == {
        "url": "https://example.com"
    }


def test_chat_message_size_limit_applies_to_http_and_websocket(client):
    oversized = "x" * 12_001
    response = client.post("/api/chat", json={"message": oversized})
    assert response.status_code == 422

    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_json({"message": oversized})
        event = websocket.receive_json()
    assert event["type"] == "error"
    assert "at most 12000 characters" in event["detail"]


def test_chat_request_rejects_extra_fields(client):
    response = client.post("/api/chat", json={"message": "oi", "unexpected": "value"})
    assert response.status_code == 422


def test_websocket_rejects_oversized_frames(client):
    with client.websocket_connect("/api/ws/chat") as websocket:
        websocket.send_text('{"message":"' + ("x" * (64 * 1024)) + '"}')
        event = websocket.receive_json()
    assert event["type"] == "error"
    assert "64 KiB" in event["detail"]


def test_api_token_is_required_for_http_and_websocket(client):
    token = "api-token-for-test-12345678901234567890"
    state.settings.api_token = token
    assert client.get("/api/settings").status_code == 401
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/api/settings", headers=headers).status_code == 200

    with pytest.raises(WebSocketDisconnect) as disconnected, client.websocket_connect(
        "/api/ws/chat"
    ):
        pass
    assert disconnected.value.code == 1008

    with client.websocket_connect("/api/ws/chat", headers=headers) as websocket:
        websocket.send_json({"message": "oi"})
        event = websocket.receive_json()
        while event["type"] not in {"done", "error"}:
            event = websocket.receive_json()
        assert event["type"] == "done"


def test_non_loopback_bind_requires_api_token(tmp_path, monkeypatch):
    monkeypatch.setenv("CHAT_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("CHAT_HOST", "0.0.0.0")
    monkeypatch.delenv("CHAT_API_TOKEN", raising=False)
    with pytest.raises(RuntimeError, match="CHAT_API_TOKEN é obrigatório"), TestClient(app):
        pass


def test_api_token_minimum_length_is_enforced(tmp_path, monkeypatch):
    monkeypatch.setenv("CHAT_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("CHAT_HOST", "127.0.0.1")
    monkeypatch.setenv("CHAT_API_TOKEN", "too-short")
    with pytest.raises(RuntimeError, match="pelo menos 32 caracteres"), TestClient(app):
        pass
