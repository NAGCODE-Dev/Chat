"""Dados do app Meu Dinheiro: lançamentos, renda e investimentos.

O PWA é a interface; o backend é a fonte de verdade. Os lançamentos ficam em
uma tabela própria para que o assistente possa inserir um gasto sem sobrescrever
o que a pessoa estiver editando no PWA. Renda e investimentos ficam em um
estado JSON, editado apenas pela interface.
"""

from __future__ import annotations

import json
import re
import unicodedata
import uuid
from datetime import date, datetime, timedelta
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator

from chat.memory.db import Database

TransactionType = Literal["entrada", "saida", "investimento"]

CATEGORIES = (
    "Salário",
    "Freela",
    "Investimento",
    "Necessidades",
    "Comida",
    "Roupas",
    "Objetivos",
    "Lazer",
    "Outros",
)

DEFAULT_SETTINGS: dict[str, Any] = {
    "monthlyIncome": 1000,
    "month": "",
    "cdiRate": 14.90,
    "budget": {
        "necessidades": 20,
        "comida": 25,
        "patrimonio": 30,
        "objetivos": 15,
        "lazer": 10,
    },
}

TYPE_LABELS = {
    "entrada": "entrada",
    "saida": "saída",
    "investimento": "investimento",
}

MONTH_NAMES = (
    "janeiro",
    "fevereiro",
    "março",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
)

_CATEGORY_ALIASES = {
    "salario": "Salário",
    "salário": "Salário",
    "freela": "Freela",
    "freelance": "Freela",
    "investimento": "Investimento",
    "aporte": "Investimento",
    "necessidades": "Necessidades",
    "necessidade": "Necessidades",
    "contas": "Necessidades",
    "moradia": "Necessidades",
    "aluguel": "Necessidades",
    "transporte": "Necessidades",
    "combustivel": "Necessidades",
    "combustível": "Necessidades",
    "comida": "Comida",
    "alimentacao": "Comida",
    "alimentação": "Comida",
    "mercado": "Comida",
    "supermercado": "Comida",
    "restaurante": "Comida",
    "roupas": "Roupas",
    "vestuario": "Roupas",
    "vestuário": "Roupas",
    "objetivos": "Objetivos",
    "objetivo": "Objetivos",
    "lazer": "Lazer",
    "cinema": "Lazer",
    "jogo": "Lazer",
    "jogos": "Lazer",
    "outros": "Outros",
    "outro": "Outros",
}


def _fold(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value.strip().lower())
    return "".join(char for char in normalized if not unicodedata.combining(char))


_MONTH_NUMBERS = {
    _fold(name): number for number, name in enumerate(MONTH_NAMES, start=1)
}
_MONTH_NUMBERS.update(
    {_fold(name[:3]): number for number, name in enumerate(MONTH_NAMES, start=1)}
)

_CURRENT_MONTH_WORDS = {
    "atual",
    "este mes",
    "mes atual",
    "mes corrente",
    "current month",
    "this month",
}
_LAST_MONTH_WORDS = {
    "mes passado",
    "ultimo mes",
    "last month",
    "previous month",
}


def normalize_category(value: str | None) -> str:
    raw = (value or "").strip()
    if not raw:
        return "Outros"
    for category in CATEGORIES:
        if _fold(category) == _fold(raw):
            return category
    return _CATEGORY_ALIASES.get(_fold(raw), "Outros")


def normalize_date(value: str | None) -> str:
    """Aceita YYYY-MM-DD e DD/MM/YYYY; sem valor, usa hoje."""
    raw = (value or "").strip()
    if not raw:
        return date.today().isoformat()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y"):
        try:
            return datetime.strptime(raw, fmt).date().isoformat()
        except ValueError:
            continue
    raise ValueError("a data deve estar no formato AAAA-MM-DD ou DD/MM/AAAA")


