"""Daemon HTTP local com token obrigatório, allowlist fechada e journal JSONL."""

from __future__ import annotations

import asyncio
import hmac
import json
import os
import shutil
import sqlite3
import tempfile
import threading
import time
from collections import defaultdict, deque
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

_MAX_REQUEST_BODY_BYTES = 128 * 1024
_MAX_WRITE_CONTENT_BYTES = 32 * 1024
_MAX_FILE_BYTES = 64 * 1024
_MAX_PARAM_CHARS = _MAX_WRITE_CONTENT_BYTES + 2048


class Command(BaseModel):
    model_config = ConfigDict(extra="forbid")
    command_id: UUID
    action: Literal[
        "status",
        "open_app",
        "list_files",
        "read_file",
        "write_file",
        "append_file",
        "create_dir",
    ]
    params: dict[
        Annotated[str, Field(max_length=32)],
        Annotated[str, Field(max_length=_MAX_PARAM_CHARS)],
    ] = Field(default_factory=dict, max_length=3)
    requires_confirmation: bool = False


app = FastAPI(title="Chat Ubuntu Agent", version="0.1.0")
_token = os.environ.get("CHAT_AGENT_TOKEN", "")
_journal = Path(os.environ.get("CHAT_AGENT_JOURNAL", Path.home() / ".local/share/chat-agent/journal.jsonl"))
_journal_lock = threading.Lock()
_request_limit = 60
_request_window_seconds = 60.0
_request_max_clients = 4096
_request_times: dict[str, deque[float]] = defaultdict(deque)
_rate_limit_lock = threading.Lock()
_MAX_READ_BYTES = 64 * 1024
_MAX_DIRECTORY_ENTRIES = 200
_CONTROL_ACTIONS = {
    "open_app",
    "list_files",
    "read_file",
    "write_file",
    "append_file",
    "create_dir",
}


class RequestBodyTooLarge(Exception):
    pass


class RequestBodyLimitMiddleware:
    def __init__(self, app, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        headers = dict(scope.get("headers", []))
        content_length = headers.get(b"content-length")
        if content_length:
            try:
                declared_size = int(content_length)
            except ValueError:
                await self._send_rejection(send, 400, "Content-Length inválido.")
                return
            if declared_size > self.max_bytes:
                await self._send_rejection(send, 413, "Corpo excede o limite de 128 KiB.")
                return

        received_bytes = 0
        too_large = False
        response_started = False

        async def limited_receive():
            nonlocal received_bytes, too_large
            message = await receive()
            if message["type"] == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > self.max_bytes:
                    too_large = True
                    raise RequestBodyTooLarge
            return message

        async def limited_send(message):
            nonlocal response_started
            if too_large:
                if message["type"] == "http.response.start" and not response_started:
                    response_started = True
                    await self._send_rejection(
                        send, 413, "Corpo excede o limite de 128 KiB."
                    )
                return
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, limited_send)
        except RequestBodyTooLarge:
            if not response_started:
                await self._send_rejection(send, 413, "Corpo excede o limite de 128 KiB.")

    @staticmethod
    async def _send_rejection(send, status: int, detail: str) -> None:
        body = json.dumps({"detail": detail}).encode()
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})


app.add_middleware(RequestBodyLimitMiddleware, max_bytes=_MAX_REQUEST_BODY_BYTES)


def _journal_command_ids():
    try:
        journal = _journal.open(encoding="utf-8")
    except FileNotFoundError:
        return
    with journal:
        for line in journal:
            try:
                event = json.loads(line)
            except (json.JSONDecodeError, AttributeError):
                continue
            if event.get("status") in {"received", "ok", "failed", "replay_rejected"}:
                command_id = event.get("command_id")
                if command_id:
                    yield command_id


def _command_index() -> sqlite3.Connection:
    _journal.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    index_path = _journal.with_name(f"{_journal.name}.commands.sqlite3")
    connection = sqlite3.connect(index_path, timeout=5)
    os.chmod(index_path, 0o600)
    connection.execute(
        "CREATE TABLE IF NOT EXISTS processed_commands (command_id TEXT PRIMARY KEY)"
    )
    version = connection.execute("PRAGMA user_version").fetchone()[0]
    if version < 1:
        connection.executemany(
            "INSERT OR IGNORE INTO processed_commands(command_id) VALUES (?)",
            ((command_id,) for command_id in _journal_command_ids()),
        )
        connection.execute("PRAGMA user_version=1")
        connection.commit()
    return connection

# Valores são argumentos fixos; o cliente nunca escolhe um executável ou argumento arbitrário.
_applications: dict[str, tuple[str, ...]] = {
    "browser": ("firefox", "--new-window", "about:blank"),
    "files": ("xdg-open", str(Path.home())),
    "terminal": ("x-terminal-emulator",),
    "editor": ("code", "--new-window"),
}


