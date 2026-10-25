"""Dispositivos permitidos e Wake-on-LAN com confirmação explícita."""

from __future__ import annotations

import asyncio
import ipaddress

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, StrictBool, field_validator

from chat.api.state import state
from chat.devices.wol import normalize_mac, send_magic_packet

router = APIRouter(prefix="/api/devices", tags=["devices"])


class DeviceInput(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    mac: str
    tailscale_ip: str | None = None

    @field_validator("name")
    @classmethod
    def valid_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("O nome não pode ficar vazio.")
        return value.strip()

    @field_validator("mac")
    @classmethod
    def valid_mac(cls, value: str) -> str:
        return normalize_mac(value)

    @field_validator("tailscale_ip")
    @classmethod
    def valid_ip(cls, value: str | None) -> str | None:
        if value is not None:
            address = ipaddress.ip_address(value)
            tailscale_range = ipaddress.ip_network("100.64.0.0/10")
            if address.version != 4 or address not in tailscale_range:
                raise ValueError("Informe um IPv4 do intervalo Tailscale 100.64.0.0/10.")
        return value


class WakeRequest(BaseModel):
    confirmed: StrictBool


def _db():
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco de dados não inicializado.")
    return state.db


@router.get("")
async def list_devices() -> dict:
    return {"devices": await _db().fetch_all(
        "SELECT id,name,mac,tailscale_ip,last_known_state,last_seen,wol_supported_states "
        "FROM devices ORDER BY name"
    )}


@router.post("", status_code=201)
async def add_device(device: DeviceInput) -> dict:
    try:
        device_id = await _db().execute(
            "INSERT INTO devices(name,mac,tailscale_ip) VALUES(?,?,?)",
            (device.name.strip(), device.mac, device.tailscale_ip),
        )
    except Exception as error:
        if "UNIQUE" in str(error):
            raise HTTPException(status_code=409, detail="Já existe um dispositivo com esse nome.") from error
        raise
    return {"id": device_id, **device.model_dump()}


@router.delete("/{device_id}")
async def remove_device(device_id: int) -> dict:
    await _db().execute("DELETE FROM devices WHERE id=?", (device_id,))
    changed = await _db().fetch_one("SELECT changes() AS count")
    if not changed or not changed["count"]:
        raise HTTPException(status_code=404, detail="Dispositivo não encontrado.")
    return {"deleted": device_id}


@router.post("/{device_id}/wake")
async def wake_device(device_id: int, request: WakeRequest) -> dict:
    if request.confirmed is not True:
        raise HTTPException(status_code=403, detail="Confirmação explícita necessária.")
    row = await _db().fetch_one("SELECT name,mac FROM devices WHERE id=?", (device_id,))
    if row is None:
        raise HTTPException(status_code=404, detail="Dispositivo não encontrado.")
    try:
        await asyncio.to_thread(send_magic_packet, row["mac"])
    except OSError as error:
        raise HTTPException(status_code=502, detail=f"Não foi possível enviar o pacote: {error}") from error
    await _db().execute(
        "INSERT INTO audit_log(actor,action,args_json,result,confirmed_by_user) "
        "VALUES('user','device_wake',?,?,1)",
        (f'{{"device_id":{device_id}}}', "pacote Wake-on-LAN enviado"),
    )
    return {"device_id": device_id, "sent": True,
            "message": f"Pacote de ativação enviado para {row['name']}; isso não confirma que o aparelho iniciou."}
