"""Saudação, importação de memórias, fontes e roteamento rápido."""

from __future__ import annotations

import asyncio
import json
import random

from chat.agent_orchestration.chat_service import ChatService, _strip_links
from chat.core.config import Settings
from chat.memory.db import Database
from chat.memory.greeting import build_greeting
from chat.memory.importer import parse_memory_dump
from chat.providers.base import ModelInfo, ToolCall
from chat.providers.fake_provider import FakeProvider
from chat.tools.base import Permission, Tool, ToolArguments, ToolResult
from chat.tools.currency import CurrencyQuoteArgs


def test_import_dump_splits_bullets_and_classifies():
    parsed = parse_memory_dump(
        """
        # Memórias
        - Prefiro respostas curtas e diretas.
        - Moro em São Paulo.
        - Meu projeto atual é o aplicativo Chat.
        - Prefiro respostas curtas e diretas.
        """
    )
    assert len(parsed) == 3
    kinds = {item["kind"] for item in parsed}
    assert "preference" in kinds
    assert "fact" in kinds
    assert "project" in kinds


def test_import_dump_accepts_json_list():
    parsed = parse_memory_dump(
        json.dumps(
            [
                {"kind": "preference", "key": "tom", "content": "Gosto de tom direto."},
                {"content": "Trabalho com desenvolvimento."},
            ]
        )
    )
    assert len(parsed) == 2
    assert parsed[0]["kind"] == "preference"
    assert parsed[0]["key"] == "tom"


def test_import_and_greeting_endpoints(client):
    response = client.post(
        "/api/memories/import",
        json={
            "text": "- Prefiro respostas curtas.\n"
            "- Moro em São Paulo.\n"
            "- Meu projeto atual é o Chat."
        },
    )
    assert response.status_code == 200
    assert response.json()["imported"] == 3
    assert response.json()["memory_count"] == 3

    greeting = client.get("/api/memories/greeting")
    assert greeting.status_code == 200
    body = greeting.json()
    assert body["memory_count"] == 3
    assert body["greeting"]
    assert "3" in body["greeting"] or "detalhe" in body["greeting"]


def test_greeting_is_varied_without_model():
    stats = {"total": 7, "kinds": {"fact": 7}, "latest": None}
    greetings = {build_greeting(stats, random.Random(seed))["greeting"] for seed in range(20)}
    assert len(greetings) > 1


def test_currency_intent_detection():
    service = ChatService(
        Settings(provider="fake", model="fake-model"), None, FakeProvider()
    )  # type: ignore[arg-type]
    assert service._currency_codes("Qual a cotação do dólar?") == ("USD", "BRL")
    assert service._currency_codes("Quanto está o euro em real?") == ("EUR", "BRL")
    assert service._currency_codes("cotação do dólar para euro") == ("USD", "EUR")
    assert service._currency_codes("Qual é a capital da França?") is None


def test_simple_prompt_heuristic():
    service = ChatService(
        Settings(provider="fake", model="fake-model"), None, FakeProvider()
    )  # type: ignore[arg-type]
    assert not service._is_simple_prompt("oi")
    assert service._is_simple_prompt("Explique o que é a taxa Selic em uma frase.")
    assert not service._is_simple_prompt("hoje eu estou meio cansado, quer conversar?")
    assert not service._is_simple_prompt("Qual a cotação do dólar?")
    assert not service._is_simple_prompt("Pesquise notícias de hoje")
    assert not service._is_simple_prompt("Qual a previsão do tempo para hoje?")
    assert not service._is_simple_prompt("x" * 400)


def test_direct_smalltalk_answers_without_model():
    service = ChatService(
        Settings(provider="fake", model="fake-model"), None, FakeProvider()
    )  # type: ignore[arg-type]
    assert service._direct_smalltalk_answer("Oi, tudo bem?")
    assert service._direct_smalltalk_answer("Bom dia!")
    assert service._direct_smalltalk_answer("Obrigado!")
    assert service._direct_smalltalk_answer("Tchau!")
    assert service._direct_smalltalk_answer("Quanto custa o dólar?") is None


def test_strip_links_keeps_text_and_removes_urls():
    cleaned = _strip_links(
        "Veja **isso** em [OpenAI](https://openai.com/noticia) ou "
        "https://example.com. Fonte: OpenAI — https://openai.com"
    )
    assert "http" not in cleaned
    assert "[OpenAI]" not in cleaned
    assert "OpenAI" in cleaned
    assert "**isso**" in cleaned


class _SourceArgs(ToolArguments):
    pass


class _SourceTool(Tool):
    name = "source_tool"
    description = "Ferramenta de teste que devolve uma fonte."
    permission = Permission.SAFE
    arguments_model = _SourceArgs

    async def run(self, arguments: dict) -> ToolResult:
        return ToolResult(
            "Resultado com fonte.",
            sources=[
                {
                    "title": "Fonte de teste",
                    "url": "https://example.com/fonte",
                    "snippet": "Trecho da fonte.",
                }
            ],
        )


class _SourceProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.rounds = 0

    async def stream_events(self, messages, model, tools=None, options=None):
        if self.rounds == 0:
            self.rounds += 1
            yield {
                "tool_calls": [
                    ToolCall(id="call-source", name="source_tool", arguments={})
                ]
            }
        else:
            yield {"content": "Resposta baseada na fonte."}