def _file_roots(environment_name: str) -> list[Path]:
    """Raízes explícitas configuradas para leitura ou escrita."""
    raw = os.environ.get(environment_name, "")
    roots: list[Path] = []
    for item in raw.split(os.pathsep):
        if not item.strip():
            continue
        try:
            root = Path(item).expanduser().resolve(strict=True)
        except (OSError, RuntimeError):
            continue
        if root.is_dir() and root not in roots:
            roots.append(root)
    return roots


def _allowed_file_roots() -> list[Path]:
    """Raízes liberadas para leitura, definidas por CHAT_AGENT_ALLOWED_DIRS."""
    return _file_roots("CHAT_AGENT_ALLOWED_DIRS")


def _allowed_write_roots() -> list[Path]:
    """Raízes liberadas para escrita, definidas por CHAT_AGENT_WRITE_DIRS."""
    return _file_roots("CHAT_AGENT_WRITE_DIRS")


def _authorized_path(raw_path: str) -> tuple[Path | None, str, str]:
    """Resolve o caminho e confirma que ele está dentro de uma raiz de leitura."""
    roots = _allowed_file_roots()
    if not roots:
        return None, "failed", "Acesso a arquivos não configurado (CHAT_AGENT_ALLOWED_DIRS)."
    if not raw_path or not Path(raw_path).is_absolute():
        return None, "failed", "Informe um caminho absoluto."
    try:
        resolved = Path(raw_path).expanduser().resolve(strict=True)
    except (OSError, RuntimeError):
        return None, "failed", "Caminho não encontrado."
    if not any(resolved == root or resolved.is_relative_to(root) for root in roots):
        return None, "denied", "Caminho fora das pastas autorizadas."
    return resolved, "ok", ""


def _authorized_write_target(raw_path: str) -> tuple[Path | None, str, str]:
    """Resolve um destino de escrita, exigindo raiz própria e pasta pai existente.

    A resolução segue links simbólicos antes da checagem, então um link que
    aponte para fora da raiz é recusado. O próprio destino não pode ser um link
    simbólico, o que evita sobrescrever outro local por engano.
    """
    roots = _allowed_write_roots()
    if not roots:
        return None, "failed", "Escrita não configurada (CHAT_AGENT_WRITE_DIRS)."
    if not raw_path or not Path(raw_path).is_absolute():
        return None, "failed", "Informe um caminho absoluto."
    original = Path(raw_path).expanduser()
    try:
        if original.is_symlink():
            return None, "denied", "Link simbólico não é aceito para escrita."
        resolved = original.resolve(strict=False)
    except (OSError, RuntimeError):
        return None, "failed", "Caminho inválido."
    if not any(resolved == root or resolved.is_relative_to(root) for root in roots):
        return None, "denied", "Caminho fora das pastas de escrita autorizadas."
    parent = resolved.parent
    if not parent.is_dir():
        return None, "failed", "A pasta de destino não existe."
    if not any(parent == root or parent.is_relative_to(root) for root in roots):
        return None, "denied", "A pasta de destino está fora das pastas autorizadas."
    return resolved, "ok", ""


def _list_directory(path: Path) -> tuple[str | None, str | None]:
    if not path.is_dir():
        return None, "O caminho não é uma pasta."
    try:
        entries = sorted(path.iterdir(), key=lambda item: (not item.is_dir(), item.name.casefold()))
    except OSError as error:
        return None, f"Não foi possível listar a pasta: {error}"
    lines: list[str] = []
    for entry in entries[:_MAX_DIRECTORY_ENTRIES]:
        try:
            is_directory = entry.is_dir()
        except OSError:
            is_directory = False
        if is_directory:
            lines.append(f"[pasta] {entry.name}")
            continue
        try:
            size = entry.stat().st_size
        except OSError:
            size = 0
        lines.append(f"[arquivo] {entry.name} ({size} bytes)")
    if len(entries) > _MAX_DIRECTORY_ENTRIES:
        lines.append(f"... {len(entries) - _MAX_DIRECTORY_ENTRIES} entradas omitidas")
    return ("\n".join(lines) if lines else "(pasta vazia)"), None


def _read_text_file(path: Path) -> tuple[str | None, str | None]:
    if not path.is_file():
        return None, "O caminho não é um arquivo."
    try:
        if path.stat().st_size > _MAX_READ_BYTES:
            return None, "Arquivo excede o limite de 64 KiB."
        data = path.read_bytes()
    except OSError as error:
        return None, f"Não foi possível ler o arquivo: {error}"
    if b"\x00" in data:
        return None, "Arquivo binário não pode ser lido como texto."
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError:
        return None, "Arquivo não está codificado em UTF-8."


def _fsync_directory(path: Path) -> None:
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    except OSError:
        return
    try:
        os.fsync(descriptor)
    except OSError:
        pass
    finally:
        os.close(descriptor)


