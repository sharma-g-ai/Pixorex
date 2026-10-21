"""The AI proxy's call to Portkey and how it checks the answer (no network)."""

import json
from typing import Any

import httpx
import pytest
from pydantic import SecretStr

from app.services import ai_proxy

CONFIG = ai_proxy.AiConfig(
    url="https://portkey.test/v1", api_key=SecretStr("k"), config_id="pc-test", timeout_s=5
)
PNG = b"\x89PNG\r\n\x1a\n" + b"x" * 20


def _client(content: str | None, status: int = 200, seen: list[Any] | None = None) -> Any:
    def answer(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        body = {"choices": [{"message": {"content": content}}]}
        return httpx.Response(status, json=body)

    return httpx.AsyncClient(transport=httpx.MockTransport(answer))


async def test_sends_the_photo_with_the_portkey_headers_and_reads_fields() -> None:
    seen: list[httpx.Request] = []
    content = (
        '```json\n{"fields": [{"label": "Serial number", "data_type": "text"},'
        ' {"label": "Rated voltage", "data_type": "number"}]}\n```'
    )
    async with _client(content, seen=seen) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    assert fields == [
        {"label": "Serial number", "data_type": "text"},
        {"label": "Rated voltage", "data_type": "number"},
    ]
    request = seen[0]
    assert str(request.url) == "https://portkey.test/v1/chat/completions"
    assert request.headers["x-portkey-api-key"] == "k"
    assert request.headers["x-portkey-config"] == "pc-test"
    sent = json.loads(request.content)
    parts = sent["messages"][1]["content"]
    assert parts[0]["text"] == 'Equipment type name: "Motor"'
    assert parts[1]["image_url"]["url"].startswith("data:image/png;base64,")
    assert "model" not in sent  # the Portkey config picks it


async def test_odd_answers_are_cleaned_up() -> None:
    content = json.dumps(
        {
            "fields": [
                {"label": " Serial number ", "data_type": "TEXT"},
                {"label": "serial NUMBER", "data_type": "text"},  # duplicate
                {"label": "Made on", "data_type": "datetime"},  # unknown type -> text
                {"label": "", "data_type": "text"},  # no label
                "not a field",
            ]
        }
    )
    async with _client(content) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Pump", image=PNG, mime="image/png"
        )
    assert fields == [
        {"label": "Serial number", "data_type": "text"},
        {"label": "Made on", "data_type": "text"},
    ]


@pytest.mark.parametrize(("content", "status"), [("no json here", 200), (None, 200), ("{}", 500)])
async def test_unusable_answers_raise(content: str | None, status: int) -> None:
    async with _client(content, status) as http:
        with pytest.raises(ai_proxy.AiUnavailableError):
            await ai_proxy.suggest_fields(
                http, CONFIG, type_name="Pump", image=PNG, mime="image/png"
            )


async def test_an_unreachable_provider_raises() -> None:
    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    async with httpx.AsyncClient(transport=httpx.MockTransport(fail)) as http:
        with pytest.raises(ai_proxy.AiUnavailableError):
            await ai_proxy.suggest_fields(
                http, CONFIG, type_name="Pump", image=PNG, mime="image/png"
            )