async def test_sources_are_persisted_and_sent_in_done(tmp_path):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        service = ChatService(
            Settings(provider="fake", model="fake-model"),
            db,
            _SourceProvider(),
        )
        service.tools = [_SourceTool()]
        events = [
            event
            async for event in service.stream_user_message("consulte a fonte")
        ]
        assert events[0]["type"] == "conversation"
        done = events[-1]
        assert done["type"] == "done"
        assert done["sources"] == [
            {
                "title": "Fonte de teste",
                "url": "https://example.com/fonte",
                "snippet": "Trecho da fonte.",
            }
        ]
        assert done["content"] == "Resposta baseada na fonte."
        assert "http" not in done["content"]
        rows = await db.fetch_all(
            "SELECT content, sources_json FROM messages WHERE role='assistant' "
            "ORDER BY id DESC LIMIT 1"
        )
        assert rows[0]["content"] == "Resposta baseada na fonte."
        assert "https://example.com/fonte" in rows[0]["sources_json"]

        stored = await service.store.get_messages(done["conversation_id"])
        assistant = [row for row in stored if row["role"] == "assistant"][-1]
        assert assistant["sources"][0]["url"] == "https://example.com/fonte"
    finally:
        await db.close()


class _LengthProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.calls = 0
        self.contexts = []

    async def stream_events(self, messages, model, tools=None, options=None):
        self.contexts.append(messages)
        if self.calls == 0:
            self.calls += 1
            yield {"content": "Primeira parte, "}
            yield {"done_reason": "length"}
            return
        yield {"content": "segunda parte."}
        yield {"done_reason": "stop"}


async def test_stream_continues_when_provider_hits_token_limit(tmp_path):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        provider = _LengthProvider()
        service = ChatService(
            Settings(provider="fake", model="fake-model"),
            db,
            provider,
        )
        events = [
            event
            async for event in service.stream_user_message(
                "Escreva uma explicação longa sobre manutenção preventiva."
            )
        ]
        done = events[-1]
        assert done["type"] == "done"
        assert done["content"] == "Primeira parte, segunda parte."
        assert provider.calls == 1
        second_context = provider.contexts[-1]
        assert any(
            message.role == "system" and "interrompida" in message.content
            for message in second_context
        )
        stored = await service.store.get_messages(done["conversation_id"])
        assistant = [row for row in stored if row["role"] == "assistant"][-1]
        assert assistant["content"] == "Primeira parte, segunda parte."
    finally:
        await db.close()


class _FastProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.models = {"small-model", "fast-model"}

    async def list_models(self) -> list[ModelInfo]:
        return [ModelInfo(id=name, name=name) for name in sorted(self.models)]


async def test_fast_model_is_used_for_simple_prompts():
    service = ChatService(
        Settings(
            provider="ollama",
            model="small-model",
            model_fast="fast-model",
            model_auto=False,
        ),
        None,  # type: ignore[arg-type]
        _FastProvider(),
    )
    assert await service._select_model("Explique o que é a taxa Selic em uma frase.") == "fast-model"
    assert await service._select_model("Qual a cotação do dólar?") == "small-model"
    # Conversa pessoal nunca usa o modelo rápido, que inventa intimidade.
    assert await service._select_model("oi, tudo bem?") == "small-model"
    assert await service._select_model("hoje eu estou cansado") == "small-model"


def test_provider_options_use_threads_and_shorter_prediction():
    service = ChatService(
        Settings(provider="ollama", model="small-model"), None, FakeProvider()
    )  # type: ignore[arg-type]
    options = service._provider_options("small-model")
    assert options["num_thread"] == 6
    assert options["num_predict"] == 1024
    assert options["num_ctx"] == 8192
    assert service._provider_options("small-model", simple=True)["num_predict"] == 512


def test_personality_prompt_is_loaded_from_its_own_file():
    settings = Settings()
    assert "PERSONALIDADE E ESTILO DE COMUNICAÇÃO" in settings.system_prompt
    assert "REGRAS DO APLICATIVO" in settings.system_prompt
    assert "próximo e caloroso" not in settings.system_prompt.lower()
    assert "Você é o assistente, não o usuário" in settings.system_prompt
    assert "PERSONALIDADE E ESTILO" not in settings.system_prompt_fast


def test_direct_currency_shortcut_avoids_provider(tmp_path, monkeypatch):
    class _NoModelProvider(FakeProvider):
        async def stream_events(self, messages, model, tools=None, options=None):
            raise AssertionError("o modelo não deveria ser chamado")
            yield {}  # pragma: no cover

    class _FakeCurrency(_SourceTool):
        name = "currency_quote"
        description = "Cotação de teste."
        arguments_model = CurrencyQuoteArgs

        async def run(self, arguments: dict) -> ToolResult:
            return ToolResult(
                "Cotação USD/BRL: R$ 5,00",
                sources=[
                    {
                        "title": "Fonte de cotação",
                        "url": "https://example.com/cotacao",
                        "snippet": "USD/BRL 5,00",
                    }
                ],
            )

    async def _run() -> list[dict]:
        db = Database(str(tmp_path / "chat.db"))
        await db.connect()
        try:
            service = ChatService(
                Settings(provider="fake", model="fake-model"),
                db,
                _NoModelProvider(),
            )
            service.tools = [_FakeCurrency()]
            return [
                event
                async for event in service.stream_user_message(
                    "Qual a cotação do dólar?"
                )
            ]
        finally:
            await db.close()

    events = asyncio.run(_run())
    assert events[0]["type"] == "conversation"
    assert events[-1]["type"] == "done"
    assert events[-1]["model"] == "currency_quote"
    assert events[-1]["sources"][0]["url"] == "https://example.com/cotacao"
    assert any(
        event["type"] == "token" and "R$ 5,00" in event["content"]
        for event in events
    )