def _write_text_file(
    path: Path, content: str, *, append: bool
) -> tuple[str | None, str | None]:
    """Grava texto de forma atômica, com limite por operação e por arquivo.

    A gravação usa um arquivo temporário no mesmo diretório e `os.replace`,
    então uma interrupção não deixa o destino pela metade. O conteúdo nunca é
    devolvido nem registrado no journal.
    """
    data = content.encode("utf-8")
    if len(data) > _MAX_WRITE_CONTENT_BYTES:
        return None, "Conteúdo excede o limite de 32 KiB por operação."
    if b"\x00" in data:
        return None, "Conteúdo binário não é aceito para escrita de texto."
    if path.exists() and not path.is_file():
        return None, "O caminho existe e não é um arquivo."
    existing = b""
    mode = 0o600
    if path.exists():
        try:
            mode = path.stat().st_mode & 0o777
            if append:
                if path.stat().st_size > _MAX_FILE_BYTES:
                    return None, "Arquivo já excede o limite de 64 KiB."
                existing = path.read_bytes()
        except OSError as error:
            return None, f"Não foi possível preparar a escrita: {error}"
    total = len(existing) + len(data)
    if total > _MAX_FILE_BYTES:
        return None, "O arquivo resultante excede o limite de 64 KiB."
    temporary_name: str | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
        )
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(existing)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
        temporary_name = None
        _fsync_directory(path.parent)
    except OSError as error:
        return None, f"Não foi possível gravar o arquivo: {error}"
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except OSError:
                pass
    action = "acrescentado" if append else "gravado"
    return (
        f"Arquivo {action} ({len(data)} bytes; total {total} bytes).",
        None,
    )


def _create_directory(path: Path) -> tuple[str | None, str | None]:
    if path.exists():
        if path.is_dir():
            return "A pasta já existe.", None
        return None, "O caminho existe e não é uma pasta."
    try:
        path.mkdir(mode=0o700)
    except OSError as error:
        return None, f"Não foi possível criar a pasta: {error}"
    return "Pasta criada.", None


async def authenticate(
    request: Request,
    authorization: str | None = Header(default=None),
) -> None:
    client_key = request.client.host if request.client else "unknown"
    now = time.monotonic()
    with _rate_limit_lock:
        cutoff = now - _request_window_seconds
        if client_key not in _request_times and len(_request_times) >= _request_max_clients:
            expired = [
                key
                for key, timestamps in _request_times.items()
                if not timestamps or timestamps[-1] <= cutoff
            ]
            for key in expired:
                del _request_times[key]
            if len(_request_times) >= _request_max_clients:
                earliest = min(timestamps[0] for timestamps in _request_times.values())
                retry_after = max(1, int(earliest + _request_window_seconds - now + 0.999))
                raise HTTPException(
                    status_code=429,
                    detail="Limite de origens concorrentes excedido.",
                    headers={"Retry-After": str(retry_after)},
                )
        events = _request_times[client_key]
        while events and events[0] <= cutoff:
            events.popleft()
        if len(events) >= _request_limit:
            retry_after = max(1, int(events[0] + _request_window_seconds - now + 0.999))
            raise HTTPException(
                status_code=429,
                detail="Limite de requisições excedido.",
                headers={"Retry-After": str(retry_after)},
            )
        events.append(now)
    if len(_token) < 32:
        raise HTTPException(status_code=503, detail="CHAT_AGENT_TOKEN não configurado (mínimo 32 caracteres).")
    supplied = authorization.removeprefix("Bearer ") if authorization else ""
    if not hmac.compare_digest(supplied, _token):
        raise HTTPException(status_code=401, detail="Token inválido.")


def _audit_params(command: Command) -> dict[str, str]:
    """Remove o conteúdo dos parâmetros antes de gravar no journal."""
    if command.action in {"write_file", "append_file"}:
        content = command.params.get("content", "")
        return {
            "path": command.params.get("path", ""),
            "content_bytes": str(len(content.encode("utf-8"))),
        }
    return command.params


