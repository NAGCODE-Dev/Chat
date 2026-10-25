#!/usr/bin/env python3
"""Benchmark local dos três modelos recomendados na arquitetura."""

from __future__ import annotations

import json
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from chat.tools.wishlist import WishlistUpdateArgs

OLLAMA_URL = "http://127.0.0.1:11434"
MODELS = (
    "qwen2.5:3b-instruct-q4_K_M",
    "llama3.2:3b-instruct-q4_K_M",
    "gemma3:4b-it-q4_K_M",
)
SYSTEM = (
    "Responda sempre em português brasileiro, com precisão e concisão. "
    "Siga as instruções e use ferramentas quando a solicitação exigir uma ação."
)
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "wishlist_update",
            "description": "Adiciona um desejo ou altera o estado de um item existente.",
            "parameters": WishlistUpdateArgs.model_json_schema(),
        },
    }
]


def measure(client: httpx.Client, model: str, kind: str, prompt: str, keep_alive: str | int) -> dict:
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": prompt},
        ],
        "stream": False,
        "keep_alive": keep_alive,
        "options": {"temperature": 0, "seed": 42, "num_predict": 160},
    }
    if kind == "tool_call":
        payload["tools"] = TOOLS
    started = time.perf_counter()
    response = client.post(f"{OLLAMA_URL}/api/chat", json=payload)
    elapsed = time.perf_counter() - started
    if response.is_error:
        return {
            "kind": kind,
            "wall_seconds": round(elapsed, 3),
            "error_status": response.status_code,
            "error": response.text,
        }
    data = response.json()
    message = data.get("message", {})
    tool_calls = message.get("tool_calls", [])
    stats = {
        key: data.get(key)
        for key in (
            "load_duration",
            "prompt_eval_count",
            "prompt_eval_duration",
            "eval_count",
            "eval_duration",
            "total_duration",
        )
    }
    eval_count, eval_duration = stats["eval_count"], stats["eval_duration"]
    stats["tokens_per_second"] = (
        round(eval_count / (eval_duration / 1_000_000_000), 2)
        if eval_count and eval_duration
        else None
    )
    return {
        "kind": kind,
        "wall_seconds": round(elapsed, 3),
        "content": message.get("content", ""),
        "tool_calls": tool_calls,
        "metrics": stats,
    }


def warm_up(client: httpx.Client, model: str) -> dict:
    started = time.perf_counter()
    response = client.post(
        f"{OLLAMA_URL}/api/chat",
        json={
            "model": model,
            "messages": [{"role": "user", "content": "Responda apenas: pronto."}],
            "stream": False,
            "keep_alive": "5m",
            "options": {"temperature": 0, "seed": 42, "num_predict": 2},
        },
    )
    elapsed = time.perf_counter() - started
    response.raise_for_status()
    data = response.json()
    return {
        "wall_seconds": round(elapsed, 3),
        "load_duration": data.get("load_duration"),
    }


def unload(client: httpx.Client, model: str) -> None:
    response = client.post(
        f"{OLLAMA_URL}/api/generate",
        json={"model": model, "prompt": "", "stream": False, "keep_alive": 0},
    )
    response.raise_for_status()


def main() -> None:
    prompts = (
        (
            "answer_quality",
            "Responda em até duas frases: quanto é 17 vezes 23 e como conferiu o resultado?",
        ),
        (
            "tool_call",
            "Adicione 'teclado mecânico' à minha lista de desejos.",
        ),
    )
    results = []
    with httpx.Client(timeout=300) as client:
        tags = client.get(f"{OLLAMA_URL}/api/tags")
        tags.raise_for_status()
        installed = {item["name"] for item in tags.json().get("models", [])}
        missing = sorted(set(MODELS) - installed)
        if missing:
            raise SystemExit(f"Modelos ausentes no Ollama: {', '.join(missing)}")
        for model in MODELS:
            warmup = warm_up(client, model)
            cases = [measure(client, model, kind, prompt, "5m") for kind, prompt in prompts]
            unload(client, model)
            results.append({"model": model, "warmup": warmup, "cases": cases})

    report = {
        "created_at_utc": datetime.now(UTC).isoformat(),
        "ollama_url": OLLAMA_URL,
        "method": {
            "sequence": "warm up once, then measure cases with the model already loaded; unload before next model",
            "sampling": {"temperature": 0, "seed": 42, "num_predict": 160},
            "cases": [kind for kind, _ in prompts],
            "tool_side_effects": "none; tool calls were inspected but not executed",
        },
        "results": results,
    }
    output = ROOT / "docs" / "benchmark-modelos-2026-10-24.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(output)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
