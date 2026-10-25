"""Estado compartilhado da aplicação.

Mantido separado de `main.py` para evitar importação circular entre
a aplicação e as rotas.
"""

from __future__ import annotations

from chat.agent_orchestration.chat_service import ChatService
from chat.memory.db import Database
from chat.memory.embeddings import EmbeddingProvider
from chat.memory.personal import MemoryStore
from chat.voice.base import STTEngine, TTSEngine


class AppState:
    def __init__(self) -> None:
        self.settings = None
        self.db: Database | None = None
        self.provider = None
        self.chat_service: ChatService | None = None
        self.memory_store: MemoryStore | None = None
        self.embedder: EmbeddingProvider | None = None
        self.stt_engine: STTEngine | None = None
        self.tts_engine: TTSEngine | None = None
        self.tools = []


state = AppState()
