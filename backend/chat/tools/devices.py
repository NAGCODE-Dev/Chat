"""Consulta de dispositivos cadastrados e ativação WOL com confirmação."""

from __future__ import annotations

import asyncio
import json

from pydantic import Field

from chat.devices.wol import send_magic_packet
from chat.memory.db import Database
from chat.tools.base import Permission, Tool, ToolArguments, ToolResult


class DeviceListArgs(ToolArguments):
    pass


class DeviceList(Tool):
    name = "device_list"
    description = "Lista dispositivos cadastrados e seus estados conhecidos."
    permission = Permission.SAFE
    arguments_model = DeviceListArgs

    def __init__(self, db: Database):
        self.db = db

    async def run(self, arguments: dict) -> ToolResult:
        rows = await self.db.fetch_all(
            "SELECT id,name,mac,tailscale_ip,last_known_state,last_seen FROM devices ORDER BY name"
        )
        return ToolResult("Nenhum dispositivo cadastrado." if not rows else str(rows))


class DeviceWakeArgs(ToolArguments):
    device_name: str = Field(min_length=1, max_length=100)


class DeviceWake(Tool):
    name = "device_wake"
    description = "Envia um pacote Wake-on-LAN para um dispositivo cadastrado."
    permission = Permission.CONFIRM
    arguments_model = DeviceWakeArgs

    def __init__(self, db: Database):
        self.db = db

    async def run(self, arguments: dict) -> ToolResult:
        device = await self.db.fetch_one(
            "SELECT id,name,mac FROM devices WHERE name=? COLLATE NOCASE",
            (arguments["device_name"],),
        )
        if device is None:
            return ToolResult("Dispositivo não cadastrado.", False)
        try:
            await asyncio.to_thread(send_magic_packet, device["mac"])
        except OSError as error:
            result = f"Falha ao enviar pacote Wake-on-LAN: {error}"
            success = False
        else:
            result = (
                f"Pacote Wake-on-LAN enviado para {device['name']}. "
                "O envio não confirma que o aparelho iniciou."
            )
            success = True
        await self.db.execute(
            "INSERT INTO audit_log(actor,action,args_json,result,confirmed_by_user) "
            "VALUES('assistant','device_wake',?,?,1)",
            (json.dumps({"device_id": device["id"]}), result),
        )
        return ToolResult(result, success)
