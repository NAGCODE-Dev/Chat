"""Leitura de recursos do sistema para decisões de alocação de modelos.

A política é conservadora: só usa um modelo maior quando há memória livre
suficiente e o swap não está sob pressão. O objetivo é evitar que o modelo
dispute RAM com o restante do desktop.
"""

from __future__ import annotations

from pathlib import Path

_MEMINFO = Path("/proc/meminfo")
_PRESSURE = Path("/proc/pressure/memory")


def _read_kb(field: str) -> int | None:
    try:
        for line in _MEMINFO.read_text(encoding="ascii").splitlines():
            if line.startswith(f"{field}:"):
                return int(line.split()[1])
    except (OSError, ValueError):
        return None
    return None


def memory_available_mb() -> int | None:
    """Memória disponível para novos processos, em MiB."""
    value = _read_kb("MemAvailable")
    return value // 1024 if value is not None else None


def swap_free_mb() -> int | None:
    """Swap livre, em MiB."""
    value = _read_kb("SwapFree")
    return value // 1024 if value is not None else None


def memory_pressure_full_avg10() -> float | None:
    """Média de 10 s do PSI de memória no estado ``full`` (0–100).

    ``None`` quando o kernel não expõe ``/proc/pressure/memory``.
    """
    try:
        for line in _PRESSURE.read_text(encoding="ascii").splitlines():
            if line.startswith("full "):
                for item in line.split()[1:]:
                    if item.startswith("avg10="):
                        return float(item.split("=", 1)[1])
    except (OSError, ValueError):
        return None
    return None
