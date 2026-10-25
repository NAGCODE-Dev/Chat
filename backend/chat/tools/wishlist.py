"""Ferramentas de consulta e edição da lista de desejos."""

from __future__ import annotations

from pydantic import Field

from chat.memory.db import Database
from chat.tools.base import Permission, Tool, ToolArguments, ToolResult


class WishlistQueryArgs(ToolArguments):
    status: str | None = Field(default=None, pattern="^(aberto|comprado|descartado)$")


class WishlistQuery(Tool):
    name = "wishlist_query"
    description = "Consulta itens da lista de desejos, sem alterá-los."
    permission = Permission.SAFE
    arguments_model = WishlistQueryArgs

    def __init__(self, db: Database):
        self.db = db

    async def run(self, arguments: dict) -> ToolResult:
        status = arguments.get("status")
        sql = "SELECT id,title,notes,priority,status,url FROM wishlist"
        params: tuple = ()
        if status:
            sql += " WHERE status=?"
            params = (status,)
        sql += " ORDER BY priority DESC, id DESC LIMIT 30"
        rows = await self.db.fetch_all(sql, params)
        return ToolResult("Nenhum item encontrado." if not rows else str(rows))


class WishlistUpdateArgs(ToolArguments):
    action: str = Field(pattern="^(add|set_status)$")
    title: str | None = Field(default=None, min_length=1, max_length=200)
    item_id: int | None = Field(default=None, gt=0)
    status: str | None = Field(default=None, pattern="^(aberto|comprado|descartado)$")
    notes: str | None = Field(default=None, max_length=1000)
    url: str | None = Field(default=None, max_length=2000)


class WishlistUpdate(Tool):
    name = "wishlist_update"
    description = "Adiciona um desejo ou altera o estado de um item existente."
    permission = Permission.CONFIRM
    arguments_model = WishlistUpdateArgs

    def __init__(self, db: Database):
        self.db = db

    async def run(self, arguments: dict) -> ToolResult:
        action = arguments["action"]
        if action == "add":
            if not arguments.get("title"):
                return ToolResult("Informe o título para adicionar.", False)
            item_id = await self.db.execute(
                "INSERT INTO wishlist(title,notes,url) VALUES (?,?,?)",
                (arguments["title"], arguments.get("notes"), arguments.get("url")),
            )
            return ToolResult(f"Item {item_id} adicionado à lista.")
        if not arguments.get("item_id") or not arguments.get("status"):
            return ToolResult("Informe item_id e status para atualizar.", False)
        await self.db.execute(
            "UPDATE wishlist SET status=?,updated_at=datetime('now') WHERE id=?",
            (arguments["status"], arguments["item_id"]),
        )
        row = await self.db.fetch_one("SELECT changes() AS count")
        changed = row["count"] if row else 0
        return ToolResult("Estado atualizado." if changed else "Item não encontrado.", bool(changed))
