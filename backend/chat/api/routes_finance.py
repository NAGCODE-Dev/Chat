"""API do app Meu Dinheiro.

A interface web (PWA) e o assistente usam os mesmos dados. O token do backend
continua obrigatório; apenas os arquivos estáticos do PWA são públicos.
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query

from chat.api.state import state
from chat.finance.store import (
    FinanceStateUpdate,
    FinanceStore,
    TransactionCreate,
    format_summary,
)

router = APIRouter(prefix="/api/finance", tags=["finance"])


def _store() -> FinanceStore:
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco não inicializado.")
    return FinanceStore(state.db)


@router.get("/state")
async def get_state() -> dict:
    return await _store().get_state()


@router.put("/state")
async def put_state(payload: FinanceStateUpdate) -> dict:
    return await _store().update_state(payload)


@router.post("/transactions", status_code=201)
async def add_transaction(payload: TransactionCreate) -> dict:
    return await _store().add_transaction(payload)


@router.delete("/transactions/{transaction_id}")
async def delete_transaction(transaction_id: str) -> dict:
    deleted = await _store().delete_transaction(transaction_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Lançamento não encontrado.")
    return {"deleted": True}


@router.get("/summary")
async def get_summary(
    month: str | None = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    all_time: bool = False,
) -> dict:
    try:
        summary = await _store().summary(month=month, all_time=all_time)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {**summary, "text": format_summary(summary)}


@router.post("/reset")
async def reset() -> dict:
    return await _store().reset()