def normalize_month(value: str | None, *, today: date | None = None) -> str | None:
    """Normaliza o mês para AAAA-MM.

    Aceita AAAA-MM, AAAA/MM, MM/AAAA, DD/MM/AAAA, ISO completo, nome do mês
    (com ano opcional) e expressões como "este mês" e "mês passado".
    """
    raw = (value or "").strip()
    if not raw:
        return None
    reference = today or date.today()

    folded = " ".join(
        _fold(raw).replace("/", " ").replace("-", " ").split()
    )
    if folded in _CURRENT_MONTH_WORDS:
        return reference.strftime("%Y-%m")
    if folded in _LAST_MONTH_WORDS:
        previous = reference.replace(day=1) - timedelta(days=1)
        return previous.strftime("%Y-%m")

    match = re.fullmatch(r"(\d{4})[-/](\d{1,2})[-/](\d{1,2})", raw)
    if match:
        raw = f"{match.group(1)}-{match.group(2)}"
    else:
        match = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", raw)
        if match:
            raw = f"{match.group(3)}-{match.group(2)}"

    match = re.fullmatch(r"(\d{4})[-/](\d{1,2})", raw)
    if match:
        year, month_number = int(match.group(1)), int(match.group(2))
    else:
        match = re.fullmatch(r"(\d{1,2})/(\d{4})", raw)
        if match:
            month_number, year = int(match.group(1)), int(match.group(2))
        else:
            tokens = [
                token
                for token in folded.split()
                if token not in {"de", "do", "da", "em"}
            ]
            year = next(
                (int(token) for token in tokens if token.isdigit() and len(token) == 4),
                reference.year,
            )
            month_number = next(
                (_MONTH_NUMBERS[token] for token in tokens if token in _MONTH_NUMBERS),
                0,
            )

    if not 1 <= month_number <= 12:
        raise ValueError(
            "o mês deve ser AAAA-MM, nome do mês ou 'este mês'/'mês passado'"
        )
    return f"{year:04d}-{month_number:02d}"


def brl(value: float) -> str:
    sign = "-" if value < 0 else ""
    formatted = f"{abs(value):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return f"{sign}R$ {formatted}"


def date_br(iso_date: str) -> str:
    try:
        return datetime.strptime(iso_date, "%Y-%m-%d").strftime("%d/%m/%Y")
    except ValueError:
        return iso_date


def month_label(month: str) -> str:
    try:
        year, month_number = month.split("-")
        return f"{MONTH_NAMES[int(month_number) - 1]}/{year}"
    except (ValueError, IndexError):
        return month


def describe_transaction(transaction: dict[str, Any]) -> str:
    label = TYPE_LABELS.get(str(transaction["type"]), str(transaction["type"]))
    note = str(transaction.get("note") or "").strip()
    suffix = f' — {note}' if note else ""
    return (
        f"{label} de {brl(float(transaction['value']))} em "
        f"{transaction['category']}, em {date_br(str(transaction['date']))}{suffix}."
    )


class TransactionCreate(BaseModel):
    type: TransactionType
    value: float = Field(gt=0, le=1_000_000_000)
    category: str = Field(default="Outros", max_length=40)
    date: str | None = Field(default=None, max_length=10)
    note: str = Field(default="", max_length=200)

    @field_validator("category")
    @classmethod
    def validate_category(cls, value: str) -> str:
        return normalize_category(value)

    @field_validator("date")
    @classmethod
    def validate_date(cls, value: str | None) -> str:
        return normalize_date(value)

    @field_validator("note")
    @classmethod
    def validate_note(cls, value: str) -> str:
        return value.strip()


class Budget(BaseModel):
    necessidades: float = Field(default=20, ge=0, le=100)
    comida: float = Field(default=25, ge=0, le=100)
    patrimonio: float = Field(default=30, ge=0, le=100)
    objetivos: float = Field(default=15, ge=0, le=100)
    lazer: float = Field(default=10, ge=0, le=100)


class FinanceSettings(BaseModel):
    monthlyIncome: float = Field(default=1000, ge=0, le=1_000_000_000)
    month: str = Field(default="", max_length=7)
    cdiRate: float = Field(default=14.90, ge=0, le=1000)
    budget: Budget = Field(default_factory=Budget)


class Investment(BaseModel):
    id: str | None = Field(default=None, max_length=64)
    name: str = Field(min_length=1, max_length=120)
    amount: float = Field(gt=0, le=1_000_000_000)
    type: Literal["monthly", "cdi"] = "monthly"
    rate: float = Field(default=0, ge=0)
    cdiPercent: float = Field(default=0, ge=0)


class FinanceStateUpdate(BaseModel):
    settings: FinanceSettings = Field(default_factory=FinanceSettings)
    investments: list[Investment] = Field(default_factory=list, max_length=200)


