"""Testes do pareamento por QR e do aquecimento dinâmico de modelos."""

from __future__ import annotations

from typing import Any

import chat.api.routes_pairing as routes_pairing
from chat.agent_orchestration.chat_service import ChatService
from chat.api.routes_pairing import _qr_payload
from chat.core.config import Settings
from chat.pairing import PairingStore
from chat.providers.base import Message, ModelInfo, ModelResponse, ToolSpec
from chat.providers.fake_provider import FakeProvider


def test_pairing_code_is_single_use_and_expires():
    now = [1_000.0]
    store = PairingStore(clock=lambda: now[0])
    session = store.create(60)
    assert len(session.code) >= 16
    assert store.claim(session.code)
    assert not store.claim(session.code)
    expired = store.create(60)
    now[0] += 61
    assert len(store) == 0
    assert not store.claim(expired.code)


def test_qr_payload_contains_code_and_all_candidate_urls():
    payload = _qr_payload(
        "codigo-seguro",
        ["http://100.97.209.46:8750", "http://192.168.15.8:8750"],
    )
    assert payload.startswith("chatpair://pair?")
    assert "code=codigo-seguro" in payload
    assert "url=http%3A%2F%2F100.97.209.46%3A8750" in payload
    assert "url=http%3A%2F%2F192.168.15.8%3A8750" in payload


def test_pairing_status_returns_only_booleans(client, monkeypatch):
    monkeypatch.setattr(
        routes_pairing,
        "_local_ipv4_addresses",
        lambda: ["192.168.15.8"],
    )
    monkeypatch.setattr(
        routes_pairing,
        "_tailscale_status",
        lambda: {"installed": True, "logged_in": True, "online": True},
    )
    response = client.get("/api/pairing/status")
    assert response.status_code == 200
    body = response.json()
    assert body == {
        "pairing_available": True,
        "lan_available": True,
        "tailscale_installed": True,
        "tailscale_logged_in": True,
        "tailscale_online": True,
    }
    assert "192.168" not in response.text
    assert "100." not in response.text


class _WarmProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.warmed: list[str] = []
        self.options_seen: dict[str, Any] = {}

    async def list_models(self) -> list[ModelInfo]:
        return [
            ModelInfo(id="modelo-padrao", name="Padrão"),
            ModelInfo(id="modelo-rapido", name="Rápido"),
            ModelInfo(id="modelo-grande", name="Grande"),
        ]

    async def loaded_models(self) -> dict[str, int]:
        return {"modelo-rapido": 1100}

    async def chat(
        self,
        messages: list[Message],
        model: str = "fake-model",
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> ModelResponse:
        self.warmed.append(model)
        self.options_seen = options or {}
        return ModelResponse(content="ok")


async def test_warmup_candidates_are_derived_from_settings_and_skip_loaded():
    provider = _WarmProvider()
    settings = Settings(
        provider="ollama",
        model="modelo-padrao",
        model_fast="modelo-rapido",
        model_auto=True,
        model_large="modelo-grande",
        model_auto_min_free_mb=1024,
    )
    service = ChatService(settings, None, provider)  # type: ignore[arg-type]
    candidates = await service.warmup_candidates()
    assert candidates == ["modelo-padrao", "modelo-grande"]

    await service.warmup_model("modelo-padrao")
    assert provider.warmed == ["modelo-padrao"]
    assert provider.options_seen["num_predict"] == 1
    assert provider.options_seen["temperature"] == 0.0
