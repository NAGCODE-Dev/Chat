"""Cliente autenticado do daemon local, com ações explicitamente limitadas."""

from __future__ import annotations

import ssl
import uuid
from pathlib import Path
from typing import Literal

import httpx
from pydantic import ConfigDict, Field, field_validator, model_validator

from chat.tools.base import Permission, Tool, ToolArguments, ToolResult


class DeviceStatusArgs(ToolArguments):
    pass


class DeviceStatus(Tool):
    name = "device_status"
    description = "Consulta se o daemon Ubuntu está conectado e disponível."
    permission = Permission.SAFE
    arguments_model = DeviceStatusArgs

    def __init__(self, base_url: str, token: str, ca: Path | None = None, cert: Path | None = None, key: Path | None = None):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.verify = _tls_context(ca, cert, key)

    async def run(self, arguments: dict) -> ToolResult:
        try:
            async with httpx.AsyncClient(timeout=5, verify=self.verify) as client:
                response = await client.get(
                    f"{self.base_url}/status",
                    headers={"Authorization": f"Bearer {self.token}"},
                )
                response.raise_for_status()
        except httpx.HTTPError as error:
            return ToolResult(f"Agente indisponível: {error}", False)
        return ToolResult(str(response.json()), True)


class AgentArgs(ToolArguments):
    # Conteúdo de arquivo não pode sofrer strip: espaços e quebras fazem parte
    # da anotação. Caminho e aplicativo são normalizados individualmente.
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=False)

    action: Literal[
        "status",
        "open_app",
        "list_files",
        "read_file",
        "write_file",
        "append_file",
        "create_dir",
        "opencode",
    ]
    app: Literal["browser", "files", "terminal", "editor"] | None = None
    path: str | None = Field(default=None, min_length=1, max_length=1024)
    content: str | None = Field(default=None, max_length=32 * 1024)
    prompt: str | None = Field(default=None, min_length=1, max_length=8000)

    @field_validator("app", "path")
    @classmethod
    def strip_identifiers(cls, value: str | None) -> str | None:
        return value.strip() if value is not None else None

    @model_validator(mode="after")
    def validate_action_fields(self) -> AgentArgs:
        if self.action == "open_app":
            if self.app is None:
                raise ValueError("Informe o aplicativo permitido.")
            if self.path is not None or self.content is not None or self.prompt is not None:
                raise ValueError("Abrir aplicativo não aceita caminho nem conteúdo.")
        elif self.action in {"list_files", "read_file"}:
            if self.path is None:
                raise ValueError("Informe o caminho absoluto.")
            if self.app is not None or self.content is not None or self.prompt is not None:
                raise ValueError("Leitura de arquivos não aceita aplicativo nem conteúdo.")
            if not self.path.startswith("/"):
                raise ValueError("O caminho precisa ser absoluto.")
        elif self.action in {"write_file", "append_file"}:
            if self.path is None or self.content is None:
                raise ValueError("Informe o caminho absoluto e o conteúdo.")
            if self.app is not None or self.prompt is not None:
                raise ValueError("Escrita de arquivos não aceita aplicativo.")
            if not self.path.startswith("/"):
                raise ValueError("O caminho precisa ser absoluto.")
        elif self.action == "create_dir":
            if self.path is None:
                raise ValueError("Informe o caminho absoluto da pasta.")
            if self.app is not None or self.content is not None or self.prompt is not None:
                raise ValueError("Criação de pasta não aceita aplicativo nem conteúdo.")
            if not self.path.startswith("/"):
                raise ValueError("O caminho precisa ser absoluto.")
        elif self.action == "opencode":
            if self.prompt is None:
                raise ValueError("Informe a tarefa para o OpenCode.")
            if self.app is not None or self.path is not None or self.content is not None:
                raise ValueError("Tarefa do OpenCode aceita somente o texto da tarefa.")
        elif self.app is not None or self.path is not None or self.content is not None or self.prompt is not None:
            raise ValueError("Consulta de estado não aceita parâmetros.")
        return self


class AgentExec(Tool):
    name = "agent_exec"
    description = (
        "Auxilia em tarefas do dia a dia no notebook: consulta o estado, abre um "
        "aplicativo permitido, lista ou lê arquivos, salva anotações e documentos "
        "em texto dentro das pastas autorizadas e, quando a pessoa pedir uma tarefa "
        "de programação ou automação, executa o OpenCode na pasta de trabalho."
    )
    permission = Permission.CONFIRM
    arguments_model = AgentArgs

    def __init__(self, base_url: str, token: str, ca: Path | None = None, cert: Path | None = None, key: Path | None = None):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.verify = _tls_context(ca, cert, key)

    async def run(self, arguments: dict) -> ToolResult:
        action = arguments["action"]
        params: dict[str, str] = {}
        if action == "open_app":
            params = {"app": arguments["app"]}
        elif action in {"list_files", "read_file", "create_dir"}:
            params = {"path": arguments["path"]}
        elif action in {"write_file", "append_file"}:
            params = {"path": arguments["path"], "content": arguments["content"]}
        elif action == "opencode":
            params = {"prompt": arguments["prompt"]}
        body = {
            "command_id": str(uuid.uuid4()),
            "action": action,
            "params": params,
            "requires_confirmation": True,
        }
        try:
            async with httpx.AsyncClient(timeout=8, verify=self.verify) as client:
                response = await client.post(
                    f"{self.base_url}/command", json=body,
                    headers={"Authorization": f"Bearer {self.token}"},
                )
                response.raise_for_status()
        except httpx.HTTPError as error:
            return ToolResult(f"Agente indisponível ou recusou a solicitação: {error}", False)
        data = response.json()
        return ToolResult(str(data.get("message", data)), data.get("status") == "ok")


class UbuntuClient:
    """Cliente direto para as rotas de status e tarefas do agente Ubuntu."""

    def __init__(
        self,
        base_url: str,
        token: str,
        ca: Path | None = None,
        cert: Path | None = None,
        key: Path | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.verify = _tls_context(ca, cert, key)

    async def status(self) -> dict:
        async with httpx.AsyncClient(timeout=8, verify=self.verify) as client:
            response = await client.get(
                f"{self.base_url}/status",
                headers={"Authorization": f"Bearer {self.token}"},
            )
            response.raise_for_status()
            return response.json()

    async def run_opencode(self, prompt: str) -> dict:
        body = {
            "command_id": str(uuid.uuid4()),
            "action": "opencode",
            "params": {"prompt": prompt},
            "requires_confirmation": True,
        }
        async with httpx.AsyncClient(timeout=300, verify=self.verify) as client:
            response = await client.post(
                f"{self.base_url}/command",
                json=body,
                headers={"Authorization": f"Bearer {self.token}"},
            )
            response.raise_for_status()
            return response.json()


def _tls_context(ca: Path | None, cert: Path | None, key: Path | None) -> ssl.SSLContext | bool:
    if not any((ca, cert, key)):
        return True
    if not all((ca, cert, key)):
        raise ValueError("mTLS do agente requer CA, certificado e chave de cliente.")
    context = ssl.create_default_context(cafile=str(ca))
    context.load_cert_chain(certfile=str(cert), keyfile=str(key))
    return context
