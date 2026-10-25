"""Testa o contrato e as rotas de voz sem baixar modelos locais grandes."""

from __future__ import annotations

import io
import wave

from chat.api.state import state
from chat.voice.base import STTEngine, TTSEngine


def _wav_bytes() -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16_000)
        wav.writeframes(b"\x00\x00" * 160)
    return buffer.getvalue()


class _FakeSTT(STTEngine):
    async def transcribe(self, audio: bytes, sample_rate: int) -> str:
        assert sample_rate == 16_000
        assert audio.startswith(b"RIFF")
        return "texto de teste"

    def interrupt(self) -> None:
        return None


class _FakeTTS(TTSEngine):
    async def synthesize(self, text: str) -> bytes:
        assert text == "Olá"
        return _wav_bytes()

    def stop(self) -> None:
        return None


def test_voice_status_and_unconfigured_engines(client):
    state.stt_engine = None
    state.tts_engine = None
    status = client.get("/api/voice/status")
    assert status.json() == {"stt_available": False, "tts_available": False}
    assert client.post("/api/voice/synthesize", json={"text": "Olá"}).status_code == 503


def test_voice_endpoints_validate_and_process_wav(client):
    state.stt_engine = _FakeSTT()
    state.tts_engine = _FakeTTS()

    transcribed = client.post(
        "/api/voice/transcribe", content=_wav_bytes(), headers={"content-type": "audio/wav"}
    )
    assert transcribed.status_code == 200
    assert transcribed.json() == {"text": "texto de teste"}

    invalid = client.post(
        "/api/voice/transcribe", content=b"not a wav", headers={"content-type": "audio/wav"}
    )
    assert invalid.status_code == 422

    synthesized = client.post("/api/voice/synthesize", json={"text": "Olá"})
    assert synthesized.status_code == 200
    assert synthesized.headers["content-type"] == "audio/wav"
    assert synthesized.content.startswith(b"RIFF")
