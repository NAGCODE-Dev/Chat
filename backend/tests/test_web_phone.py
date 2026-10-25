"""Testes offline da busca web e das ações de celular."""

from __future__ import annotations

import base64
from datetime import datetime, timedelta

import pytest
from pydantic import ValidationError

from chat.agent_orchestration.chat_service import ChatService
from chat.api.routes_chat import ChatRequest
from chat.core.config import Settings
from chat.memory.db import Database
from chat.providers.base import ToolCall
from chat.providers.fake_provider import FakeProvider
from chat.tools.base import ToolError
from chat.tools.phone import (
    DEVICE_ACTION_PREFIX,
    PhoneAction,
    describe_device_action,
    parse_device_action,
)
from chat.tools.web import (
    _ensure_public_url,
    html_to_text,
    is_news_query,
    news_topic,
    parse_bing_news_rss,
    parse_bing_results,
)


def _bing_redirect(url: str) -> str:
    encoded = base64.urlsafe_b64encode(url.encode()).decode().rstrip("=")
    return f"https://www.bing.com/ck/a?u=a1{encoded}"


def test_parse_bing_results_decodes_redirect_and_snippet():
    target = "https://example.com/noticia"
    html = f"""
    <ol>
      <li class="b_algo">
        <h2><a href="{_bing_redirect(target)}">Título da notícia</a></h2>
        <div class="b_caption"><p>Resumo <b>importante</b> da notícia.</p></div>
      </li>
      <li class="b_algo">
        <h2><a href="https://example.org/outra">Outra</a></h2>
        <p>Segundo resumo.</p>
      </li>
    </ol>
    """
    results = parse_bing_results(html)
    assert results == [
        {
            "title": "Título da notícia",
            "url": target,
            "snippet": "Resumo importante da notícia.",
        },
        {
            "title": "Outra",
            "url": "https://example.org/outra",
            "snippet": "Segundo resumo.",
        },
    ]


def test_news_query_cleans_topic_and_recognizes_request():
    assert is_news_query("Pesquise notícias de tecnologia de hoje")
    assert is_news_query("quais as últimas notícias sobre o dólar?")
    assert not is_news_query("lembra daquela notícia que te contei?")
    assert news_topic("Pesquise notícias de tecnologia de hoje") == "tecnologia"
    assert news_topic("me mostre notícias sobre inteligência artificial") == (
        "inteligência artificial"
    )
    assert news_topic("quais as notícias de hoje?") == "notícias"


def test_parse_bing_news_rss_uses_publisher_and_decodes_link():
    rss = """<?xml version="1.0" encoding="utf-8" ?>
    <rss version="2.0" xmlns:News="https://www.bing.com/news/search">
      <channel>
        <item>
          <title>OpenAI anuncia novidade</title>
          <link>https://www.bing.com/news/apiclick.aspx?url=https%3a%2f%2fexemplo.com%2fia&amp;c=1</link>
          <description>Resumo &amp; detalhes da notícia.</description>
          <pubDate>Sat, 24 Oct 2026 12:00:00 GMT</pubDate>
          <News:Source>Exemplo</News:Source>
        </item>
      </channel>
    </rss>"""
    results = parse_bing_news_rss(rss)
    assert len(results) == 1
    assert results[0]["title"] == "OpenAI anuncia novidade"
    assert results[0]["url"] == "https://exemplo.com/ia"
    assert results[0]["snippet"] == "Resumo & detalhes da notícia."
    assert results[0]["source"] == "Exemplo"
    assert "24/10/2026" in results[0]["published"]


def test_news_answer_formats_vehicle_relative_date_and_no_links():
    now = datetime.now().astimezone()
    yesterday = now - timedelta(days=1)
    items = [
        {
            "title": "Nova descoberta de tecnologia",
            "source": "g1",
            "published": yesterday.strftime("%d/%m/%Y %H:%M"),
            "snippet": "Resumo da matéria com detalhes importantes.",
            "url": "https://example.com/noticia",
        },
        {
            "title": "Outra matéria do dia",
            "source": "Folha",
            "published": yesterday.strftime("%d/%m/%Y %H:%M"),
            "snippet": "Segundo resumo.",
            "url": "https://example.org/outra",
        },
    ]
    answer = ChatService._news_answer("Pesquise notícias de tecnologia de hoje", items)
    assert "**Tecnologia**" in answer
    assert "a mais recente é de ontem" in answer
    assert "**Nova descoberta de tecnologia**" in answer
    assert "g1, ontem" in answer
    assert "Folha, ontem" in answer
    assert "http" not in answer
    assert "example.com" not in answer


