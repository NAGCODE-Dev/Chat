"""Aquecimento dos modelos configurados, disparado pela abertura do app."""

from __future__ import annotations

import asyncio
from typing import Any

from fastapi import APIRouter, HTTPException

from chat.api.state import state
from chat.core.logging import get_logger

router = APIRouter(prefix="/api/models", tags=["models"])
log = get_logger("chat.routes_models")

_task: asyncio.Task[None] | None = None
_status: dict[str, Any] = {
    "status": "idle",
    "models": [],
    "warmed": [],
    "failed": {},
}


async def _run_warmup(models: list[str]) -> None:
    global _status
    service = state.chat_service
    if service is None:
        return
    _status = {"status": "warming", "models": models, "warmed": [], "failed": {}}
    for model in models:
        try:
            await service.warmup_model(model)
        except Exception as error:  # noqa: BLE001 - aquecimento é melhor esforço
            log.warning("falha ao aquecer %s: %s", model, error)
            _status["failed"][model] = str(error)[:300]
        else:
            _status["warmed"].append(model)
            log.info("modelo aquecido: %s", model)
    _status["status"] = "ready" if not _status["failed"] else "partial"


@router.post("/warmup")
async def warmup_models() -> dict:
    global _task, _status
    service = state.chat_service
    if service is None:
        raise HTTPException(status_code=503, detail="Serviço não inicializado.")
    if _task is not None and not _task.done():
        return {
            "status": "warming",
            "models": _status.get("models", []),
            "warmed": _status.get("warmed", []),
        }
    models = await service.warmup_candidates()
    if not models:
        _status = {"status": "ready", "models": [], "warmed": [], "failed": {}}
        return {"status": "ready", "models": [], "warmed": []}
    _status = {"status": "warming", "models": models, "warmed": [], "failed": {}}
    _task = asyncio.create_task(_run_warmup(models), name="chat-warmup")
    return {"status": "started", "models": models, "warmed": []}


@router.get("/warmup")
async def warmup_status() -> dict:
    return dict(_status)
