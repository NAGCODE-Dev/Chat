"""Ferramentas do assistente para o app Meu Dinheiro."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import Field, field_validator, model_validator

from chat.finance.store import (
    CATEGORIES,
    FinanceStore,
    TransactionCreate,
    _fold,
    describe_transaction,
    format_summary,
    normalize_month,
)
from chat.memory.db import Database
from chat.tools.base import Permission, Tool, ToolArguments, ToolResult

_ALL_TIME_TRUE = {
    "all",
    "all time",
    "alltime",
    "geral",
    "historico",
    "historico completo",
    "todos",
    "todo",
    "tudo",
}


def _coerce_all_time(value: Any) -> bool:
    """Aceita booleano, número ou texto; só o histórico completo vira True."""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, (int, float)):
        return bool(value)
    folded = " ".join(
        _fold(str(value)).replace("_", " ").replace("-", " ").split()
    )
    return bool(
        folded in _ALL_TIME_TRUE
        or "histor" in folded
        or folded.startswith("all")
    )


class FinanceAddArgs(ToolArguments):
    type: Literal["entrada", "saida", "investimento"]
    value: float = Field(gt=0, le=1_000_000_000)
    category: str = Field(default="Outros", max_length=40)
    date: str | None = Field(default=None, max_length=10)
    note: str = Field(default="", max_length=200)


class FinanceAdd(Tool):
    name = "finance_add"
    description = (
        "Registra um lançamento no app Meu Dinheiro. Use quando a pessoa pedir "
        "para anotar, registrar ou lançar um gasto, uma receita ou um aporte. "
        "type: entrada (receita), saida (gasto) ou investimento (aporte). "
        "value em reais, sempre positivo. category: "
        + ", ".join(CATEGORIES)
        + ". date opcional no formato AAAA-MM-DD; se a pessoa disser 'hoje', "
        "omita date (o servidor usa a data atual). note é uma descrição curta "
        "opcional."
    )
    permission = Permission.SAFE
    arguments_model = FinanceAddArgs

    def __init__(self, db: Database):
        self.store = FinanceStore(db)

    async def run(self, arguments: dict) -> ToolResult:
        try:
            transaction = await self.store.add_transaction(
                TransactionCreate(**arguments)
            )
        except ValueError as error:
            return ToolResult(f"Não registrei o lançamento: {error}", False)
        return ToolResult(f"Lançamento registrado: {describe_transaction(transaction)}")


class FinanceSummaryArgs(ToolArguments):
    month: str | None = Field(
        default=None,
        max_length=40,
        description="Mês específico: AAAA-MM, nome do mês ou DD/MM/AAAA.",
    )
    period: Literal["mes_atual", "mes_passado", "todos"] = Field(
        default="mes_atual",
        description="mes_atual (padrão), mes_passado ou todos.",
    )

    @field_validator("month", mode="before")
    @classmethod
    def validate_month(cls, value: object) -> str | None:
        if value is None:
            return None
        return normalize_month(str(value))

    @field_validator("period", mode="before")
    @classmethod
    def validate_period(cls, value: object) -> str:
        folded = " ".join(
            _fold(str(value or "")).replace("_", " ").replace("-", " ").split()
        )
        aliases = {
            "atual": "mes_atual",
            "este mes": "mes_atual",
            "mes atual": "mes_atual",
            "current month": "mes_atual",
            "this month": "mes_atual",
            "mes passado": "mes_passado",
            "ultimo mes": "mes_passado",
            "last month": "mes_passado",
            "previous month": "mes_passado",
            "todos": "todos",
            "todo": "todos",
            "tudo": "todos",
            "all": "todos",
            "all time": "todos",
            "historico": "todos",
        }
        return aliases.get(folded, "mes_atual")

    @model_validator(mode="before")
    @classmethod
    def accept_legacy_arguments(cls, data: object) -> object:
        if not isinstance(data, dict):
            return data
        values = dict(data)
        legacy_all_time = values.pop("all_time", None)
        if legacy_all_time is not None and _coerce_all_time(legacy_all_time):
            values["period"] = "todos"
        return values


class FinanceSummary(Tool):
    name = "finance_summary"
    description = (
        "Consulta o resumo de lançamentos do app Meu Dinheiro. period pode ser "
        "mes_atual (padrão), mes_passado ou todos. Para um mês específico, use "
        "month como AAAA-MM; month tem prioridade sobre period. Retorna "
        "entradas, saídas, investimentos, saldo e gastos por categoria."
    )
    permission = Permission.SAFE
    arguments_model = FinanceSummaryArgs

    def __init__(self, db: Database):
        self.store = FinanceStore(db)

    async def run(self, arguments: dict) -> ToolResult:
        period = arguments.get("period", "mes_atual")
        month = arguments.get("month")
        if month is None and period == "mes_passado":
            month = normalize_month("mês passado")
        all_time = period == "todos" and month is None
        try:
            summary = await self.store.summary(month=month, all_time=all_time)
        except ValueError as error:
            return ToolResult(f"Não consultei o resumo: {error}", False)
        return ToolResult(format_summary(summary))
