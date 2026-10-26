from __future__ import annotations

import asyncio
import json
import sqlite3
from collections import defaultdict, deque

from fastapi import HTTPException, Request
from fastapi.testclient import TestClient

from ubuntu_agent import server


def test_agent_requires_long_bearer_token(monkeypatch, tmp_path):
    monkeypatch.setattr(server, "_token", "x" * 31)
    with TestClient(server.app) as client:
        assert client.get("/status").status_code == 503

    monkeypatch.setattr(server, "_token", "a" * 40)
    with TestClient(server.app) as client:
        assert client.get("/status").status_code == 401
        assert client.get("/status", headers={"Authorization": f"Bearer {'a' * 40}"}).json()["status"] == "ok"


def test_open_app_requires_confirmation_and_uses_allowlist(monkeypatch, tmp_path):
    token = "b" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    monkeypatch.setattr(server.shutil, "which", lambda _: "/usr/bin/xdg-open")
    launched = {}

    class Process:
        pid = 987

        async def wait(self):
            return 0

    async def fake_spawn(executable, *args, **kwargs):
        launched["argv"] = (executable, *args)
        launched["env"] = kwargs["env"]
        return Process()

    monkeypatch.setenv("CHAT_AGENT_TOKEN", token)
    monkeypatch.setenv("CHAT_AGENT_TLS_CLIENT_KEY", "/secret/client.key")
    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_spawn)
    headers = {"Authorization": f"Bearer {token}"}
    body = {
        "command_id": "99b58b02-2324-4e69-a18b-6bf87b9071f2",
        "action": "open_app", "params": {"app": "browser"},
    }
    with TestClient(server.app) as client:
        denied = client.post("/command", json=body, headers=headers)
        assert denied.json()["status"] == "needs_confirmation"
        assert not launched

        body["requires_confirmation"] = True
        opened = client.post("/command", json=body, headers=headers)
        assert opened.json()["status"] == "ok"
        assert launched["argv"] == ("/usr/bin/xdg-open", "--new-window", "about:blank")
        assert not any(key.startswith("CHAT_AGENT_") for key in launched["env"])
        assert launched["env"]["PATH"] == "/usr/bin"

        body["params"] = {"app": "browser", "url": "https://invalid.test"}
        body["command_id"] = "99b58b02-2324-4e69-a18b-6bf87b9071f3"
        assert client.post("/command", json=body, headers=headers).status_code == 422
    journal = (tmp_path / "journal.jsonl").read_text()
    assert '"status": "needs_confirmation"' in journal
    assert '"status": "ok"' in journal


def test_launcher_failure_is_audited_as_failed(monkeypatch, tmp_path):
    monkeypatch.setattr(server, "_token", "c" * 40)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    monkeypatch.setattr(server.shutil, "which", lambda _: "/usr/bin/firefox")

    class Process:
        pid = 123

        async def wait(self):
            return 1

    async def failed_spawn(*_args, **_kwargs):
        return Process()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", failed_spawn)
    with TestClient(server.app) as client:
        response = client.post(
            "/command",
            json={
                "command_id": "199ca844-23ae-4972-8469-773a5af5a4e8",
                "action": "open_app",
                "params": {"app": "browser"},
                "requires_confirmation": True,
            },
            headers={"Authorization": f"Bearer {'c' * 40}"},
        )
    assert response.json()["status"] == "failed"
    assert '"status": "failed"' in (tmp_path / "journal.jsonl").read_text()


def test_command_id_replay_is_rejected(monkeypatch, tmp_path):
    token = "d" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    body = {
        "command_id": "c4ce4e87-5e8f-4ceb-98b4-8f7d7b550792",
        "action": "status",
        "params": {},
    }
    headers = {"Authorization": f"Bearer {token}"}
    with TestClient(server.app) as client:
        assert client.post("/command", json=body, headers=headers).status_code == 200
        replay = client.post("/command", json=body, headers=headers)
    assert replay.status_code == 409
    events = [json.loads(line) for line in (tmp_path / "journal.jsonl").read_text().splitlines()]
    assert any(event["status"] == "replay_rejected" for event in events)
    assert (tmp_path / "journal.jsonl").stat().st_mode & 0o777 == 0o600


