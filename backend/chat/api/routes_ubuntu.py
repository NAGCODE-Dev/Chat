"""Rotas do computador Ubuntu: status do agente e tarefas via OpenCode."""

from __future__ import annotations

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from chat.api.state import state
from chat.tools.agent import UbuntuClient

router = APIRouter(prefix="/api/ubuntu", tags=["ubuntu"])


class UbuntuTaskRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=8000)
    confirmed: bool = False


def _client() -> UbuntuClient:
    if state.settings is None:
        raise HTTPException(status_code=503, detail="Configuração não inicializada.")
    settings = state.settings
    if not settings.agent_url or not settings.agent_token:
        raise HTTPException(
            status_code=503,
            detail="Agente Ubuntu não configurado (CHAT_AGENT_URL e CHAT_AGENT_TOKEN).",
        )
    return UbuntuClient(
        settings.agent_url,
        settings.agent_token,
        settings.agent_tls_ca,
        settings.agent_tls_client_cert,
        settings.agent_tls_client_key,
    )


def _configured() -> bool:
    return bool(
        state.settings
        and state.settings.agent_url
        and state.settings.agent_token
    )


@router.get("/status")
async def ubuntu_status() -> dict:
    if not _configured():
        return {
            "configured": False,
            "reachable": False,
            "detail": "Configure CHAT_AGENT_URL e CHAT_AGENT_TOKEN no backend.",
        }
    try:
        agent = await _client().status()
    except (httpx.HTTPError, ValueError) as error:
        return {
            "configured": True,
            "reachable": False,
            "detail": f"Agente indisponível: {error}",
        }
    return {"configured": True, "reachable": True, **agent}


@router.get("/tasks")
async def list_tasks(limit: int = 20) -> dict:
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco não inicializado.")
    limit = max(1, min(limit, 100))
    rows = await state.db.fetch_all(
        "SELECT id, prompt, status, output, created_at, finished_at "
        "FROM ubuntu_tasks ORDER BY id DESC LIMIT ?",
        (limit,),
    )
    return {"tasks": rows}


@router.post("/tasks", status_code=201)
async def create_task(req: UbuntuTaskRequest) -> dict:
    if not req.confirmed:
        raise HTTPException(
            status_code=422,
            detail="A tarefa no computador exige confirmação explícita.",
        )
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco não inicializado.")
    prompt = req.prompt.strip()
    if not prompt:
        raise HTTPException(status_code=422, detail="Descreva a tarefa.")
    task_id = await state.db.execute(
        "INSERT INTO ubuntu_tasks(prompt, status) VALUES (?, 'running')",
        (prompt,),
    )
    try:
        result = await _client().run_opencode(prompt)
    except (httpx.HTTPError, ValueError) as error:
        output = f"Falha ao executar no computador: {error}"
        await state.db.execute(
            "UPDATE ubuntu_tasks SET status='failed', output=?, "
            "finished_at=datetime('now') WHERE id=?",
            (output[:12000], task_id),
        )
        raise HTTPException(status_code=502, detail=output) from error
    status = result.get("status")
    output = str(result.get("message", "")).strip() or "Tarefa concluída sem saída."
    final_status = "ok" if status == "ok" else "failed"
    await state.db.execute(
        "UPDATE ubuntu_tasks SET status=?, output=?, finished_at=datetime('now') WHERE id=?",
        (final_status, output[:12000], task_id),
    )
    row = await state.db.fetch_one("SELECT * FROM ubuntu_tasks WHERE id=?", (task_id,))
    return {"task": row}
