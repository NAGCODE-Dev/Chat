"""Endpoints para transcrição e síntese de voz local."""

from __future__ import annotations

import io
import wave

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field

from chat.api.state import state
from chat.voice.base import VoiceError

router = APIRouter(prefix="/api/voice", tags=["voice"])
MAX_AUDIO_BYTES = 25 * 1024 * 1024


class SynthesizeRequest(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


@router.get("/status")
async def voice_status() -> dict[str, bool]:
    return {
        "stt_available": state.stt_engine is not None,
        "tts_available": state.tts_engine is not None,
    }


@router.post("/transcribe")
async def transcribe(request: Request) -> dict[str, str]:
    engine = state.stt_engine
    if engine is None:
        raise HTTPException(status_code=503, detail="STT não configurado no backend")
    audio = await request.body()
    if not audio:
        raise HTTPException(status_code=400, detail="Áudio vazio")
    if len(audio) > MAX_AUDIO_BYTES:
        raise HTTPException(status_code=413, detail="Áudio excede o limite de 25 MiB")
    try:
        with wave.open(io.BytesIO(audio), "rb") as wav:
            if wav.getcomptype() != "NONE" or wav.getnchannels() != 1 or wav.getsampwidth() != 2:
                raise HTTPException(
                    status_code=422,
                    detail="Envie um WAV PCM mono de 16 bits.",
                )
            sample_rate = wav.getframerate()
            if sample_rate != 16_000:
                raise HTTPException(
                    status_code=422,
                    detail="O áudio deve estar em 16000 Hz.",
                )
    except (wave.Error, EOFError) as error:
        raise HTTPException(status_code=422, detail="Arquivo WAV inválido") from error
    try:
        return {"text": await engine.transcribe(audio, sample_rate)}
    except VoiceError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@router.post("/synthesize")
async def synthesize(request: SynthesizeRequest) -> Response:
    engine = state.tts_engine
    if engine is None:
        raise HTTPException(status_code=503, detail="TTS não configurado no backend")
    try:
        audio = await engine.synthesize(request.text)
    except VoiceError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
    return Response(content=audio, media_type="audio/wav")
