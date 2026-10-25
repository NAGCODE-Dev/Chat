"""Contrato e validação de argumentos para ferramentas do agente."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, ClassVar

from pydantic import BaseModel, ConfigDict, ValidationError


class Permission(StrEnum):
    SAFE = "safe"
    CONFIRM = "confirm"
    RESTRICTED = "restricted"


class ToolArguments(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


@dataclass
class ToolResult:
    content: str
    success: bool = True
    sources: list[dict[str, str]] = field(default_factory=list)
    # Dados estruturados opcionais para a orquestração montar respostas
    # determinísticas (por exemplo, notícias com veículo e data).
    data: list[dict[str, str]] | None = None


class ToolError(Exception):
    """Falha controlada na validação ou execução de uma ferramenta."""


class Tool(ABC):
    name: ClassVar[str]
    description: ClassVar[str]
    permission: ClassVar[Permission]
    arguments_model: ClassVar[type[ToolArguments]]

    @property
    def parameters(self) -> dict[str, Any]:
        return self.arguments_model.model_json_schema()

    def validate_arguments(self, arguments: dict[str, Any]) -> dict[str, Any]:
        try:
            return self.arguments_model.model_validate(arguments).model_dump(exclude_none=True)
        except ValidationError as error:
            details = "; ".join(
                f"{'.'.join(str(part) for part in item['loc'])}: {item['msg']}"
                for item in error.errors()
            )
            raise ToolError(f"Argumentos inválidos para {self.name}: {details}") from error

    @abstractmethod
    async def run(self, arguments: dict[str, Any]) -> ToolResult:
        """Executa argumentos já validados."""
