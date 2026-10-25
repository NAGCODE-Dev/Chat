"""Adaptador STT para o executável oficial whisper.cpp."""

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

from chat.voice.base import STTEngine, VoiceError


class WhisperCppSTT(STTEngine):
    def __init__(
        self,
        model_path: str | Path,
        binary: str = "whisper-cli",
        language: str = "pt",
        threads: int = 4,
        timeout: float = 180.0,
    ) -> None:
        self.model_path = Path(model_path).expanduser()
        self.binary = binary
        self.language = language
        self.threads = max(1, threads)
        self.timeout = timeout
        self._process: asyncio.subprocess.Process | None = None

    async def transcribe(self, audio: bytes, sample_rate: int) -> str:
        if sample_rate != 16_000:
            raise VoiceError("A transcrição exige áudio mono WAV a 16000 Hz.")
        if not audio:
            raise VoiceError("O áudio está vazio.")
        if not self.model_path.is_file():
            raise VoiceError(f"Modelo whisper.cpp não encontrado: {self.model_path}")

        process: asyncio.subprocess.Process | None = None
        try:
            with tempfile.TemporaryDirectory(prefix="chat-stt-") as directory:
                audio_path = Path(directory) / "input.wav"
                audio_path.write_bytes(audio)
                process = await asyncio.create_subprocess_exec(
                    self.binary,
                    "-m",
                    str(self.model_path),
                    "-f",
                    str(audio_path),
                    "-l",
                    self.language,
                    "-t",
                    str(self.threads),
                    "-nt",
                    "-np",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                self._process = process
                stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=self.timeout)
                if process.returncode != 0:
                    detail = stderr.decode(errors="replace")[-1000:].strip()
                    raise VoiceError(f"whisper.cpp falhou: {detail or process.returncode}")
                return stdout.decode(errors="replace").strip()
        except TimeoutError as error:
            if process and process.returncode is None:
                process.kill()
                await process.wait()
            raise VoiceError("A transcrição excedeu o tempo limite.") from error
        except asyncio.CancelledError:
            if process and process.returncode is None:
                process.terminate()
                await process.wait()
            raise
        except OSError as error:
            raise VoiceError(f"Não foi possível iniciar whisper.cpp: {error}") from error
        finally:
            self._process = None

    def interrupt(self) -> None:
        if self._process and self._process.returncode is None:
            self._process.terminate()
