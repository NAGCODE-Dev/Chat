"""Ações executadas no celular Android conectado.

O backend não tem acesso ao aparelho. A ferramenta devolve um marcador que o
serviço de conversa transforma em um evento ``device_action``; o aplicativo
Android executa a ação e mostra o resultado. Assim o modelo continua sem
poder executar comandos arbitrários: só existe uma lista fechada de ações.
"""

from __future__ import annotations

import json
from typing import Literal
from urllib.parse import urlparse

from pydantic import Field, field_validator

from chat.tools.base import Permission, Tool, ToolArguments, ToolResult

DEVICE_ACTION_PREFIX = "__DEVICE_ACTION__"


class PhoneActionArgs(ToolArguments):
    action: Literal["open_app", "play_music", "media_control", "open_url"]
    target: str = Field(default="", max_length=300)

    @field_validator("target")
    @classmethod
    def validate_target(cls, value: str, info) -> str:
        action = info.data.get("action")
        if action == "open_url":
            parsed = urlparse(value)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or parsed.username
                or parsed.password
            ):
                raise ValueError("open_url exige uma URL HTTP/HTTPS sem credenciais")
        if action in {"open_app", "play_music"} and not value.strip():
            raise ValueError(f"{action} exige um nome de aplicativo ou música")
        return value


class PhoneAction(Tool):
    name = "phone_action"
    description = (
        "Executa uma ação no celular Android conectado. Ações válidas: "
        "open_app (target = nome do aplicativo, ex.: WhatsApp), play_music "
        "(target = nome da música ou artista), media_control (target = play, "
        "pause, next ou previous) e open_url (target = URL HTTP/HTTPS). Use "
        "somente quando a pessoa pedir uma ação no celular."
    )
    permission = Permission.SAFE
    arguments_model = PhoneActionArgs

    async def run(self, arguments: dict) -> ToolResult:
        payload = {
            "action": arguments["action"],
            "target": arguments.get("target", ""),
        }
        return ToolResult(DEVICE_ACTION_PREFIX + json.dumps(payload, ensure_ascii=False))


def parse_device_action(result: str) -> dict[str, str] | None:
    """Devolve a ação estruturada quando o resultado é um marcador de dispositivo."""
    if not result.startswith(DEVICE_ACTION_PREFIX):
        return None
    try:
        payload = json.loads(result[len(DEVICE_ACTION_PREFIX):])
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    action = payload.get("action")
    target = payload.get("target", "")
    if action not in {"open_app", "play_music", "media_control", "open_url"}:
        return None
    return {"action": str(action), "target": str(target)}


def describe_device_action(action: dict[str, str]) -> str:
    labels = {
        "open_app": "abrir o aplicativo",
        "play_music": "tocar música",
        "media_control": "controlar a mídia",
        "open_url": "abrir o link",
    }
    label = labels.get(action["action"], action["action"])
    target = action.get("target", "")
    return f"Comando enviado ao celular para {label}{': ' + target if target else ''}."
