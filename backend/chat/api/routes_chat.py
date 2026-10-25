"""Rotas de conversa: POST /api/chat, histórico, listagem e exclusão."""

from __future__ import annotations

import hmac
import json

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ConfigDict, Field

from chat.agent_orchestration.chat_service import ChatService, ChatTurn
from chat.api.rate_limit import RateLimiter, rate_limiter
from chat.api.state import state
from chat.core.logging import get_logger
from chat.memory.conversations import ConversationStore

router = APIRouter(prefix="/api", tags=["chat"])
log = get_logger("chat.routes_chat")
MAX_WEBSOCKET_MESSAGE_BYTES = 64 * 1024


async def _receive_websocket_json(websocket: WebSocket) -> dict:
    raw = await websocket.receive_text()
    if len(raw.encode("utf-8")) > MAX_WEBSOCKET_MESSAGE_BYTES:
        raise ValueError("Mensagem WebSocket excede o limite de 64 KiB.")
    return json.loads(raw)


def _new_message_limiter() -> RateLimiter:
    limit = state.settings.ws_message_rate_per_minute if state.settings else 30
    return RateLimiter(requests=limit, window_seconds=60.0)


async def _receive_limited(websocket: WebSocket, limiter: RateLimiter) -> dict:
    """Aplica limite por conexão a cada frame recebido do cliente."""
    allowed, retry_after = limiter.allow("connection")
    if not allowed:
        detail = f"Limite de mensagens da conexão excedido; tente em {retry_after}s."
        try:
            await websocket.send_json({"type": "error", "detail": detail})
            await websocket.close(code=1013, reason=detail)
        except (WebSocketDisconnect, RuntimeError):
            # Cliente já desconectou; a exceção abaixo encerra o fluxo.
            pass
        raise WebSocketDisconnect(code=1013, reason=detail)
    return await _receive_websocket_json(websocket)


async def _safe_send(websocket: WebSocket, payload: dict) -> bool:
    """Envia um evento; devolve False se o cliente já tiver desconectado."""
    try:
        await websocket.send_json(payload)
    except (WebSocketDisconnect, RuntimeError):
        return False
    return True


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    message: str = Field(min_length=1, max_length=12_000)
    conversation_id: int | None = None
    device_context: str | None = Field(default=None, max_length=6000)


class ChatResponse(BaseModel):
    conversation_id: int
    reply: str
    model: str
    provider: str
    latency_ms: int


class ConversationListResponse(BaseModel):
    conversations: list[dict]


def get_chat_service() -> ChatService:
    if state.chat_service is None:
        raise HTTPException(status_code=503, detail="Serviço de chat não inicializado")
    return state.chat_service


@router.post("/chat", response_model=ChatResponse)
async def chat(
    req: ChatRequest,
    svc: ChatService = Depends(get_chat_service),  # noqa: B008
) -> ChatResponse:
    try:
        turn: ChatTurn = await svc.handle_user_message(
            req.message, req.conversation_id, req.device_context
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Erro ao gerar resposta: {e}") from e
    return ChatResponse(
        conversation_id=turn.conversation_id,
        reply=turn.content,
        model=turn.model,
        provider=turn.provider,
        latency_ms=turn.latency_ms,
    )


@router.websocket("/ws/chat")
async def stream_chat(websocket: WebSocket) -> None:
    """Recebe {message, conversation_id?}; envia eventos token e done em JSON."""
    rate_limiter.requests = state.settings.rate_limit_per_minute if state.settings else 120
    client_key = websocket.client.host if websocket.client else "unknown"
    allowed, retry_after = rate_limiter.allow(client_key)
    if not allowed:
        await websocket.close(code=1013, reason=f"Limite excedido; tente em {retry_after}s.")
        return
    token = state.settings.api_token if state.settings else None
    if token:
        supplied = websocket.headers.get("authorization", "").removeprefix("Bearer ")
        if not hmac.compare_digest(supplied, token):
            await websocket.close(code=1008, reason="Token inválido.")
            return
    await websocket.accept()
    message_limiter = _new_message_limiter()
    events = None
    try:
        try:
            payload = await _receive_limited(websocket, message_limiter)
            req = ChatRequest.model_validate(payload)
            svc = get_chat_service()
            events = svc.stream_user_message(
                req.message, req.conversation_id, req.device_context
            )
            event = await anext(events)
            while True:
                if not await _safe_send(websocket, event):
                    return
                if event.get("type") == "confirmation_required":
                    decision = await _receive_limited(websocket, message_limiter)
                    if (decision.get("type") != "confirmation" or
                            decision.get("tool_call_id") != event.get("tool_call_id") or
                            not isinstance(decision.get("approved"), bool)):
                        await _safe_send(
                            websocket,
                            {"type": "error", "detail": "Confirmação inválida."},
                        )
                        break
                    event = await events.asend(decision)
                else:
                    try:
                        event = await anext(events)
                    except StopAsyncIteration:
                        break
        except (ValueError, TypeError) as e:
            await _safe_send(websocket, {"type": "error", "detail": str(e)})
        except WebSocketDisconnect:
            return
        except Exception as e:  # noqa: BLE001
            await _safe_send(
                websocket,
                {"type": "error", "detail": f"Erro ao gerar resposta: {e}"},
            )
    finally:
        if events is not None:
            try:
                await events.aclose()
            except Exception as error:  # noqa: BLE001 - encerramento é melhor esforço
                log.debug("falha ao encerrar stream: %s", error)
        try:
            await websocket.close()
        except (WebSocketDisconnect, RuntimeError):
            pass


@router.get("/conversations", response_model=ConversationListResponse)
async def list_conversations() -> ConversationListResponse:
    store = ConversationStore(state.db)
    convs = await store.list_conversations()
    return ConversationListResponse(conversations=convs)


@router.get("/conversations/{conversation_id}/messages")
async def get_messages(conversation_id: int) -> dict:
    store = ConversationStore(state.db)
    msgs = await store.get_messages(conversation_id)
    return {"messages": msgs}


@router.delete("/conversations/{conversation_id}")
async def delete_conversation(conversation_id: int) -> dict:
    store = ConversationStore(state.db)
    await store.delete_conversation(conversation_id)
    return {"deleted": conversation_id}
