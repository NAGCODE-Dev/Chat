"""Estado e configuração persistente do provider ativo."""

from __future__ import annotations

import json

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from chat.api.state import state
from chat.providers.registry import available_providers, create_provider

router = APIRouter(prefix="/api/settings", tags=["settings"])


class ModelSettings(BaseModel):
    provider: str = Field(min_length=1, max_length=40)
    model: str = Field(min_length=1, max_length=160)


@router.get("")
async def get_settings() -> dict:
    if state.settings is None:
        raise HTTPException(status_code=503, detail="Configuração não inicializada.")
    return {
        "provider": state.settings.provider,
        "model": state.settings.model,
        "model_auto": state.settings.model_auto,
        "model_large": state.settings.model_large,
        "model_fast": state.settings.model_fast,
        "model_fast_max_chars": state.settings.model_fast_max_chars,
        "vision_model": state.settings.vision_model,
        "model_auto_min_free_mb": state.settings.model_auto_min_free_mb,
        "model_auto_keep_free_mb": state.settings.model_auto_keep_free_mb,
        "num_thread": state.settings.num_thread,
        "num_ctx": state.settings.num_ctx,
        "providers": [
            name
            for name in available_providers()
            if name != "fake" or state.settings.provider == "fake"
        ],
        "provider_base_url": state.settings.provider_base_url,
        "voice": {
            "stt_available": state.stt_engine is not None,
            "tts_available": state.tts_engine is not None,
        },
        "agent_configured": bool(state.settings.agent_url and state.settings.agent_token),
        "web_search_configured": True,
        "web_search_provider": "searxng" if state.settings.web_search_url else "bing",
    }


@router.get("/models")
async def list_models(provider: str | None = None) -> dict:
    selected = provider or state.settings.provider
    if selected not in available_providers():
        raise HTTPException(status_code=422, detail="Provider não registrado.")
    try:
        models = await create_provider(selected).list_models()
    except Exception as error:
        raise HTTPException(status_code=502, detail=f"Não foi possível listar modelos: {error}") from error
    return {"models": [model.__dict__ for model in models]}


@router.put("/model")
async def update_model(settings: ModelSettings) -> dict:
    if settings.provider not in available_providers():
        raise HTTPException(status_code=422, detail="Provider não registrado.")
    provider = create_provider(settings.provider)
    if settings.provider == "ollama":
        try:
            models = await provider.list_models()
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"Ollama indisponível: {error}") from error
        if settings.model not in {model.id for model in models}:
            raise HTTPException(status_code=422, detail="Modelo não encontrado no Ollama.")
    if state.db is None or state.settings is None or state.chat_service is None:
        raise HTTPException(status_code=503, detail="Serviço não inicializado.")
    for key, value in (("provider", settings.provider), ("model", settings.model)):
        await state.db.execute(
            "INSERT INTO settings(key,value_json) VALUES(?,?) "
            "ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json",
            (key, json.dumps(value)),
        )
    state.settings.provider = settings.provider
    state.settings.model = settings.model
    state.provider = provider
    state.chat_service.provider = provider
    state.chat_service.settings = state.settings
    return {"provider": settings.provider, "model": settings.model}
