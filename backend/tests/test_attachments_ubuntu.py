"""Anexos e rotas do computador Ubuntu."""

from __future__ import annotations

from chat.api.main import state


def test_attachment_upload_list_content_and_chat_context(client):
    upload = client.post(
        "/api/attachments",
        params={"filename": "notas.txt", "mime": "text/plain"},
        content="Minha reunião é às 15h e o projeto é Atlas.".encode(),
    )
    assert upload.status_code == 201
    attachment = upload.json()["attachment"]
    assert attachment["filename"] == "notas.txt"
    assert attachment["kind"] == "text"
    attachment_id = attachment["id"]

    listed = client.get("/api/attachments").json()["attachments"]
    assert [item["id"] for item in listed] == [attachment_id]

    content = client.get(f"/api/attachments/{attachment_id}/content")
    assert content.status_code == 200
    assert "projeto é Atlas" in content.text

    detail = client.get(f"/api/attachments/{attachment_id}").json()["attachment"]
    assert "projeto é Atlas" in detail["extracted_text"]

    reply = client.post(
        "/api/chat",
        json={
            "message": "Resuma o anexo.",
            "attachment_ids": [attachment_id],
        },
    )
    assert reply.status_code == 200
    conversation_id = reply.json()["conversation_id"]
    system_context = "\n".join(
        message.content
        for message in state.provider.last_messages
        if message.role == "system"
    )
    assert "projeto é Atlas" in system_context
    messages = client.get(
        f"/api/conversations/{conversation_id}/messages"
    ).json()["messages"]
    user = next(message for message in messages if message["role"] == "user")
    assert user["attachments"][0]["filename"] == "notas.txt"

    assert client.delete(f"/api/attachments/{attachment_id}").status_code == 200
    assert client.get(f"/api/attachments/{attachment_id}").status_code == 404


def test_attachment_upload_rejects_empty_body(client):
    response = client.post(
        "/api/attachments",
        params={"filename": "vazio.txt"},
        content=b"",
    )
    assert response.status_code == 422


def test_attachment_name_is_sanitized(client):
    response = client.post(
        "/api/attachments",
        params={"filename": "../../segredo.txt"},
        content=b"conteudo",
    )
    assert response.status_code == 201
    assert response.json()["attachment"]["filename"] == "segredo.txt"


def test_ubuntu_status_without_agent(client):
    body = client.get("/api/ubuntu/status").json()
    assert body["configured"] is False
    assert body["reachable"] is False


def test_ubuntu_task_requires_confirmation(client):
    response = client.post(
        "/api/ubuntu/tasks",
        json={"prompt": "Crie um arquivo", "confirmed": False},
    )
    assert response.status_code == 422


def test_ubuntu_task_failure_is_persisted(client, monkeypatch):
    settings = state.settings
    monkeypatch.setattr(settings, "agent_url", "https://127.0.0.1:9")
    monkeypatch.setattr(settings, "agent_token", "t" * 40)

    class FailingClient:
        async def run_opencode(self, _prompt: str) -> dict:
            raise ValueError("agente fora do ar")

    monkeypatch.setattr(
        "chat.api.routes_ubuntu.UbuntuClient",
        lambda *_args, **_kwargs: FailingClient(),
    )
    response = client.post(
        "/api/ubuntu/tasks",
        json={"prompt": "Crie um arquivo", "confirmed": True},
    )
    assert response.status_code == 502
    tasks = client.get("/api/ubuntu/tasks").json()["tasks"]
    assert tasks[0]["status"] == "failed"
    assert "agente fora do ar" in tasks[0]["output"]
