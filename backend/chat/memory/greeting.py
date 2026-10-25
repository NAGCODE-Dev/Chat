"""Saudação curta e variada baseada no que a memória já sabe."""

from __future__ import annotations

import random
from typing import Any

_GREETINGS: dict[str, list[str]] = {
    "empty": [
        "Ainda estou te conhecendo. Se quiser, me conte suas preferências e eu começo a lembrar.",
        "Nosso histórico está só começando. O que você gostaria que eu soubesse sobre você?",
        "Primeira conversa por aqui. Pode falar do seu jeito; eu vou aprendendo.",
        "Ainda não tenho memórias suas. Me conta uma coisa que você gosta e eu guardo.",
    ],
    "few": [
        "Já guardei {n} detalhe sobre você. Quer continuar de onde paramos?",
        "Tenho {n} memória sua e estou pronto para ajudar. Por onde começamos?",
        "Lembro de {n} coisa sobre você. O que vamos resolver agora?",
        "Comecei a te conhecer: {n} detalhe(s) na memória. Como posso ajudar?",
    ],
    "some": [
        "Conheço {n} detalhes sobre você, de preferências a projetos. O que vamos resolver hoje?",
        "Já são {n} memórias suas. Posso puxar preferências, projetos e rotina quando precisar.",
        "Tenho {n} anotações sobre você. Quer retomar algo ou começar do zero?",
        "Meu mapa sobre você já tem {n} pontos. Em que posso ser útil?",
    ],
    "many": [
        "Tenho {n} memórias suas. Já dá para dizer que não somos estranhos. O que você precisa?",
        "São {n} detalhes guardados sobre você. Posso ser bem mais específico agora.",
        "Conheço {n} coisas sobre a sua vida e seus projetos. Por onde seguimos?",
        "Com {n} memórias suas, já consigo acompanhar seu contexto. O que fazemos hoje?",
    ],
}


def _bucket(total: int) -> str:
    if total <= 0:
        return "empty"
    if total < 5:
        return "few"
    if total < 15:
        return "some"
    return "many"


def build_greeting(stats: dict[str, Any], rng: random.Random | None = None) -> dict[str, Any]:
    """Monta uma frase diferente a cada chamada, sem depender do modelo."""
    total = int(stats.get("total") or 0)
    generator = rng or random.SystemRandom()
    text = generator.choice(_GREETINGS[_bucket(total)]).format(n=total)
    latest = stats.get("latest")
    if total >= 5 and isinstance(latest, dict):
        detail = str(latest.get("content") or "").strip()
        if detail:
            if len(detail) > 90:
                detail = detail[:87].rstrip() + "…"
            if generator.random() < 0.55:
                text += f' A última coisa que anotei foi: “{detail}”.'
    return {
        "greeting": text,
        "memory_count": total,
        "kinds": stats.get("kinds") or {},
    }
