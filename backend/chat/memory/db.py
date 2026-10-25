"""Camada de acesso ao SQLite: conexão, migrações e acesso concorrente.

Design:
- Um único arquivo de banco (config.resolved_db_path), em modo WAL.
- Migrações numeradas, idempotentes, executadas na inicialização.
- Todas as tabelas do projeto definidas aqui — a memória é independente
  do modelo de linguagem.
"""

from __future__ import annotations

import aiosqlite

from chat.core.logging import get_logger

log = get_logger("chat.memory.db")

MIGRATIONS: list[tuple[int, str]] = [
    (
        1,
        """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );

        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL DEFAULT 'Nova conversa',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            role TEXT NOT NULL CHECK (role IN ('system','user','assistant','tool')),
            content TEXT NOT NULL,
            tool_calls_json TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_messages_conversation
            ON messages(conversation_id, created_at);

        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL CHECK (kind IN ('personal','preference','project','fact')),
            key TEXT NOT NULL,
            content TEXT NOT NULL,
            source_message_id INTEGER,
            active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_memories_key ON memories(key);

        CREATE TABLE IF NOT EXISTS wishlist (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            notes TEXT,
            priority INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'aberto'
                CHECK (status IN ('aberto','comprado','descartado')),
            url TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            mac TEXT,
            tailscale_ip TEXT,
            last_known_state TEXT NOT NULL DEFAULT 'desconhecido',
            last_seen TEXT,
            wol_supported_states TEXT
        );

        CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actor TEXT NOT NULL,
            action TEXT NOT NULL,
            args_json TEXT,
            result TEXT,
            confirmed_by_user INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            content, content=memories, content_rowid=id, tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
            INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
        END;
        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, content)
            VALUES ('delete', old.id, old.content);
        END;
        CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, content)
            VALUES ('delete', old.id, old.content);
            INSERT INTO memories_fts(rowid, content) VALUES (new.id, new.content);
        END;
        """,
    ),
    (
        2,
        """
        ALTER TABLE messages ADD COLUMN tool_call_id TEXT;
        ALTER TABLE messages ADD COLUMN name TEXT;
        CREATE INDEX IF NOT EXISTS idx_messages_tool_call ON messages(tool_call_id);
        """,
    ),
    (
        3,
        """
        CREATE TABLE IF NOT EXISTS memory_embeddings (
            memory_id INTEGER PRIMARY KEY REFERENCES memories(id) ON DELETE CASCADE,
            model TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector BLOB NOT NULL,
            content_hash TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_memory_embeddings_model
            ON memory_embeddings(model);
        """,
    ),
    (
        4,
        """
        CREATE TABLE IF NOT EXISTS finance_transactions (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL CHECK (type IN ('entrada','saida','investimento')),
            value REAL NOT NULL CHECK (value > 0),
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_finance_transactions_date
            ON finance_transactions(date DESC, created_at DESC);

        CREATE TABLE IF NOT EXISTS finance_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            settings_json TEXT NOT NULL,
            investments_json TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """,
    ),
    (
        5,
        """
        ALTER TABLE messages ADD COLUMN sources_json TEXT;
        """,
    ),
]


class Database:
    """Wrapper assíncrono sobre aiosqlite com migrações automáticas."""

    def __init__(self, path: str) -> None:
        self.path = path
        self._conn: aiosqlite.Connection | None = None

    async def connect(self) -> None:
        self._conn = await aiosqlite.connect(self.path)
        self._conn.row_factory = aiosqlite.Row
        await self._conn.execute("PRAGMA journal_mode=WAL")
        await self._conn.execute("PRAGMA foreign_keys=ON")
        await self.migrate()

    async def close(self) -> None:
        if self._conn:
            await self._conn.close()
            self._conn = None

    @property
    def conn(self) -> aiosqlite.Connection:
        assert self._conn is not None, "Database.connect() precisa ser chamado antes"
        return self._conn

    async def migrate(self) -> None:
        async with self.conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)"
        ):
            pass
        row = await (
            await self.conn.execute("SELECT MAX(version) v FROM schema_version")
        ).fetchone()
        current = row["v"] or 0
        for version, sql in MIGRATIONS:
            if version <= current:
                continue
            log.info("aplicando migração %d", version)
            await self.conn.executescript(sql)
            await self.conn.execute("INSERT INTO schema_version(version) VALUES (?)", (version,))
        await self.conn.commit()

    async def execute(self, sql: str, params: tuple = ()) -> int:
        cur = await self.conn.execute(sql, params)
        await self.conn.commit()
        return cur.lastrowid  # type: ignore[return-value]

    async def fetch_all(self, sql: str, params: tuple = ()) -> list[dict]:
        rows = await (await self.conn.execute(sql, params)).fetchall()
        return [dict(r) for r in rows]

    async def fetch_one(self, sql: str, params: tuple = ()) -> dict | None:
        row = await (await self.conn.execute(sql, params)).fetchone()
        return dict(row) if row else None
