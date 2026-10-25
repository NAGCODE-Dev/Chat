"""Testes do app Meu Dinheiro: armazenamento, API e ferramentas."""

from __future__ import annotations

from datetime import date
from pathlib import Path

import pytest

from chat.agent_orchestration.chat_service import ChatService
from chat.core.config import Settings
from chat.finance.store import (
    FinanceStateUpdate,
    FinanceStore,
    TransactionCreate,
    normalize_month,
)
from chat.memory.db import Database
from chat.providers.fake_provider import FakeProvider
from chat.tools.finance import FinanceAdd, FinanceSummary


async def test_store_add_summary_delete_and_reset(tmp_path: Path):
    db = Database(str(tmp_path / "finance.db"))
    await db.connect()
    try:
        store = FinanceStore(db)
        income = await store.add_transaction(
            TransactionCreate(
                type="entrada",
                value=1000,
                category="salario",
                date="2026-10-01",
                note="pagamento",
            )
        )
        expense = await store.add_transaction(
            TransactionCreate(
                type="saida",
                value=50,
                category="mercado",
                date="2026-10-02",
            )
        )

        assert income["category"] == "Salário"
        assert expense["category"] == "Comida"

        summary = await store.summary(month="2026-10")
        assert summary["entradas"] == 1000
        assert summary["saidas"] == 50
        assert summary["saldo"] == 950
        assert summary["por_categoria"] == [{"category": "Comida", "total": 50.0}]

        assert await store.delete_transaction(expense["id"]) is True
        assert await store.delete_transaction(expense["id"]) is False
        state = await store.get_state()
        assert len(state["transactions"]) == 1

        await store.reset()
        state = await store.get_state()
        assert state["transactions"] == []
        assert state["settings"]["monthlyIncome"] == 1000
    finally:
        await db.close()


async def test_store_updates_income_and_investments(tmp_path: Path):
    db = Database(str(tmp_path / "finance.db"))
    await db.connect()
    try:
        store = FinanceStore(db)
        state = await store.get_state()
        assert state["investments"] == []

        updated = await store.update_state(
            FinanceStateUpdate.model_validate(
                {
                    "settings": {
                        "monthlyIncome": 2500,
                        "month": "2026-10",
                        "cdiRate": 15,
                        "budget": {
                            "necessidades": 30,
                            "comida": 20,
                            "patrimonio": 25,
                            "objetivos": 15,
                            "lazer": 10,
                        },
                    },
                    "investments": [
                        {
                            "name": "Tesouro Selic",
                            "amount": 1000,
                            "type": "cdi",
                            "cdiPercent": 100,
                        }
                    ],
                }
            )
        )
        assert updated["settings"]["monthlyIncome"] == 2500
        assert updated["investments"][0]["name"] == "Tesouro Selic"
        assert updated["investments"][0]["id"]
    finally:
        await db.close()


async def test_finance_tools(tmp_path: Path):
    db = Database(str(tmp_path / "finance.db"))
    await db.connect()
    try:
        add = FinanceAdd(db)
        arguments = add.validate_arguments(
            {
                "type": "saida",
                "value": 9.9,
                "category": "lazer",
                "date": "24/10/2026",
                "note": "cinema",
            }
        )
        result = await add.run(arguments)
        assert result.success is True
        assert "R$ 9,90" in result.content
        assert "Lazer" in result.content

        summary = FinanceSummary(db)
        result = await summary.run(
            summary.validate_arguments({"month": "2026-10"})
        )
        assert result.success is True
        assert "saídas R$ 9,90" in result.content
        assert "Lazer R$ 9,90" in result.content
    finally:
        await db.close()


def test_normalize_month_formats():
    assert normalize_month("2026-10") == "2026-10"
    assert normalize_month("2026/10") == "2026-10"
    assert normalize_month("10/2026") == "2026-10"
    assert normalize_month("24/10/2026") == "2026-10"
    assert normalize_month("2026-10-24") == "2026-10"
    assert normalize_month("outubro de 2026") == "2026-10"
    assert normalize_month("Out", today=date(2026, 10, 24)) == "2026-10"
    assert normalize_month("outubro", today=date(2025, 3, 1)) == "2025-10"
    assert normalize_month("este mês", today=date(2026, 10, 24)) == "2026-10"
    assert normalize_month("mês passado", today=date(2026, 1, 15)) == "2025-12"
    assert normalize_month(None) is None
    with pytest.raises(ValueError):
        normalize_month("banana")


async def test_finance_summary_tolerates_model_arguments(tmp_path: Path):
    db = Database(str(tmp_path / "finance.db"))
    await db.connect()
    try:
        store = FinanceStore(db)
        await store.add_transaction(
            TransactionCreate(type="saida", value=7.5, category="lazer")
        )

        summary = FinanceSummary(db)
        arguments = summary.validate_arguments({"all_time": "this_month"})
        assert arguments["period"] == "mes_atual"
        result = await summary.run(arguments)
        assert result.success is True
        assert "R$ 7,50" in result.content

        arguments = summary.validate_arguments(
            {"month": "este mês", "all_time": "todos"}
        )
        assert arguments["month"] == date.today().strftime("%Y-%m")
        assert arguments["period"] == "todos"
        result = await summary.run(arguments)
        assert result.success is True
        assert "todos os lançamentos" not in result.content

        arguments = summary.validate_arguments({"all_time": "todos"})
        assert arguments["period"] == "todos"
        result = await summary.run(arguments)
        assert result.success is True
        assert "todos os lançamentos" in result.content

        arguments = summary.validate_arguments({"period": "mês passado"})
        assert arguments["period"] == "mes_passado"
        result = await summary.run(arguments)
        assert result.success is True
        assert "nenhum lançamento" in result.content
        assert "all_time" not in summary.parameters["properties"]

        arguments = summary.validate_arguments(
            {"month": date.today().strftime("%Y-%m"), "period": "todos"}
        )
        result = await summary.run(arguments)
        assert result.success is True
        assert "todos os lançamentos" not in result.content
        assert "R$ 7,50" in result.content
    finally:
        await db.close()


