"""Aplicação FastAPI do backend.

Registra providers disponíveis, inicializa o serviço de chat e monta as rotas.
"""

from __future__ import annotations

import hmac
import ipaddress
import json
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.responses import Response

from chat.agent_orchestration.chat_service import ChatService
from chat.api.body_limit import RequestBodyLimitMiddleware
from chat.api.rate_limit import rate_limiter
from chat.api.routes_chat import router as chat_router
from chat.api.routes_devices import router as devices_router
from chat.api.routes_finance import router as finance_router
from chat.api.routes_memory import router as memory_router
from chat.api.routes_models import router as models_router
from chat.api.routes_pairing import (
    is_public_pairing_request,
)
from chat.api.routes_pairing import (
    router as pairing_router,
)
from chat.api.routes_settings import router as settings_router
from chat.api.routes_voice import router as voice_router
from chat.api.routes_wishlist import router as wishlist_router
from chat.api.state import state
from chat.core.config import Settings, load_settings
from chat.core.logging import get_logger
from chat.memory.db import Database
from chat.memory.embeddings import EmbeddingProvider, OllamaEmbeddingProvider
from chat.memory.personal import MemoryStore
from chat.providers.fake_provider import FakeProvider
from chat.providers.ollama_provider import OllamaProvider
from chat.providers.registry import available_providers, create_provider, register
from chat.tools.agent import AgentExec, DeviceStatus
from chat.tools.currency import CurrencyQuote
from chat.tools.devices import DeviceList, DeviceWake
from chat.tools.finance import FinanceAdd, FinanceSummary
from chat.tools.phone import PhoneAction
from chat.tools.web import FetchPage, OpenURL, WebSearch
from chat.tools.wishlist import WishlistQuery, WishlistUpdate
from chat.voice.piper_tts import PiperTTS
from chat.voice.whisper_cpp import WhisperCppSTT

log = get_logger("chat.api")

# registro dos providers: trocar o modelo aqui não afeta o resto do sistema
register("fake", lambda: FakeProvider())
register("ollama", lambda: OllamaProvider())


def _create_embedder(settings: Settings) -> EmbeddingProvider | None:
    """Cria o provedor de embeddings apenas quando ele foi configurado."""
    provider = (settings.embedding_provider or "none").strip().lower()
    if provider in {"", "none", "off", "disabled"}:
        return None
    if provider == "ollama":
        return OllamaEmbeddingProvider(
            model=settings.embedding_model,
            base_url=settings.embedding_base_url or settings.provider_base_url,
            timeout=settings.embedding_timeout_seconds,
        )
    raise RuntimeError(f"CHAT_EMBEDDING_PROVIDER desconhecido: {provider}")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    state.settings = load_settings()
    try:
        is_loopback = ipaddress.ip_address(state.settings.host).is_loopback
    except ValueError:
        is_loopback = state.settings.host.lower() == "localhost"
    if not is_loopback and not state.settings.api_token:
        raise RuntimeError("CHAT_API_TOKEN é obrigatório quando CHAT_HOST não é loopback.")
    if state.settings.api_token and len(state.settings.api_token) < 32:
        raise RuntimeError("CHAT_API_TOKEN precisa ter pelo menos 32 caracteres.")
    if state.settings.rate_limit_per_minute < 1:
        raise RuntimeError("CHAT_RATE_LIMIT_PER_MINUTE precisa ser positivo.")
    if state.settings.ws_message_rate_per_minute < 1:
        raise RuntimeError("CHAT_WS_MESSAGE_RATE_PER_MINUTE precisa ser positivo.")
    if not 60 <= state.settings.pairing_ttl_seconds <= 900:
        raise RuntimeError("CHAT_PAIRING_TTL_SECONDS precisa estar entre 60 e 900.")
    if state.settings.embedding_timeout_seconds <= 0:
        raise RuntimeError("CHAT_EMBEDDING_TIMEOUT_SECONDS precisa ser positivo.")
    if state.settings.embedding_batch_size < 1:
        raise RuntimeError("CHAT_EMBEDDING_BATCH_SIZE precisa ser positivo.")
    if not 0.0 <= state.settings.embedding_min_similarity <= 1.0:
        raise RuntimeError("CHAT_EMBEDDING_MIN_SIMILARITY precisa estar entre 0 e 1.")
    if state.settings.model_auto and not state.settings.model_large:
        raise RuntimeError("CHAT_MODEL_AUTO requer CHAT_MODEL_LARGE.")
    if state.settings.model_auto_min_free_mb < 1024:
        raise RuntimeError("CHAT_MODEL_AUTO_MIN_FREE_MB precisa ser pelo menos 1024.")
    if state.settings.model_auto_keep_free_mb < 512:
        raise RuntimeError("CHAT_MODEL_AUTO_KEEP_FREE_MB precisa ser pelo menos 512.")
    agent_tls_values = (
        state.settings.agent_tls_ca,
        state.settings.agent_tls_client_cert,
        state.settings.agent_tls_client_key,
    )
    if any(agent_tls_values) and not all(agent_tls_values):
        raise RuntimeError("mTLS do agente requer CA, certificado e chave de cliente.")
    if all(agent_tls_values) and state.settings.agent_url and not state.settings.agent_url.startswith("https://"):
        raise RuntimeError("CHAT_AGENT_URL precisa usar HTTPS quando mTLS está configurado.")
    state.db = Database(str(state.settings.resolved_db_path))
    await state.db.connect()
    for key in ("provider", "model"):
        saved = await state.db.fetch_one("SELECT value_json FROM settings WHERE key=?", (key,))
        if saved:
            setattr(state.settings, key, json.loads(saved["value_json"]))
    register("ollama", lambda: OllamaProvider(base_url=state.settings.provider_base_url))
    state.provider = create_provider(state.settings.provider)
    state.embedder = _create_embedder(state.settings)
    state.memory_store = MemoryStore(
        state.db,
        embedder=state.embedder,
        embedding_model=state.settings.embedding_model if state.embedder else None,
        batch_size=state.settings.embedding_batch_size,
        min_similarity=state.settings.embedding_min_similarity,
    )
    state.chat_service = ChatService(
        state.settings, state.db, state.provider, memories=state.memory_store
    )
    state.tools = [
        WishlistQuery(state.db), WishlistUpdate(state.db),
        WebSearch(state.settings.web_search_url), FetchPage(), OpenURL(),
        CurrencyQuote(),
        PhoneAction(),
        FinanceAdd(state.db), FinanceSummary(state.db),
        DeviceList(state.db), DeviceWake(state.db),
    ]
    if state.settings.agent_url and state.settings.agent_token:
        state.tools.extend([
            DeviceStatus(
                state.settings.agent_url, state.settings.agent_token,
                state.settings.agent_tls_ca, state.settings.agent_tls_client_cert,
                state.settings.agent_tls_client_key,
            ),
            AgentExec(
                state.settings.agent_url, state.settings.agent_token,
                state.settings.agent_tls_ca, state.settings.agent_tls_client_cert,
                state.settings.agent_tls_client_key,
            ),
        ])
    state.chat_service.tools = state.tools
    state.stt_engine = (
        WhisperCppSTT(
            state.settings.whisper_model_path,
            binary=state.settings.whisper_binary,
            language=state.settings.whisper_language,
            timeout=state.settings.voice_timeout_seconds,
        )
        if state.settings.whisper_model_path
        else None
    )
    state.tts_engine = (
        PiperTTS(
            state.settings.piper_model_path,
            timeout=state.settings.voice_timeout_seconds,
        )
        if state.settings.piper_model_path
        else None
    )
    log.info(
        "backend pronto | db=%s | provider=%s | model=%s | disponíveis=%s",
        state.settings.resolved_db_path,
        state.settings.provider,
        state.settings.model,
        available_providers(),
    )
    yield
    if state.db:
        await state.db.close()
    state.memory_store = None
    state.embedder = None


