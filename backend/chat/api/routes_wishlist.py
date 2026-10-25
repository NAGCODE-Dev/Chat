"""CRUD da lista de desejos para o app; ações do modelo continuam com confirmação."""

from __future__ import annotations

import json
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, HttpUrl

from chat.api.state import state

router = APIRouter(prefix="/api/wishlist", tags=["wishlist"])
WishlistStatus = Literal["aberto", "comprado", "descartado"]


class WishlistInput(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=1000)
    priority: int = Field(default=0, ge=0, le=5)
    url: HttpUrl | None = None


class WishlistUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=1000)
    priority: int | None = Field(default=None, ge=0, le=5)
    status: WishlistStatus | None = None
    url: HttpUrl | None = None


def _db():
    if state.db is None:
        raise HTTPException(status_code=503, detail="Banco de dados não inicializado.")
    return state.db


@router.get("")
async def list_wishlist(status: WishlistStatus | None = None) -> dict:
    sql = "SELECT id,title,notes,priority,status,url,created_at,updated_at FROM wishlist"
    params: tuple = ()
    if status:
        sql += " WHERE status=?"
        params = (status,)
    sql += " ORDER BY priority DESC, updated_at DESC"
    return {"items": await _db().fetch_all(sql, params)}


@router.post("", status_code=201)
async def create_wishlist_item(item: WishlistInput) -> dict:
    item_id = await _db().execute(
        "INSERT INTO wishlist(title,notes,priority,url) VALUES(?,?,?,?)",
        (item.title.strip(), item.notes, item.priority, str(item.url) if item.url else None),
    )
    await _db().execute(
        "INSERT INTO audit_log(actor,action,args_json,result,confirmed_by_user) "
        "VALUES('user','wishlist_add',?,?,1)",
        (json.dumps(item.model_dump(mode="json"), ensure_ascii=False), f"item_id={item_id}"),
    )
    return {"id": item_id, **item.model_dump(mode="json"), "status": "aberto"}


@router.patch("/{item_id}")
async def update_wishlist_item(item_id: int, update: WishlistUpdate) -> dict:
    values = {
        key: value for key, value in update.model_dump(exclude_unset=True, mode="json").items()
        if value is not None
    }
    if not values:
        raise HTTPException(status_code=422, detail="Informe ao menos um campo para alterar.")
    current = await _db().fetch_one("SELECT id FROM wishlist WHERE id=?", (item_id,))
    if current is None:
        raise HTTPException(status_code=404, detail="Item não encontrado.")
    assignments = ",".join(f"{key}=?" for key in values)
    params = [str(value) if key == "url" and value is not None else value
              for key, value in values.items()]
    await _db().execute(
        f"UPDATE wishlist SET {assignments},updated_at=datetime('now') WHERE id=?",
        (*params, item_id),
    )
    await _db().execute(
        "INSERT INTO audit_log(actor,action,args_json,result,confirmed_by_user) "
        "VALUES('user','wishlist_update',?,?,1)",
        (json.dumps(values, ensure_ascii=False), f"item_id={item_id}"),
    )
    return {"updated": item_id}


@router.delete("/{item_id}")
async def delete_wishlist_item(item_id: int) -> dict:
    await _db().execute("DELETE FROM wishlist WHERE id=?", (item_id,))
    changed = await _db().fetch_one("SELECT changes() AS count")
    if not changed or not changed["count"]:
        raise HTTPException(status_code=404, detail="Item não encontrado.")
    return {"deleted": item_id}