def _record(command: Command, status: str, message: str) -> None:
    entry = {
        "at": datetime.now(UTC).isoformat(), "command_id": str(command.command_id),
        "action": command.action, "params": _audit_params(command),
        "status": status, "message": message,
    }
    with _journal_lock:
        _journal.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        descriptor = os.open(_journal, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(descriptor, "a", encoding="utf-8") as stream:
            stream.write(json.dumps(entry, ensure_ascii=False) + "\n")
        os.chmod(_journal, 0o600)


def _claim_command(command: Command) -> bool:
    command_id = str(command.command_id)
    with _journal_lock:
        connection = _command_index()
        try:
            with connection:
                cursor = connection.execute(
                    "INSERT OR IGNORE INTO processed_commands(command_id) VALUES (?)",
                    (command_id,),
                )
                claimed = cursor.rowcount == 1
        finally:
            connection.close()
    if not claimed:
        return False
    _record(command, "received", "Comando aceito para processamento.")
    return True


@app.get("/status", dependencies=[Depends(authenticate)])
async def status() -> dict:
    return {"status": "ok", "version": app.version, "host": "ubuntu"}


@app.post("/command", dependencies=[Depends(authenticate)])
async def command(request: Command) -> dict:
    if request.action in _CONTROL_ACTIONS and not request.requires_confirmation:
        result = {"status": "needs_confirmation", "message": "Ação requer confirmação explícita."}
        _record(request, result["status"], result["message"])
        return {"command_id": str(request.command_id), **result}

    if not _claim_command(request):
        _record(request, "replay_rejected", "command_id já processado; replay bloqueado.")
        raise HTTPException(status_code=409, detail="command_id já foi processado.")
    if request.action == "status":
        if request.params:
            raise HTTPException(status_code=422, detail="Status não aceita parâmetros.")
        result = {"status": "ok", "message": f"Agente ativo ({app.version})."}
        _record(request, result["status"], result["message"])
        return {"command_id": str(request.command_id), **result}

    if request.action in {"list_files", "read_file"}:
        if set(request.params) != {"path"}:
            raise HTTPException(status_code=422, detail="Informe somente o caminho.")
        path, status, message = _authorized_path(request.params.get("path", ""))
        if path is None:
            result = {"status": status, "message": message}
        else:
            handler = _list_directory if request.action == "list_files" else _read_text_file
            message, error = await asyncio.to_thread(handler, path)
            result = (
                {"status": "failed", "message": error}
                if error is not None
                else {"status": "ok", "message": message}
            )
        audit_message = result["message"]
        if result["status"] == "ok":
            audit_message = (
                f"Pasta listada ({len(result['message'].splitlines())} entradas)."
                if request.action == "list_files"
                else f"Arquivo lido ({len(result['message'])} caracteres)."
            )
        _record(request, result["status"], audit_message)
        return {"command_id": str(request.command_id), **result}

    if request.action in {"write_file", "append_file", "create_dir"}:
        expected = {"path"} if request.action == "create_dir" else {"path", "content"}
        if set(request.params) != expected:
            detail = (
                "Informe somente o caminho."
                if request.action == "create_dir"
                else "Informe somente o caminho e o conteúdo."
            )
            raise HTTPException(status_code=422, detail=detail)
        path, status, message = _authorized_write_target(request.params.get("path", ""))
        if path is None:
            result = {"status": status, "message": message}
        elif request.action == "create_dir":
            message, error = await asyncio.to_thread(_create_directory, path)
            result = (
                {"status": "failed", "message": error}
                if error is not None
                else {"status": "ok", "message": message}
            )
        else:
            message, error = await asyncio.to_thread(
                _write_text_file,
                path,
                request.params.get("content", ""),
                append=request.action == "append_file",
            )
            result = (
                {"status": "failed", "message": error}
                if error is not None
                else {"status": "ok", "message": message}
            )
        _record(request, result["status"], result["message"])
        return {"command_id": str(request.command_id), **result}

    if set(request.params) != {"app"}:
        raise HTTPException(status_code=422, detail="Informe somente o identificador do aplicativo.")
    app_id = request.params.get("app", "")
    argv = _applications.get(app_id)
    if not argv:
        raise HTTPException(status_code=422, detail="Aplicativo fora da allowlist.")
    executable = shutil.which(argv[0])
    if not executable:
        result = {"status": "failed", "message": f"Aplicativo '{app_id}' não está instalado."}
        _record(request, result["status"], result["message"])
        return {"command_id": str(request.command_id), **result}

    try:
        # GUI apps inherit the daemon environment by default. Do not leak its
        # bearer token, mTLS material, or journal configuration to them.
        child_env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("CHAT_AGENT_")
        }
        process = await asyncio.create_subprocess_exec(
            executable, *argv[1:], env=child_env
        )
    except OSError as error:
        result = {"status": "failed", "message": f"Não foi possível iniciar '{app_id}': {error}"}
    else:
        try:
            exit_code = await asyncio.wait_for(process.wait(), timeout=1.5)
        except TimeoutError:
            result = {
                "status": "ok",
                "message": f"Aplicativo '{app_id}' iniciou e continua ativo (pid {process.pid}).",
            }
        else:
            result = (
                {"status": "ok", "message": f"Aplicativo '{app_id}' aberto (pid {process.pid})."}
                if exit_code == 0
                else {"status": "failed", "message": f"Launcher de '{app_id}' encerrou com código {exit_code}."}
            )
    _record(request, result["status"], result["message"])
    return {"command_id": str(request.command_id), **result}
