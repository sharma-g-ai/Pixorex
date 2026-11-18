"""The AI proxy's call to OpenAI and how it checks the answer (no network)."""

import json
from typing import Any

import httpx
import pytest
from pydantic import SecretStr

from app.services import ai_proxy

CONFIG = ai_proxy.AiConfig(
    url="https://openai.test/v1", api_key=SecretStr("k"), model="gpt-test", timeout_s=5
)
PNG = b"\x89PNG\r\n\x1a\n" + b"x" * 20


def _client(content: str | None, status: int = 200, seen: list[Any] | None = None) -> Any:
    def answer(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(request)
        body = {"choices": [{"message": {"content": content}}]}
        return httpx.Response(status, json=body)

    return httpx.AsyncClient(transport=httpx.MockTransport(answer))


async def test_sends_the_photo_with_the_openai_key_and_model_and_reads_fields() -> None:
    seen: list[httpx.Request] = []
    content = (
        '```json\n{"fields": [{"label": "Serial number", "data_type": "text",'
        ' "description": "The unique serial number, printed after S/N."},'
        ' {"label": "Rated voltage", "data_type": "number"}]}\n```'
    )
    async with _client(content, seen=seen) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    assert fields == [
        {
            "label": "Serial number",
            "data_type": "text",
            "description": "The unique serial number, printed after S/N.",
        },
        {"label": "Rated voltage", "data_type": "number", "description": None},
    ]
    request = seen[0]
    assert str(request.url) == "https://openai.test/v1/chat/completions"
    assert request.headers["authorization"] == "Bearer k"
    sent = json.loads(request.content)
    parts = sent["messages"][1]["content"]
    assert parts[0]["text"] == 'Equipment type name: "Motor"'
    assert parts[1]["image_url"]["url"].startswith("data:image/png;base64,")
    assert parts[1]["image_url"]["detail"] == "high"
    assert sent["model"] == "gpt-test"
    assert sent["reasoning_effort"] == "low"
    assert "temperature" not in sent  # GPT-5.6 models reject it
    # The prompt asks for a description in general words, never the photo's own value.
    system = sent["messages"][0]["content"]
    assert "description" in system
    assert "Never copy a value from this photo" in system


async def test_suggested_descriptions_are_cleaned_up() -> None:
    long = "word " * 200
    content = json.dumps(
        {
            "fields": [
                {"label": "Model", "data_type": "text", "description": "  The model\n code.  "},
                {"label": "Notes", "data_type": "text", "description": long},
                {"label": "Plant", "data_type": "text", "description": "   "},
                {"label": "Weight", "data_type": "number", "description": 12},
            ]
        }
    )
    async with _client(content) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    by_label = {f["label"]: f["description"] for f in fields}
    assert by_label["Model"] == "The model code."  # one line, trimmed
    assert len(by_label["Notes"] or "") <= ai_proxy.MAX_DESCRIPTION  # cut to the column
    assert by_label["Plant"] is None  # blank means none
    assert by_label["Weight"] == "12"  # odd types become text, not an error


async def test_extraction_sends_every_photo_at_high_detail_without_temperature() -> None:
    seen: list[httpx.Request] = []
    content = '{"fields": {"serial": {"value": "SN-1", "confidence": 0.9}}}'
    field = {
        "field_key": "serial",
        "label": "Serial number",
        "data_type": "text",
        "options": None,
        "description": "The unique serial number, printed after S/N.",
    }
    async with _client(content, seen=seen) as http:
        result = await ai_proxy.extract(
            http,
            CONFIG,
            photos=[(PNG, "image/png"), (PNG, "image/png")],
            type_name="Motor",
            fields=[field],
            type_names=["Motor"],
            extra_instructions=None,
        )
    assert result.fields["serial"]["value"] == "SN-1"
    sent = json.loads(seen[0].content)
    images = [p for p in sent["messages"][1]["content"] if p["type"] == "image_url"]
    assert [p["image_url"]["detail"] for p in images] == ["high", "high"]
    assert (sent["model"], sent["reasoning_effort"]) == ("gpt-test", "low")
    assert "temperature" not in sent
    # Each field goes with its description, as data inside the field list; no format rule.
    text = sent["messages"][1]["content"][0]["text"]
    wanted = json.loads(text.split("Fields to extract: ", 1)[1].split("\n", 1)[0])
    assert wanted == [
        {
            "key": "serial",
            "label": "Serial number",
            "data_type": "text",
            "choices": None,
            "description": "The unique serial number, printed after S/N.",
        }
    ]
    assert "format_ok" not in sent["messages"][0]["content"]
    assert result.fields["serial"] == {"value": "SN-1", "confidence": 0.9}


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
        {"label": "Serial number", "data_type": "text", "description": None},
        {"label": "Made on", "data_type": "text", "description": None},
    ]


async def test_readings_are_never_suggested_as_field_labels() -> None:
    """GIVEN a plate whose uncaptioned values (3/60CYCLE, 3-PHASE, 230/460) came back as labels
    WHEN the answer is cleaned THEN only real captions are kept, and look-alikes survive."""
    labels = [
        "3/60CYCLE", "3x60 cycle", "3-PHASE", "3 PH", "3~Mot.", "230/460", "1.15", "%",
        "Phase", "Frequency (Hz)", "1S thermal current", "额定电压",
    ]  # fmt: skip
    content = json.dumps({"fields": [{"label": lbl, "data_type": "text"} for lbl in labels]})
    async with _client(content) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    assert [f["label"] for f in fields] == [
        "Phase", "Frequency (Hz)", "1S thermal current", "额定电压",
    ]  # fmt: skip


async def test_same_caption_spelt_differently_is_one_field_and_dropdown_becomes_text() -> None:
    """GIVEN 'Serial No.' and 'Serial no:' (same field key) and a dropdown with no choices
    WHEN cleaned THEN one Serial field is kept, without the colon, and the dropdown is text."""
    content = json.dumps(
        {
            "fields": [
                {"label": "Serial No.", "data_type": "text"},
                {"label": " Serial  no: ", "data_type": "text"},
                {"label": "Duty:", "data_type": "dropdown"},
            ]
        }
    )
    async with _client(content) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    assert fields == [
        {"label": "Serial No.", "data_type": "text", "description": None},
        {"label": "Duty", "data_type": "text", "description": None},
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


async def test_discovery_never_suggests_yes_no_or_dropdown_fields() -> None:
    """GIVEN the AI proposes a boolean and a dropdown
    WHEN cleaned THEN both are text, and the prompt only offers text, number and date."""
    content = json.dumps(
        {
            "fields": [
                {"label": "Explosion-proof rating", "data_type": "boolean"},
                {"label": "Fan guard", "data_type": "Boolean"},
                {"label": "Duty", "data_type": "dropdown"},
                {"label": "Power (kW)", "data_type": "number"},
                {"label": "Made on", "data_type": "date"},
            ]
        }
    )
    async with _client(content) as http:
        fields = await ai_proxy.suggest_fields(
            http, CONFIG, type_name="Motor", image=PNG, mime="image/png"
        )
    assert [(f["label"], f["data_type"]) for f in fields] == [
        ("Explosion-proof rating", "text"),
        ("Fan guard", "text"),
        ("Duty", "text"),
        ("Power (kW)", "number"),
        ("Made on", "date"),
    ]
    assert "- boolean:" not in ai_proxy.SUGGEST_PROMPT
    assert "never boolean" in ai_proxy.SUGGEST_PROMPT
