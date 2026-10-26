"""Rotas de anexos: upload binário, listagem, leitura e remoção."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse

from chat.api.state import state
from chat.memory.attachments import (
    MAX_ATTACHMENT_BYTES,
    AttachmentStore,
    guess_mime,
)

router = APIRouter(prefix="/api/attachments", tags=["attachments"])


def _store() -> AttachmentStore:
    if state.settings is None or state.db is None:
        raise HTTPException(status_code=503, detail="Serviço não inicializado.")
    return AttachmentStore(state.db, state.settings.resolved_attachments_path)


@router.post("", status_code=201)
async def upload_attachment(
    request: Request,
    filename: str = Query(min_length=1, max_length=200),
    mime: str | None = Query(default=None, max_length=120),
) -> dict:
    data = await request.body()
    if not data:
        raise HTTPException(status_code=422, detail="O arquivo está vazio.")
    if len(data) > MAX_ATTACHMENT_BYTES:
        raise HTTPException(status_code=413, detail="O arquivo excede o limite de 20 MiB.")
    try:
        metadata = await _store().create(filename, mime or guess_mime(filename), data)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    return {"attachment": metadata}


@router.get("")
async def list_attachments() -> dict:
    return {"attachments": await _store().list()}


@router.get("/{attachment_id}")
async def get_attachment(attachment_id: int) -> dict:
    metadata = await _store().get(attachment_id, include_text=True)
    if metadata is None:
        raise HTTPException(status_code=404, detail="Anexo não encontrado.")
    return {"attachment": metadata}


@router.get("/{attachment_id}/content")
async def attachment_content(attachment_id: int) -> FileResponse:
    resolved = await _store().content_path(attachment_id)
    if resolved is None:
        raise HTTPException(status_code=404, detail="Anexo não encontrado.")
    row, path = resolved
    if not path.is_file():
        raise HTTPException(status_code=410, detail="Arquivo do anexo não está disponível.")
    return FileResponse(
        path,
        media_type=row["mime"],
        filename=row["filename"],
        content_disposition_type="inline" if row["kind"] == "image" else "attachment",
    )


@router.delete("/{attachment_id}")
async def delete_attachment(attachment_id: int) -> dict:
    if not await _store().delete(attachment_id):
        raise HTTPException(status_code=404, detail="Anexo não encontrado.")
    return {"deleted": attachment_id}
