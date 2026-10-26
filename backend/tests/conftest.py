from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from chat.api.main import app


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("CHAT_DATA_DIR", str(tmp_path))
    monkeypatch.setenv("CHAT_PROVIDER", "fake")
    monkeypatch.setenv("CHAT_MODEL", "fake-model")
    with TestClient(app) as test_client:
        yield test_client
