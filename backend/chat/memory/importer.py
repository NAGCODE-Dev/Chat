"""Importação em massa de memórias coladas do ChatGPT.

Aceita a lista em texto (uma memória por linha, com ou sem marcadores) e
também JSON simples. O objetivo é popular a memória sem exigir que a pessoa
reescreva tudo no formato interno.
"""

from __future__ import annotations

import json
import re
import unicodedata
from typing import Any

KINDS = ("personal", "preference", "project", "fact")
_MAX_ITEMS = 500
_MAX_CONTENT = 4000

_HEADINGS = {
    "memoria",
    "memorias",
    "memory",
    "memories",
    "o que o chatgpt sabe sobre voce",
    "o que eu sei sobre voce",
    "informacoes pessoais",
    "preferencias",
    "projetos",
    "fatos",
    "contexto",
    "sobre voce",
    "sobre mim",
}
_BULLET = re.compile(r"^\s*(?:[-*•·–—]|\d+[.)])\s*")


def _fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(char for char in normalized if not unicodedata.combining(char)).casefold()


def _classify(text: str) -> str:
    folded = _fold(text)
    if any(
        token in folded
        for token in (
            "prefere",
            "prefiro",
            "gosta",
            "gosto",
            "odeia",
            "nao gosta",
            "favorit",
            "estilo",
            "costuma",
            "preferencia",
        )
    ):
        return "preference"
    if any(
        token in folded
        for token in (
            "projeto",
            "trabalha",
            "trabalho",
            "empresa",
            "negocio",
            "desenvolv",
            "aplicativo",
            "app ",
            "site",
            "curso",
            "estuda",
            "cliente",
        )
    ):
        return "project"
    if any(
        token in folded
        for token in (
            "mora",
            "moro",
            "nasceu",
            "idade",
            "aniversario",
            "familia",
            "filho",
            "filha",
            "esposa",
            "marido",
            "email",
            "telefone",
            "cidade",
            "pais",
            "nome ",
        )
    ):
        return "fact"
    return "personal"


def _clean_line(line: str) -> str:
    value = line.strip().lstrip("#> ").strip()
    value = _BULLET.sub("", value).strip()
    value = re.sub(r"\s+", " ", value)
    return value


def _key_for(content: str, kind: str, used: set[str]) -> str:
    prefix = content.split(":", 1)[0].strip() if ":" in content[:80] else ""
    base = prefix if 2 <= len(prefix) <= 60 else " ".join(content.split()[:8])
    base = base.strip(" .:-")[:80] or content[:80]
    key = base
    counter = 2
    while f"{kind}:{key.casefold()}" in used:
        key = f"{base} ({counter})"
        counter += 1
    used.add(f"{kind}:{key.casefold()}")
    return key


def _from_json(payload: Any) -> list[tuple[str, str, str]] | None:
    items: list[Any] | None = None
    if isinstance(payload, list):
        items = payload
    elif isinstance(payload, dict):
        nested = payload.get("memories") or payload.get("memórias")
        if isinstance(nested, list):
            items = nested
        elif all(isinstance(value, str) for value in payload.values()):
            items = [{"key": key, "content": value} for key, value in payload.items()]
    if items is None:
        return None
    parsed: list[tuple[str, str, str]] = []
    for item in items:
        if isinstance(item, str):
            content = _clean_line(item)
            if content:
                parsed.append(("", "", content))
            continue
        if not isinstance(item, dict):
            continue
        content = str(
            item.get("content")
            or item.get("memory")
            or item.get("text")
            or item.get("value")
            or ""
        ).strip()
        if not content:
            continue
        key = str(item.get("key") or item.get("title") or "").strip()
        kind = str(item.get("kind") or "").strip().lower()
        if kind not in KINDS:
            kind = ""
        parsed.append((kind, key, content))
    return parsed


def parse_memory_dump(text: str, max_items: int = _MAX_ITEMS) -> list[dict[str, str]]:
    """Converte texto/JSON em memórias prontas para o MemoryStore."""
    raw = text.strip()
    if not raw:
        return []
    json_items: list[tuple[str, str, str]] | None = None
    if raw[:1] in "[{":
        try:
            json_items = _from_json(json.loads(raw))
        except (TypeError, ValueError):
            json_items = None

    candidates: list[tuple[str, str, str]] = []
    if json_items is not None:
        candidates = json_items
    else:
        lines = raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        for line in lines:
            cleaned = _clean_line(line)
            if not cleaned:
                continue
            if _fold(cleaned).strip(" :") in _HEADINGS:
                continue
            if len(cleaned) < 3:
                continue
            candidates.append(("", "", cleaned))
        if not candidates:
            # Texto corrido sem quebras: guarda como uma única memória.
            collapsed = re.sub(r"\s+", " ", raw).strip()
            if len(collapsed) >= 3:
                candidates = [("", "", collapsed[:_MAX_CONTENT])]

    parsed: list[dict[str, str]] = []
    seen: set[str] = set()
    used_keys: set[str] = set()
    for forced_kind, forced_key, content in candidates:
        cleaned = re.sub(r"\s+", " ", content).strip()
        if not cleaned:
            continue
        dedupe = _fold(cleaned)
        if dedupe in seen:
            continue
        seen.add(dedupe)
        cleaned = cleaned[:_MAX_CONTENT]
        kind = forced_kind if forced_kind in KINDS else _classify(cleaned)
        if forced_key:
            key = forced_key[:80]
            base = key
            counter = 2
            while f"{kind}:{key.casefold()}" in used_keys:
                key = f"{base} ({counter})"
                counter += 1
            used_keys.add(f"{kind}:{key.casefold()}")
        else:
            key = _key_for(cleaned, kind, used_keys)
        parsed.append({"kind": kind, "key": key, "content": cleaned})
        if len(parsed) >= max_items:
            break
    return parsed