app = FastAPI(title="Chat Backend", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    RequestBodyLimitMiddleware,
    max_bytes=26 * 1024 * 1024,
    detail="Corpo excede o limite global de 26 MiB.",
)


@app.middleware("http")
async def require_api_token(request: Request, call_next) -> Response:
    if state.settings:
        rate_limiter.requests = state.settings.rate_limit_per_minute
    client_key = request.client.host if request.client else "unknown"
    allowed, retry_after = rate_limiter.allow(client_key)
    if not allowed:
        return JSONResponse(
            status_code=429,
            content={"detail": "Limite de requisições excedido."},
            headers={"Retry-After": str(retry_after)},
        )
    token = state.settings.api_token if state.settings else None
    path = request.url.path
    is_finance_shell = path == "/finance" or path.startswith("/finance/")
    is_pairing = is_public_pairing_request(request)
    if token and not is_finance_shell and not is_pairing:
        authorization = request.headers.get("authorization", "")
        supplied = authorization.removeprefix("Bearer ")
        if not hmac.compare_digest(supplied, token):
            return JSONResponse(status_code=401, content={"detail": "Token inválido."})
    return await call_next(request)
app.include_router(chat_router)
app.include_router(memory_router)
app.include_router(pairing_router)
app.include_router(models_router)
app.include_router(voice_router)
app.include_router(devices_router)
app.include_router(wishlist_router)
app.include_router(settings_router)
app.include_router(finance_router)
app.mount(
    "/finance",
    StaticFiles(
        directory=Path(__file__).resolve().parent.parent / "finance" / "static",
        html=True,
    ),
    name="finance",
)


@app.get("/health")
async def health() -> dict:
    provider_ok = bool(state.provider) and await state.provider.health()
    return {
        "status": "ok",
        "version": app.version,
        "provider": state.settings.provider if state.settings else None,
        "model": state.settings.model if state.settings else None,
        "model_auto": state.settings.model_auto if state.settings else None,
        "model_large": state.settings.model_large if state.settings else None,
        "provider_healthy": provider_ok,
        "providers_available": available_providers(),
        "voice": {
            "stt_available": state.stt_engine is not None,
            "tts_available": state.tts_engine is not None,
        },
    }
