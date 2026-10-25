"""Provedor Ollama — implementação de ModelProvider via HTTP.

Consome a API nativa do Ollama (/api/chat) com httpx. Não impõe SDK;
só conhece a interface abstrata `ModelProvider` e o formato do Ollama.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from typing import Any

import httpx

from chat.core.logging import get_logger
from chat.providers.base import (
    Message,
    ModelInfo,
    ModelProvider,
    ModelResponse,
    ProviderError,
    ToolCall,
    ToolSpec,
)

log = get_logger("chat.providers.ollama")


def _to_ollama_message(m: Message) -> dict[str, Any]:
    result: dict[str, Any] = {"role": m.role, "content": m.content}
    if m.tool_calls:
        result["tool_calls"] = [
            {"function": {"name": tc.name, "arguments": tc.arguments}}
            for tc in m.tool_calls
        ]
    if m.tool_call_id:
        result["tool_name"] = m.name or ""
    return result


class OllamaProvider(ModelProvider):
    """Implementação concreta para Ollama."""

    def __init__(self, base_url: str = "http://127.0.0.1:11434", timeout: float = 120.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    @staticmethod
    def _build_payload(
        messages: list[Message],
        model: str,
        *,
        stream: bool,
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Monta o payload do Ollama.

        ``keep_alive`` é uma opção de ciclo de vida do Ollama, não um parâmetro
        de amostragem; por isso sai de ``options`` e vai para o nível raiz.
        """
        payload: dict[str, Any] = {
            "model": model,
            "messages": [_to_ollama_message(m) for m in messages],
            "stream": stream,
        }
        if options:
            model_options = dict(options)
            keep_alive = model_options.pop("keep_alive", None)
            if keep_alive is not None:
                payload["keep_alive"] = keep_alive
            if model_options:
                payload["options"] = model_options
        if tools:
            payload["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": t.parameters,
                    },
                }
                for t in tools
            ]
        return payload

    # --- geração ---

    async def chat(
        self,
        messages: list[Message],
        model: str,
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> ModelResponse:
        payload = self._build_payload(
            messages, model, stream=False, tools=tools, options=options
        )
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                r = await client.post(f"{self.base_url}/api/chat", json=payload)
                r.raise_for_status()
        except httpx.HTTPError as e:
            raise ProviderError(f"Ollama indisponível ou erro HTTP: {e}") from e

        data = r.json()
        msg = data.get("message", {})
        tool_calls = [
            ToolCall(
                id=tc.get("id") or f"tc_{i}",
                name=tc.get("function", {}).get("name", ""),
                arguments=tc.get("function", {}).get("arguments", {}),
            )
            for i, tc in enumerate(msg.get("tool_calls", []))
        ]
        return ModelResponse(
            content=msg.get("content", ""),
            tool_calls=tool_calls,
            finish_reason="tool_calls" if tool_calls else "stop",
            raw={"model": data.get("model"), "eval_count": data.get("eval_count")},
        )

    async def stream(
        self,
        messages: list[Message],
        model: str,
        options: dict[str, Any] | None = None,
    ) -> AsyncIterator[str]:
        payload = self._build_payload(messages, model, stream=True, options=options)
        try:
            async with (
                httpx.AsyncClient(timeout=self.timeout) as client,
                client.stream("POST", f"{self.base_url}/api/chat", json=payload) as r,
            ):
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if not line:
                        continue
                    chunk = json.loads(line)
                    content = chunk.get("message", {}).get("content", "")
                    if content:
                        yield content
                    if chunk.get("done"):
                        break
        except httpx.HTTPError as e:
            raise ProviderError(f"Erro de streaming no Ollama: {e}") from e

    async def stream_events(
        self,
        messages: list[Message],
        model: str,
        tools: list[ToolSpec] | None = None,
        options: dict[str, Any] | None = None,
    ) -> AsyncIterator[dict[str, Any]]:
        payload = self._build_payload(
            messages, model, stream=True, tools=tools, options=options
        )
        try:
            async with (
                httpx.AsyncClient(timeout=self.timeout) as client,
                client.stream("POST", f"{self.base_url}/api/chat", json=payload) as response,
            ):
                response.raise_for_status()
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    chunk = json.loads(line)
                    msg = chunk.get("message", {})
                    if msg.get("content"):
                        yield {"content": msg["content"]}
                    calls = []
                    for index, item in enumerate(msg.get("tool_calls", [])):
                        function = item.get("function", {})
                        args = function.get("arguments", {})
                        if isinstance(args, str):
                            args = json.loads(args)
                        calls.append(ToolCall(
                            id=item.get("id") or f"tc_{index}",
                            name=function.get("name", ""), arguments=args,
                        ))
                    if calls:
                        yield {"tool_calls": calls}
                    if chunk.get("done"):
                        break
        except (httpx.HTTPError, json.JSONDecodeError) as e:
            raise ProviderError(f"Erro de streaming no Ollama: {e}") from e

    # --- metadados ---

    async def loaded_models(self) -> dict[str, int]:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                r = await client.get(f"{self.base_url}/api/ps")
                r.raise_for_status()
        except httpx.HTTPError:
            return {}
        loaded: dict[str, int] = {}
        for item in r.json().get("models", []):
            name = item.get("name")
            if name:
                loaded[name] = int(item.get("size", 0)) // (1024 * 1024)
        return loaded

    async def unload(self, model: str) -> None:
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                await client.post(
                    f"{self.base_url}/api/generate",
                    json={
                        "model": model,
                        "prompt": "",
                        "stream": False,
                        "keep_alive": 0,
                    },
                )
        except httpx.HTTPError as error:
            log.warning("falha ao descarregar modelo %s: %s", model, error)

    async def list_models(self) -> list[ModelInfo]:
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                r = await client.get(f"{self.base_url}/api/tags")
                r.raise_for_status()
        except httpx.HTTPError as e:
            raise ProviderError(f"Não foi possível listar modelos: {e}") from e
        return [
            ModelInfo(id=m["name"], name=m.get("details", {}).get("family", m["name"]))
            for m in r.json().get("models", [])
        ]

    async def health(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=3) as client:
                r = await client.get(f"{self.base_url}/api/tags")
                return r.status_code == 200
        except httpx.HTTPError:
            return False
