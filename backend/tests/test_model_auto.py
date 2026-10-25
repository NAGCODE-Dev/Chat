"""Seleção automática de modelo por memória disponível."""

from __future__ import annotations

from chat.agent_orchestration import chat_service
from chat.agent_orchestration.chat_service import ChatService
from chat.core.config import Settings
from chat.providers.base import ModelInfo
from chat.providers.fake_provider import FakeProvider
from chat.providers.ollama_provider import OllamaProvider


class _ModelListProvider(FakeProvider):
    def __init__(self, models: set[str], loaded: dict[str, int] | None = None) -> None:
        super().__init__()
        self.models = models
        self.loaded = loaded or {}
        self.unloaded: list[str] = []

    async def list_models(self) -> list[ModelInfo]:
        return [ModelInfo(id=name, name=name) for name in sorted(self.models)]

    async def loaded_models(self) -> dict[str, int]:
        return dict(self.loaded)

    async def unload(self, model: str) -> None:
        self.unloaded.append(model)
        self.loaded.pop(model, None)


def _service(
    models: set[str] | None = None,
    loaded: dict[str, int] | None = None,
    **settings_kwargs,
) -> ChatService:
    settings_kwargs.setdefault("model_auto", True)
    settings = Settings(
        provider="ollama",
        model="small-model",
        model_large="large-model",
        model_auto_min_free_mb=4096,
        **settings_kwargs,
    )
    provider = _ModelListProvider(
        models or {"small-model", "large-model"}, loaded=loaded
    )
    return ChatService(settings, db=None, provider=provider)  # type: ignore[arg-type]


def _memory(monkeypatch, available: int, swap_free: int = 2048, pressure: float = 0.0) -> None:
    monkeypatch.setattr(chat_service, "memory_available_mb", lambda: available)
    monkeypatch.setattr(chat_service, "swap_free_mb", lambda: swap_free)
    monkeypatch.setattr(chat_service, "memory_pressure_full_avg10", lambda: pressure)


async def test_uses_large_model_when_memory_is_plentiful(monkeypatch):
    _memory(monkeypatch, available=6000)
    assert await _service()._select_model() == "large-model"


async def test_falls_back_to_small_model_when_memory_is_low(monkeypatch):
    _memory(monkeypatch, available=3500)
    assert await _service()._select_model() == "small-model"


async def test_falls_back_when_swap_is_low(monkeypatch):
    _memory(monkeypatch, available=6000, swap_free=100)
    assert await _service()._select_model() == "small-model"


async def test_falls_back_under_memory_pressure(monkeypatch):
    _memory(monkeypatch, available=6000, pressure=20.0)
    assert await _service()._select_model() == "small-model"


async def test_falls_back_when_large_model_is_not_installed(monkeypatch):
    _memory(monkeypatch, available=6000)
    assert await _service(models={"small-model"})._select_model() == "small-model"


async def test_auto_mode_disabled_uses_configured_model(monkeypatch):
    _memory(monkeypatch, available=6000)
    service = _service(model_auto=False)
    assert await service._select_model() == "small-model"


async def test_switches_to_large_by_unloading_small_when_effective_memory_allows(monkeypatch):
    _memory(monkeypatch, available=4300)
    service = _service(loaded={"small-model": 2100})
    assert await service._select_model() == "large-model"
    assert service.provider.unloaded == ["small-model"]


async def test_does_not_switch_when_effective_memory_is_low(monkeypatch):
    _memory(monkeypatch, available=1500)
    service = _service(loaded={"small-model": 2100})
    assert await service._select_model() == "small-model"
    assert service.provider.unloaded == []


async def test_keeps_loaded_large_model_under_moderate_pressure(monkeypatch):
    _memory(monkeypatch, available=1500)
    service = _service(loaded={"large-model": 2500})
    assert await service._select_model() == "large-model"
    assert service.provider.unloaded == []


async def test_unloads_large_model_under_heavy_pressure(monkeypatch):
    _memory(monkeypatch, available=800, pressure=20.0)
    service = _service(loaded={"large-model": 2500})
    assert await service._select_model() == "small-model"
    assert service.provider.unloaded == ["large-model"]


def test_provider_options_use_shorter_keep_alive_for_large_model():
    service = _service()
    small_options = service._provider_options("small-model")
    large_options = service._provider_options("large-model")
    assert small_options["keep_alive"] == "5m"
    assert large_options["keep_alive"] == "2m"


def test_ollama_payload_moves_keep_alive_to_root():
    payload = OllamaProvider._build_payload(
        [], "model", stream=False, options={"temperature": 0.1, "keep_alive": "30s"}
    )
    assert payload["keep_alive"] == "30s"
    assert payload["options"] == {"temperature": 0.1}
