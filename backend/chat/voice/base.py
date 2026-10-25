"""Contratos independentes dos mecanismos de reconhecimento e síntese."""

from __future__ import annotations

from abc import ABC, abstractmethod


class STTEngine(ABC):
    @abstractmethod
    async def transcribe(self, audio: bytes, sample_rate: int) -> str:
        """Converte áudio PCM/WAV para texto."""

    @abstractmethod
    def interrupt(self) -> None:
        """Interrompe a transcrição em andamento, se houver."""


class TTSEngine(ABC):
    @abstractmethod
    async def synthesize(self, text: str) -> bytes:
        """Gera um arquivo WAV a partir de texto."""

    @abstractmethod
    def stop(self) -> None:
        """Interrompe a síntese em andamento, se houver."""


class VoiceError(Exception):
    """Erro normalizado de um mecanismo de voz."""