def test_news_answer_uses_manchetes_for_generic_topic():
    now = datetime.now().astimezone()
    items = [
        {
            "title": "Manchete principal",
            "source": "g1",
            "published": now.strftime("%d/%m/%Y %H:%M"),
            "snippet": "Resumo.",
            "url": "https://example.com",
        }
    ]
    answer = ChatService._news_answer("quais as notícias de hoje?", items)
    assert "Separei 1 manchete" in answer
    assert "hoje" in answer
    assert "**Manchete principal**" in answer


async def test_news_stream_uses_rss_without_calling_model(tmp_path, monkeypatch):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        service = ChatService(
            Settings(provider="fake", model="fake-model"),
            db,
            FakeProvider(),
        )
        now = datetime.now().astimezone()
        items = [
            {
                "title": "Notícia já formatada",
                "source": "g1",
                "published": now.strftime("%d/%m/%Y %H:%M"),
                "snippet": "Resumo vindo do RSS.",
                "url": "https://example.com/noticia",
            }
        ]
        sources = [
            {
                "title": "g1: Notícia já formatada",
                "url": "https://example.com/noticia",
                "snippet": "Resumo vindo do RSS.",
            }
        ]

        async def fake_prefetch(_text: str):
            return items, sources

        monkeypatch.setattr(service, "_prefetch_news", fake_prefetch)
        events = [
            event
            async for event in service.stream_user_message(
                "Pesquise notícias de tecnologia de hoje"
            )
        ]
        done = next(event for event in events if event["type"] == "done")
        assert done["model"] == "news_rss"
        assert "g1, hoje" in done["content"]
        assert done["sources"] == sources
        assert "http" not in done["content"]
        rows = await db.fetch_all(
            "SELECT role, sources_json FROM messages ORDER BY id"
        )
        assert rows[-1]["role"] == "assistant"
        assert rows[-1]["sources_json"]
    finally:
        await db.close()


def test_html_to_text_skips_scripts_and_styles():
    text = html_to_text(
        "<html><head><style>p{color:red}</style></head>"
        "<body><h1>Olá</h1><script>alert(1)</script><p>Mundo &amp; cia</p></body></html>"
    )
    assert "Olá" in text
    assert "Mundo & cia" in text
    assert "alert" not in text
    assert "color" not in text


async def test_fetch_page_blocks_private_addresses():
    with pytest.raises(ToolError, match="interno"):
        await _ensure_public_url("http://127.0.0.1:8750/health")
    with pytest.raises(ToolError, match="interno"):
        await _ensure_public_url("http://localhost:11434/api/tags")


async def test_phone_action_returns_marker():
    tool = PhoneAction()
    args = tool.validate_arguments({"action": "open_app", "target": "WhatsApp"})
    result = await tool.run(args)
    assert result.content.startswith(DEVICE_ACTION_PREFIX)
    action = parse_device_action(result.content)
    assert action == {"action": "open_app", "target": "WhatsApp"}
    assert "WhatsApp" in describe_device_action(action)


def test_phone_action_requires_target_and_valid_url():
    tool = PhoneAction()
    with pytest.raises(ToolError):
        tool.validate_arguments({"action": "open_app", "target": ""})
    with pytest.raises(ToolError):
        tool.validate_arguments({"action": "open_url", "target": "file:///etc/passwd"})
    assert tool.validate_arguments(
        {"action": "open_url", "target": "https://example.com"}
    )["target"] == "https://example.com"


def test_chat_request_accepts_device_context_and_rejects_too_long():
    request = ChatRequest(message="oi", device_context="notificação: nova mensagem")
    assert request.device_context == "notificação: nova mensagem"
    with pytest.raises(ValidationError):
        ChatRequest(message="oi", device_context="x" * 6001)


class _ToolCallingProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.rounds = 0

    async def stream_events(self, messages, model, tools=None, options=None):
        self.rounds += 1
        if self.rounds == 1:
            yield {
                "tool_calls": [
                    ToolCall(
                        id="call-1",
                        name="phone_action",
                        arguments={"action": "open_app", "target": "WhatsApp"},
                    )
                ]
            }
        else:
            yield {"content": "Abrindo o WhatsApp."}


async def test_stream_yields_device_action_and_hides_marker(tmp_path):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        provider = _ToolCallingProvider()
        settings = Settings(provider="fake", model="fake-model")
        service = ChatService(settings, db, provider)
        service.tools = [PhoneAction()]
        events = [
            event
            async for event in service.stream_user_message("abrir o WhatsApp")
        ]
        device_events = [event for event in events if event["type"] == "device_action"]
        assert device_events == [
            {
                "type": "device_action",
                "action": "open_app",
                "target": "WhatsApp",
                "tool_call_id": "call-1",
            }
        ]
        assert any(event["type"] == "done" for event in events)
        rows = await db.fetch_all("SELECT content FROM messages WHERE role='tool'")
        assert rows
        assert all("__DEVICE_ACTION__" not in row["content"] for row in rows)
    finally:
        await db.close()
