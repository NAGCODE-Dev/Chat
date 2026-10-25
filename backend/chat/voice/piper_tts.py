"""Adaptador TTS para o pacote local Piper (`python -m piper`)."""

from __future__ import annotations

import asyncio
import sys
import tempfile
import wave
from pathlib import Path

from chat.voice.base import TTSEngine, VoiceError


class PiperTTS(TTSEngine):
    def __init__(self, model_path: str | Path, timeout: float = 180.0) -> None:
        self.model_path = Path(model_path).expanduser()
        self.timeout = timeout
        self._process: asyncio.subprocess.Process | None = None

    async def synthesize(self, text: str) -> bytes:
        text = text.strip()
        if not text:
            raise VoiceError("O texto para síntese está vazio.")
        if len(text) > 4000:
            raise VoiceError("O texto excede o limite de 4000 caracteres.")
        if not self.model_path.is_file():
            raise VoiceError(f"Modelo Piper não encontrado: {self.model_path}")

        process: asyncio.subprocess.Process | None = None
        try:
            with tempfile.TemporaryDirectory(prefix="chat-tts-") as directory:
                wav_path = Path(directory) / "speech.wav"
                process = await asyncio.create_subprocess_exec(
                    sys.executable,
                    "-m",
                    "piper",
                    "--model",
                    str(self.model_path),
                    "--output_file",
                    str(wav_path),
                    "--",
                    text,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                self._process = process
                _, stderr = await asyncio.wait_for(process.communicate(), timeout=self.timeout)
                if process.returncode != 0:
                    detail = stderr.decode(errors="replace")[-1000:].strip()
                    raise VoiceError(f"Piper falhou: {detail or process.returncode}")
                if not wav_path.is_file():
                    raise VoiceError("Piper terminou sem produzir o arquivo WAV.")
                audio = wav_path.read_bytes()
                _validate_wav(audio)
                return audio
        except TimeoutError as error:
            if process and process.returncode is None:
                process.kill()
                await process.wait()
            raise VoiceError("A síntese excedeu o tempo limite.") from error
        except asyncio.CancelledError:
            if process and process.returncode is None:
                process.terminate()
                await process.wait()
            raise
        except OSError as error:
            raise VoiceError(f"Não foi possível iniciar Piper: {error}") from error
        finally:
            self._process = None

    def stop(self) -> None:
        if self._process and self._process.returncode is None:
            self._process.terminate()


def _validate_wav(audio: bytes) -> None:
    import io

    try:
        with wave.open(io.BytesIO(audio), "rb") as wav:
            if wav.getnframes() <= 0 or wav.getframerate() <= 0:
                raise VoiceError("O WAV sintetizado não contém áudio válido.")
    except (wave.Error, EOFError) as error:
        raise VoiceError("Piper produziu um arquivo WAV inválido.") from error
