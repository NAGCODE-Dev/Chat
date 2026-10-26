"""Camada de memória: conversas e mensagens.

O histórico é fonte de contexto, não de memória de longo prazo
(a memória estruturada vive na tabela `memories`, Fase 2).
"""

from __future__ import annotations

import json

from chat.memory.db import Database


class ConversationStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def create_conversation(self, title: str = "Nova conversa") -> int:
        return await self.db.execute("INSERT INTO conversations(title) VALUES (?)", (title,))

    async def add_message(
        self, conversation_id: int, role: str, content: str, tool_calls_json: str | None = None,
        tool_call_id: str | None = None, name: str | None = None,
        sources_json: str | None = None, attachments_json: str | None = None,
    ) -> int:
        msg_id = await self.db.execute(
            "INSERT INTO messages(conversation_id, role, content, tool_calls_json, "
            "tool_call_id, name, sources_json, attachments_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                conversation_id,
                role,
                content,
                tool_calls_json,
                tool_call_id,
                name,
                sources_json,
                attachments_json,
            ),
        )
        await self.db.execute(
            "UPDATE conversations SET updated_at = datetime('now') WHERE id = ?",
            (conversation_id,),
        )
        return msg_id

    async def get_history(self, conversation_id: int, limit: int = 10) -> list[dict]:
        rows = await self.db.fetch_all(
            "SELECT role, content, tool_calls_json, tool_call_id, name FROM messages "
            "WHERE conversation_id = ? ORDER BY id DESC LIMIT ?",
            (conversation_id, limit),
        )
        return list(reversed(rows))

    async def list_conversations(self, limit: int = 50) -> list[dict]:
        return await self.db.fetch_all(
            "SELECT c.id, c.title, c.created_at, c.updated_at, "
            "(SELECT m.content FROM messages m "
            " WHERE m.conversation_id = c.id "
            "   AND m.role IN ('user','assistant') "
            "   AND trim(m.content) <> '' "
            " ORDER BY m.id DESC LIMIT 1) AS last_message "
            "FROM conversations c ORDER BY c.updated_at DESC LIMIT ?",
            (limit,),
        )

    async def get_messages(self, conversation_id: int) -> list[dict]:
        rows = await self.db.fetch_all(
            "SELECT id, role, content, created_at, name, tool_call_id, sources_json, "
            "attachments_json FROM messages WHERE conversation_id = ? ORDER BY id",
            (conversation_id,),
        )
        for row in rows:
            sources: list[dict] = []
            if row.get("sources_json"):
                try:
                    parsed = json.loads(row["sources_json"])
                except (TypeError, ValueError):
                    parsed = []
                if isinstance(parsed, list):
                    sources = [item for item in parsed if isinstance(item, dict)]
            row["sources"] = sources
            row.pop("sources_json", None)
            attachments: list[dict] = []
            if row.get("attachments_json"):
                try:
                    parsed = json.loads(row["attachments_json"])
                except (TypeError, ValueError):
                    parsed = []
                if isinstance(parsed, list):
                    attachments = [item for item in parsed if isinstance(item, dict)]
            row["attachments"] = attachments
            row.pop("attachments_json", None)
        return rows

    async def delete_conversation(self, conversation_id: int) -> None:
        await self.db.execute("DELETE FROM conversations WHERE id = ?", (conversation_id,))