def test_finance_intent_does_not_steal_launches_or_general_questions():
    service = ChatService(
        Settings(provider="fake", model="fake-model"), None, FakeProvider()
    )  # type: ignore[arg-type]
    assert service._finance_summary_arguments("Quanto eu gastei este mês?") == {
        "period": "mes_atual"
    }
    assert service._finance_summary_arguments("Qual meu saldo?") == {
        "period": "mes_atual"
    }
    assert service._finance_summary_arguments("Quanto gastei no mês passado?") == {
        "period": "mes_passado"
    }
    assert service._finance_summary_arguments("Quanto gastei em outubro de 2025?") == {
        "month": "2025-10"
    }
    assert service._finance_summary_arguments("gastei 50 no mercado") is None
    assert service._finance_summary_arguments("registre um gasto de 30 no almoço") is None
    assert service._finance_summary_arguments("o que é orçamento?") is None
    assert service._finance_summary_arguments("Quanto gastei hoje?") is None


async def test_finance_summary_stream_is_deterministic(tmp_path: Path):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        store = FinanceStore(db)
        month = date.today().strftime("%Y-%m")
        await store.add_transaction(
            TransactionCreate(
                type="entrada",
                value=1000,
                category="salario",
                date=f"{month}-01",
            )
        )
        await store.add_transaction(
            TransactionCreate(
                type="saida",
                value=50,
                category="mercado",
                date=f"{month}-02",
            )
        )
        service = ChatService(
            Settings(provider="fake", model="fake-model"),
            db,
            FakeProvider(),
        )
        events = [
            event
            async for event in service.stream_user_message(
                "Quanto eu gastei este mês?"
            )
        ]
        done = events[-1]
        assert done["type"] == "done"
        assert done["model"] == "finance_summary"
        assert "R$ 50,00" in done["content"]
        assert "R$ 1.000,00" in done["content"]
        assert "**" in done["content"]
        assert "http" not in done["content"]
    finally:
        await db.close()


async def test_finance_summary_stream_without_launches(tmp_path: Path):
    db = Database(str(tmp_path / "chat.db"))
    await db.connect()
    try:
        service = ChatService(
            Settings(provider="fake", model="fake-model"),
            db,
            FakeProvider(),
        )
        events = [
            event
            async for event in service.stream_user_message(
                "Quanto eu gastei este mês?"
            )
        ]
        done = events[-1]
        assert done["model"] == "finance_summary"
        assert "Ainda não há lançamentos" in done["content"]
    finally:
        await db.close()


def test_finance_api(client):
    response = client.get("/api/finance/state")
    assert response.status_code == 200
    body = response.json()
    assert body["transactions"] == []
    assert body["settings"]["monthlyIncome"] == 1000

    response = client.post(
        "/api/finance/transactions",
        json={
            "type": "saida",
            "value": 12.34,
            "category": "comida",
            "date": "2026-10-24",
            "note": "almoço",
        },
    )
    assert response.status_code == 201
    transaction = response.json()
    assert transaction["category"] == "Comida"
    assert transaction["value"] == 12.34

    response = client.get("/api/finance/summary?month=2026-10")
    assert response.status_code == 200
    summary = response.json()
    assert summary["saidas"] == 12.34
    assert summary["por_categoria"] == [{"category": "Comida", "total": 12.34}]
    assert "almoço" not in summary["text"]

    response = client.delete(f"/api/finance/transactions/{transaction['id']}")
    assert response.status_code == 200
    assert response.json() == {"deleted": True}

    response = client.post("/api/finance/reset")
    assert response.status_code == 200
    assert response.json()["transactions"] == []


def test_finance_state_api(client):
    response = client.put(
        "/api/finance/state",
        json={
            "settings": {
                "monthlyIncome": 2500,
                "month": "2026-10",
                "cdiRate": 15,
                "budget": {
                    "necessidades": 30,
                    "comida": 20,
                    "patrimonio": 25,
                    "objetivos": 15,
                    "lazer": 10,
                },
            },
            "investments": [
                {
                    "name": "Tesouro Selic",
                    "amount": 1000,
                    "type": "cdi",
                    "cdiPercent": 100,
                }
            ],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["settings"]["monthlyIncome"] == 2500
    assert body["investments"][0]["id"]

    response = client.get("/finance/")
    assert response.status_code == 200
    assert "Meu Dinheiro" in response.text
    response = client.get("/finance/app.js")
    assert response.status_code == 200
    assert "/api/finance" in response.text
