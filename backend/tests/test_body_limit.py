from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

from chat.api.body_limit import RequestBodyLimitMiddleware


def make_client():
    app = FastAPI()
    app.add_middleware(
        RequestBodyLimitMiddleware,
        max_bytes=8,
        detail="payload too large",
    )

    @app.post("/echo")
    async def echo(request: Request):
        return {"size": len(await request.body())}

    return TestClient(app)


def test_body_limit_rejects_content_length_and_chunked_bodies():
    with make_client() as client:
        declared = client.post("/echo", content=b"x" * 9)
        chunked = client.post("/echo", content=iter([b"1234", b"56789"]))
        exact_limit = client.post("/echo", content=b"12345678")

    assert declared.status_code == 413
    assert chunked.status_code == 413
    assert exact_limit.json() == {"size": 8}
