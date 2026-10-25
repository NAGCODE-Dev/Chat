"""Registro de provedores de modelo.

Trocar de LLM em runtime: `set_provider("ollama", model="...")`.
Nenhuma outra parte do sistema conhece os nomes dos provedores.
"""

from __future__ import annotations

from collections.abc import Callable

from chat.providers.base import ModelProvider

_PROVIDERS: dict[str, Callable[[], ModelProvider]] = {}


def register(name: str, factory: Callable[[], ModelProvider]) -> None:
    _PROVIDERS[name] = factory


def create_provider(name: str) -> ModelProvider:
    if name not in _PROVIDERS:
        raise KeyError(f"Provider '{name}' não registrado. Disponíveis: {sorted(_PROVIDERS)}")
    return _PROVIDERS[name]()


def available_providers() -> list[str]:
    return sorted(_PROVIDERS)
