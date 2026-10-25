"""Cotação de moedas em fontes públicas.

A ferramenta consulta a AwesomeAPI (dólar e outras moedas negociadas no
Brasil) e, quando necessário, a Open Exchange Rates. O resultado sempre
inclui a fonte e o horário para que a resposta não invente valores.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import httpx
from pydantic import Field, field_validator

from chat.tools.base import Permission, Tool, ToolArguments, ToolResult

_AWESOME_URL = "https://economia.awesomeapi.com.br/json/last/{source}-{target}"
_OPEN_ER_URL = "https://open.er-api.com/v6/latest/{source}"
_CURRENCY_NAMES = {
    "USD": "Dólar americano",
    "EUR": "Euro",
    "GBP": "Libra esterlina",
    "JPY": "Iene japonês",
    "ARS": "Peso argentino",
    "CLP": "Peso chileno",
    "UYU": "Peso uruguaio",
    "CAD": "Dólar canadense",
    "AUD": "Dólar australiano",
    "CHF": "Franco suíço",
    "CNY": "Yuan chinês",
    "BRL": "Real brasileiro",
}


def _format_number(value: float, digits: int = 4) -> str:
    text = f"{value:,.{digits}f}"
    return text.replace(",", "X").replace(".", ",").replace("X", ".")


def _parse_awesome(payload: dict[str, Any], source: str, target: str) -> dict[str, Any] | None:
    data = payload.get(f"{source}{target}")
    if not isinstance(data, dict):
        return None
    try:
        bid = float(data["bid"])
    except (KeyError, TypeError, ValueError):
        return None
    ask_raw = data.get("ask")
    try:
        ask = float(ask_raw) if ask_raw not in (None, "") else bid
    except (TypeError, ValueError):
        ask = bid
    pct_raw = data.get("pctChange")
    try:
        pct = float(pct_raw) if pct_raw not in (None, "") else None
    except (TypeError, ValueError):
        pct = None
    updated = ""
    timestamp = data.get("timestamp")
    if timestamp not in (None, ""):
        try:
            updated = datetime.fromtimestamp(int(timestamp)).strftime("%d/%m/%Y %H:%M")
        except (TypeError, ValueError, OSError):
            updated = str(data.get("create_date") or "")
    return {
        "source": source,
        "target": target,
        "bid": bid,
        "ask": ask,
        "pct": pct,
        "updated": updated,
        "provider": "AwesomeAPI",
        "url": _AWESOME_URL.format(source=source, target=target),
    }


def _format_quote(quote: dict[str, Any]) -> str:
    source = quote["source"]
    target = quote["target"]
    name = _CURRENCY_NAMES.get(source, source)
    pair = f"{source}/{target}"
    bid = _format_number(quote["bid"])
    ask = _format_number(quote["ask"])
    if target == "BRL":
        lines = [f"**{name} ({pair}):** R$ {bid}"]
        if quote["ask"] != quote["bid"]:
            lines.append(f"Compra R$ {bid} · Venda R$ {ask}")
    else:
        lines = [f"**{name} ({pair}):** 1 {source} = {bid} {target}"]
    pct = quote.get("pct")
    if pct is not None:
        signal = "+" if pct >= 0 else ""
        lines.append(f"Variação no dia: **{signal}{_format_number(pct, 2)}%**")
    if quote.get("updated"):
        lines.append(f"Atualizado em {quote['updated']}")
    lines.append(f"Fonte: {quote['provider']}")
    return "\n".join(lines)


class CurrencyQuoteArgs(ToolArguments):
    from_currency: str = Field(default="USD", min_length=3, max_length=3)
    to_currency: str = Field(default="BRL", min_length=3, max_length=3)

    @field_validator("from_currency", "to_currency")
    @classmethod
    def valid_code(cls, value: str) -> str:
        code = value.strip().upper()
        if len(code) != 3 or not code.isalpha():
            raise ValueError("use um código ISO de três letras, como USD ou BRL")
        return code


class CurrencyQuote(Tool):
    name = "currency_quote"
    description = (
        "Consulta a cotação atual de uma moeda em fontes públicas. Use sempre "
        "que a pessoa perguntar quanto está o dólar, o euro ou outra moeda. "
        "Informe o valor, a variação e a fonte; nunca invente uma cotação."
    )
    permission = Permission.SAFE
    arguments_model = CurrencyQuoteArgs

    async def run(self, arguments: dict) -> ToolResult:
        source = arguments.get("from_currency", "USD")
        target = arguments.get("to_currency", "BRL")
        quote = await self._awesome(source, target)
        if quote is not None:
            return ToolResult(
                _format_quote(quote),
                sources=[
                    {
                        "title": f"{quote['provider']} — {source}/{target}",
                        "url": quote["url"],
                        "snippet": f"Cotação {source}/{target}: {quote['bid']}",
                    }
                ],
            )
        quote = await self._open_er(source, target)
        if quote is not None:
            return ToolResult(
                _format_quote(quote),
                sources=[
                    {
                        "title": f"{quote['provider']} — {source}/{target}",
                        "url": quote["url"],
                        "snippet": f"1 {source} = {quote['bid']} {target}",
                    }
                ],
            )
        return ToolResult(
            "Não consegui consultar a cotação agora. Tente novamente em instantes.",
            False,
        )

    @staticmethod
    async def _awesome(source: str, target: str) -> dict[str, Any] | None:
        url = _AWESOME_URL.format(source=source, target=target)
        try:
            async with httpx.AsyncClient(timeout=8, follow_redirects=True) as client:
                response = await client.get(url)
                response.raise_for_status()
                payload = response.json()
        except (httpx.HTTPError, ValueError):
            return None
        if not isinstance(payload, dict):
            return None
        return _parse_awesome(payload, source, target)

    @staticmethod
    async def _open_er(source: str, target: str) -> dict[str, Any] | None:
        url = _OPEN_ER_URL.format(source=source)
        try:
            async with httpx.AsyncClient(timeout=8, follow_redirects=True) as client:
                response = await client.get(url)
                response.raise_for_status()
                payload = response.json()
        except (httpx.HTTPError, ValueError):
            return None
        if not isinstance(payload, dict) or payload.get("result") != "success":
            return None
        rate = payload.get("rates", {}).get(target)
        if not isinstance(rate, (int, float)):
            return None
        updated = ""
        timestamp = payload.get("time_last_update_unix")
        if isinstance(timestamp, (int, float)):
            try:
                updated = datetime.fromtimestamp(int(timestamp)).strftime("%d/%m/%Y %H:%M")
            except (ValueError, OSError):
                updated = ""
        return {
            "source": source,
            "target": target,
            "bid": float(rate),
            "ask": float(rate),
            "pct": None,
            "updated": updated,
            "provider": "Open Exchange Rates",
            "url": url,
        }