class FinanceStore:
    """Acesso assíncrono aos dados financeiros no SQLite."""

    def __init__(self, db: Database) -> None:
        self.db = db

    async def ensure_state(self) -> None:
        row = await self.db.fetch_one("SELECT id FROM finance_state WHERE id=1")
        if row is None:
            await self.db.execute(
                "INSERT INTO finance_state(id, settings_json, investments_json) "
                "VALUES (1, ?, '[]')",
                (json.dumps(DEFAULT_SETTINGS, ensure_ascii=False),),
            )

    async def get_state(self) -> dict[str, Any]:
        await self.ensure_state()
        state_row = await self.db.fetch_one(
            "SELECT settings_json, investments_json FROM finance_state WHERE id=1"
        )
        assert state_row is not None
        transactions = await self.db.fetch_all(
            "SELECT id, type, value, category, date, note "
            "FROM finance_transactions ORDER BY date DESC, created_at DESC"
        )
        return {
            "settings": json.loads(state_row["settings_json"]),
            "investments": json.loads(state_row["investments_json"]),
            "transactions": transactions,
        }

    async def update_state(self, payload: FinanceStateUpdate) -> dict[str, Any]:
        await self.ensure_state()
        investments = []
        for investment in payload.investments:
            item = investment.model_dump()
            if not item.get("id"):
                item["id"] = uuid.uuid4().hex
            investments.append(item)
        await self.db.execute(
            "UPDATE finance_state SET settings_json=?, investments_json=?, "
            "updated_at=datetime('now') WHERE id=1",
            (
                json.dumps(payload.settings.model_dump(), ensure_ascii=False),
                json.dumps(investments, ensure_ascii=False),
            ),
        )
        return await self.get_state()

    async def add_transaction(self, payload: TransactionCreate) -> dict[str, Any]:
        transaction = {
            "id": uuid.uuid4().hex,
            "type": payload.type,
            "value": round(float(payload.value), 2),
            "category": payload.category,
            "date": payload.date or date.today().isoformat(),
            "note": payload.note,
        }
        await self.db.execute(
            "INSERT INTO finance_transactions(id, type, value, category, date, note) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                transaction["id"],
                transaction["type"],
                transaction["value"],
                transaction["category"],
                transaction["date"],
                transaction["note"],
            ),
        )
        return transaction

    async def delete_transaction(self, transaction_id: str) -> bool:
        await self.db.execute(
            "DELETE FROM finance_transactions WHERE id=?", (transaction_id,)
        )
        row = await self.db.fetch_one("SELECT changes() AS count")
        return bool(row and row["count"])

    async def reset(self) -> dict[str, Any]:
        await self.ensure_state()
        await self.db.execute("DELETE FROM finance_transactions")
        await self.db.execute(
            "UPDATE finance_state SET settings_json=?, investments_json='[]', "
            "updated_at=datetime('now') WHERE id=1",
            (json.dumps(DEFAULT_SETTINGS, ensure_ascii=False),),
        )
        return await self.get_state()

    async def summary(
        self, month: str | None = None, all_time: bool = False
    ) -> dict[str, Any]:
        where = ""
        params: tuple[Any, ...] = ()
        period = "todos"
        if not all_time:
            selected = month or date.today().strftime("%Y-%m")
            try:
                datetime.strptime(selected, "%Y-%m")
            except ValueError as error:
                raise ValueError("o mês deve estar no formato AAAA-MM") from error
            where = " WHERE date LIKE ?"
            params = (f"{selected}-%",)
            period = selected

        totals_rows = await self.db.fetch_all(
            "SELECT type, COALESCE(SUM(value), 0) AS total, COUNT(*) AS count "
            f"FROM finance_transactions{where} GROUP BY type",
            params,
        )
        totals = {row["type"]: float(row["total"]) for row in totals_rows}
        count = sum(int(row["count"]) for row in totals_rows)

        categories = await self.db.fetch_all(
            "SELECT category, COALESCE(SUM(value), 0) AS total "
            f"FROM finance_transactions{where} "
            f"{'AND' if where else 'WHERE'} type='saida' "
            "GROUP BY category ORDER BY total DESC",
            params,
        )

        return {
            "period": period,
            "entradas": totals.get("entrada", 0.0),
            "saidas": totals.get("saida", 0.0),
            "investimentos": totals.get("investimento", 0.0),
            "saldo": totals.get("entrada", 0.0)
            - totals.get("saida", 0.0)
            - totals.get("investimento", 0.0),
            "por_categoria": [
                {"category": row["category"], "total": float(row["total"])}
                for row in categories
            ],
            "count": count,
        }


def format_summary(summary: dict[str, Any]) -> str:
    period = summary["period"]
    if period == "todos":
        heading = "Resumo de todos os lançamentos"
    else:
        heading = f"Resumo de {month_label(period)}"
    if not summary["count"]:
        return f"{heading}: nenhum lançamento registrado."
    parts = [
        f"{heading}:",
        f"entradas {brl(summary['entradas'])};",
        f"saídas {brl(summary['saidas'])};",
        f"investimentos {brl(summary['investimentos'])};",
        f"saldo {brl(summary['saldo'])}.",
    ]
    text = " ".join(parts)
    if summary["por_categoria"]:
        categories = "; ".join(
            f"{item['category']} {brl(item['total'])}"
            for item in summary["por_categoria"]
        )
        text += f" Saídas por categoria: {categories}."
    return text