def test_command_index_migrates_journal_and_persists_ids(monkeypatch, tmp_path):
    journal = tmp_path / "journal.jsonl"
    journal.write_text(
        '{"command_id":"0bb50fb4-931a-42aa-a5ad-96dcb24ed98f","status":"received"}\n'
        '{"command_id":"4bb50fb4-931a-42aa-a5ad-96dcb24ed98f","status":"needs_confirmation"}\n'
        "invalid json\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(server, "_journal", journal)
    historical = server.Command(
        command_id="0bb50fb4-931a-42aa-a5ad-96dcb24ed98f", action="status"
    )
    fresh = server.Command(
        command_id="d4ec2766-9ceb-4d71-89ad-2ebf8063f302", action="status"
    )
    assert not server._claim_command(historical)
    assert server._claim_command(fresh)
    assert not server._claim_command(fresh)

    index = tmp_path / "journal.jsonl.commands.sqlite3"
    assert index.stat().st_mode & 0o777 == 0o600
    with sqlite3.connect(index) as connection:
        rows = connection.execute("SELECT command_id FROM processed_commands").fetchall()
    assert {row[0] for row in rows} == {
        "0bb50fb4-931a-42aa-a5ad-96dcb24ed98f",
        "d4ec2766-9ceb-4d71-89ad-2ebf8063f302",
    }


def test_agent_rate_limits_authenticated_requests(monkeypatch):
    token = "r" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_request_limit", 1)
    monkeypatch.setattr(server, "_request_times", defaultdict(deque))
    headers = {"Authorization": f"Bearer {token}"}
    with TestClient(server.app) as client:
        assert client.get("/status", headers=headers).status_code == 200
        limited = client.get("/status", headers=headers)
    assert limited.status_code == 429
    assert int(limited.headers["retry-after"]) > 0


def test_agent_caps_rate_limit_memory_by_client(monkeypatch):
    token = "m" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_request_limit", 10)
    monkeypatch.setattr(server, "_request_max_clients", 1)
    monkeypatch.setattr(server, "_request_times", defaultdict(deque))

    def request_for(host):
        return Request(
            {
                "type": "http",
                "method": "GET",
                "path": "/status",
                "headers": [],
                "client": (host, 1234),
                "server": ("127.0.0.1", 8765),
            }
        )

    asyncio.run(server.authenticate(request_for("192.0.2.1"), f"Bearer {token}"))
    try:
        asyncio.run(server.authenticate(request_for("192.0.2.2"), f"Bearer {token}"))
        raise AssertionError("A nova origem deveria ter sido limitada")
    except HTTPException as error:
        assert error.status_code == 429


def test_file_actions_require_confirmation_and_respect_allowed_roots(monkeypatch, tmp_path):
    from uuid import uuid4

    token = "f" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    allowed = tmp_path / "allowed"
    allowed.mkdir()
    (allowed / "nota.txt").write_text("conteúdo seguro", encoding="utf-8")
    (allowed / "binario.bin").write_bytes(b"\x00\x01\x02")
    outside = tmp_path / "fora.txt"
    outside.write_text("segredo", encoding="utf-8")
    monkeypatch.setenv("CHAT_AGENT_ALLOWED_DIRS", str(allowed))
    headers = {"Authorization": f"Bearer {token}"}

    def send(action: str, path: str, *, confirmed: bool = True):
        return client.post(
            "/command",
            json={
                "command_id": str(uuid4()),
                "action": action,
                "params": {"path": path},
                "requires_confirmation": confirmed,
            },
            headers=headers,
        )

    with TestClient(server.app) as client:
        pending = send("list_files", str(allowed), confirmed=False)
        assert pending.json()["status"] == "needs_confirmation"

        listed = send("list_files", str(allowed))
        assert listed.json()["status"] == "ok"
        assert "nota.txt" in listed.json()["message"]

        read = send("read_file", str(allowed / "nota.txt"))
        assert read.json() == {
            "command_id": read.json()["command_id"],
            "status": "ok",
            "message": "conteúdo seguro",
        }

        assert send("read_file", str(allowed / "binario.bin")).json()["status"] == "failed"
        assert send("read_file", str(outside)).json()["status"] == "denied"
        assert send("list_files", str(allowed / "nao-existe")).json()["status"] == "failed"
        assert send("read_file", "nota.txt").json()["status"] == "failed"

        monkeypatch.delenv("CHAT_AGENT_ALLOWED_DIRS")
        assert send("list_files", str(allowed)).json()["status"] == "failed"

    journal = (tmp_path / "journal.jsonl").read_text()
    assert '"status": "denied"' in journal
    assert '"status": "ok"' in journal
    assert "conteúdo seguro" not in journal


def test_write_actions_require_confirmation_and_use_separate_roots(monkeypatch, tmp_path):
    from uuid import uuid4

    token = "w" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    read_root = tmp_path / "leitura"
    write_root = tmp_path / "escrita"
    read_root.mkdir()
    write_root.mkdir()
    outside = tmp_path / "fora"
    outside.mkdir()
    (write_root / "link").symlink_to(outside, target_is_directory=True)
    monkeypatch.setenv("CHAT_AGENT_ALLOWED_DIRS", str(read_root))
    monkeypatch.setenv("CHAT_AGENT_WRITE_DIRS", str(write_root))
    headers = {"Authorization": f"Bearer {token}"}

    def send(action, params, *, confirmed=True):
        return client.post(
            "/command",
            json={
                "command_id": str(uuid4()),
                "action": action,
                "params": params,
                "requires_confirmation": confirmed,
            },
            headers=headers,
        )

    target = write_root / "nota.txt"
    with TestClient(server.app) as client:
        pending = send(
            "write_file", {"path": str(target), "content": "linha 1\n"},
            confirmed=False,
        )
        assert pending.json()["status"] == "needs_confirmation"
        assert not target.exists()

        written = send(
            "write_file", {"path": str(target), "content": "linha 1\nlinha 2\n"}
        )
        assert written.json()["status"] == "ok"
        assert target.read_text(encoding="utf-8") == "linha 1\nlinha 2\n"

        appended = send("append_file", {"path": str(target), "content": "linha 3\n"})
        assert appended.json()["status"] == "ok"
        assert target.read_text(encoding="utf-8") == "linha 1\nlinha 2\nlinha 3\n"

        created = send("create_dir", {"path": str(write_root / "diario")})
        assert created.json()["status"] == "ok"
        assert (write_root / "diario").is_dir()

        assert send(
            "write_file", {"path": str(read_root / "nao.txt"), "content": "x"}
        ).json()["status"] == "denied"
        assert send(
            "write_file", {"path": str(write_root / ".." / "fora.txt"), "content": "x"}
        ).json()["status"] == "denied"
        assert send(
            "write_file", {"path": str(write_root / "link" / "fora.txt"), "content": "x"}
        ).json()["status"] == "denied"
        assert send(
            "write_file", {"path": str(write_root / "grande.txt"), "content": "x" * (32 * 1024 + 1)}
        ).json()["status"] == "failed"
        assert send(
            "write_file", {"path": str(write_root / "sem_pasta" / "x.txt"), "content": "x"}
        ).json()["status"] == "failed"
        assert send("create_dir", {"path": str(write_root / "nota.txt")}).json()["status"] == "failed"

        monkeypatch.delenv("CHAT_AGENT_WRITE_DIRS")
        assert send(
            "write_file", {"path": str(write_root / "outra.txt"), "content": "x"}
        ).json()["status"] == "failed"

    journal = (tmp_path / "journal.jsonl").read_text()
    assert "linha 1" not in journal
    assert "linha 3" not in journal
    assert '"status": "ok"' in journal
    assert '"status": "denied"' in journal


def test_agent_rejects_oversized_body_and_unbounded_params(monkeypatch, tmp_path):
    token = "z" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    headers = {"Authorization": f"Bearer {token}"}
    with TestClient(server.app) as client:
        oversized = client.post(
            "/command", content=b"x" * (128 * 1024 + 1), headers=headers
        )
        assert oversized.status_code == 413
        chunked = client.post(
            "/command",
            content=iter([b"x" * (64 * 1024), b"x" * (64 * 1024 + 1)]),
            headers=headers,
        )
        assert chunked.status_code == 413

        body = {
            "command_id": "f4a0986b-564e-4e34-94c9-76b4433867b3",
            "action": "open_app",
            "params": {
                "app": "browser",
                "extra": "argument",
                "outro": "argumento",
                "mais": "argumento",
            },
            "requires_confirmation": True,
        }
        too_many_params = client.post("/command", json=body, headers=headers)
    assert too_many_params.status_code == 422
    assert not (tmp_path / "journal.jsonl").exists()


def test_opencode_action_requires_confirmation_and_parses_events(monkeypatch, tmp_path):
    token = "o" * 40
    monkeypatch.setattr(server, "_token", token)
    monkeypatch.setattr(server, "_journal", tmp_path / "journal.jsonl")
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    binary = tmp_path / "opencode"
    binary.write_text("#!/bin/sh\n", encoding="utf-8")
    monkeypatch.setenv("CHAT_AGENT_ALLOWED_DIRS", str(workspace))
    monkeypatch.setenv("CHAT_AGENT_WRITE_DIRS", str(workspace))
    monkeypatch.setenv("CHAT_AGENT_OPENCODE_BIN", str(binary))
    monkeypatch.setenv("CHAT_AGENT_OPENCODE_MODEL", "opencode/test-model")
    monkeypatch.setenv("CHAT_AGENT_OPENCODE_SANDBOX", "0")
    monkeypatch.setenv("CHAT_AGENT_TOKEN", token)
    launched = {}

    class Process:
        returncode = 0

        async def communicate(self):
            return (
                b'{"type":"tool_use","part":{"tool":"write","state":{"title":"write"}}}\n'
                b'{"type":"text","part":{"text":"Arquivo criado com sucesso."}}\n',
                b"",
            )

        async def wait(self):
            return 0

        def kill(self):
            pass

    async def fake_spawn(*argv, **kwargs):
        launched["argv"] = argv
        launched["cwd"] = kwargs.get("cwd")
        launched["env"] = kwargs.get("env")
        return Process()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_spawn)
    headers = {"Authorization": f"Bearer {token}"}

    def send(*, confirmed: bool):
        return client.post(
            "/command",
            json={
                "command_id": "aa33a807-46dc-4d58-9d0b-20c91e422f00",
                "action": "opencode",
                "params": {"prompt": "Crie um arquivo de teste"},
                "requires_confirmation": confirmed,
            },
            headers=headers,
        )

    with TestClient(server.app) as client:
        pending = send(confirmed=False)
        assert pending.json()["status"] == "needs_confirmation"
        assert not launched
        done = send(confirmed=True)
        assert done.json()["status"] == "ok"
        assert "Arquivo criado com sucesso." in done.json()["message"]
        assert "write" in done.json()["message"]
        assert launched["cwd"] == workspace
        assert launched["env"]["PWD"] == str(workspace)
        assert launched["argv"][:2] == (str(binary), "run")
        assert "--standalone" in launched["argv"]
        assert "opencode/test-model" in launched["argv"]
        assert not any(key.startswith("CHAT_AGENT_") for key in launched["env"])
        assert "Crie um arquivo de teste" not in launched["env"].get("CHAT_AGENT_TOKEN", "")

    journal = (tmp_path / "journal.jsonl").read_text()
    assert "Crie um arquivo de teste" not in journal
    assert "prompt_chars" in journal
