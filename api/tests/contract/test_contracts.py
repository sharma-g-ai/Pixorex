"""Every built endpoint matches contracts/*.yaml: path, method, success code, query and header
parameters, request body fields and response fields (top level and list items)."""

from pathlib import Path
from typing import Any

import pytest
import yaml

from app.main import create_app
from tests.conftest import make_settings

CONTRACTS = Path(__file__).resolve().parents[3] / "contracts"
DOCS = {f.name: yaml.safe_load(f.read_text(encoding="utf-8")) for f in CONTRACTS.glob("*.yaml")}
OURS = create_app(make_settings()).openapi()
CONTRACT_OPS = {
    op["operationId"]: (name, path, method, op)
    for name, doc in DOCS.items()
    for path, ops in doc.get("paths", {}).items()
    for method, op in ops.items()
    if isinstance(op, dict) and "operationId" in op
}
OUR_OPS = [(path, method, op) for path, ops in OURS["paths"].items() for method, op in ops.items()]


def _contract(node: Any, doc: str) -> tuple[dict[str, Any], str]:
    while isinstance(node, dict) and "$ref" in node:
        file, _, pointer = node["$ref"].partition("#")
        doc = file.split("/")[-1] if file else doc
        node = DOCS[doc]
        for part in pointer.strip("/").split("/"):
            node = node[part]
    if isinstance(node, dict) and "allOf" in node:  # merge the parts into one object
        merged: dict[str, Any] = {"properties": {}, "required": []}
        for part in node["allOf"]:
            resolved, _ = _contract(part, doc)
            merged["properties"].update(resolved.get("properties", {}))
            merged["required"] += resolved.get("required", [])
        node = merged
    return node, doc


def _ours(node: Any) -> dict[str, Any]:
    while isinstance(node, dict) and "$ref" in node:
        target: Any = OURS
        for part in node["$ref"].lstrip("#/").split("/"):
            target = target[part]
        node = target
    if "anyOf" in node:  # Optional[...] from pydantic
        node = next(_ours(x) for x in node["anyOf"] if _ours(x).get("type") != "null")
    return node


def _fields(schema: dict[str, Any]) -> tuple[set[str], set[str]]:
    return set(schema.get("properties", {})), set(schema.get("required", []))


def _camel(path: str) -> str:
    """Our snake_case path params vs the contract's camelCase: {invite_id} -> {inviteId}."""
    parts = path.split("{")
    out = [parts[0]]
    for part in parts[1:]:
        name, _, rest = part.partition("}")
        head, *tail = name.split("_")
        out.append("{" + head + "".join(t.title() for t in tail) + "}" + rest)
    return "".join(out)


@pytest.mark.parametrize(
    ("path", "method", "op"), OUR_OPS, ids=[o[2]["operationId"] for o in OUR_OPS]
)
def test_endpoint_matches_contract(path: str, method: str, op: dict[str, Any]) -> None:
    name, c_path, c_method, c_op = CONTRACT_OPS[op["operationId"]]
    assert (_camel(path.removeprefix("/api/v1")), method) == (c_path, c_method)

    c_codes = sorted(k for k in c_op["responses"] if k.startswith("2"))
    assert sorted(k for k in op["responses"] if k.startswith("2")) == c_codes

    c_params = {
        _contract(p, name)[0]["name"].lower()
        for p in c_op.get("parameters", [])
        if _contract(p, name)[0]["in"] in ("query", "header")
    }
    o_params = {
        p["name"].lower() for p in op.get("parameters", []) if p["in"] in ("query", "header")
    }
    assert c_params - o_params == set(), "missing parameters"
    assert o_params - c_params - {"x-device-id"} == set(), "extra parameters"

    c_body = c_op.get("requestBody", {}).get("content", {}).get("application/json")
    if c_body:
        o_body = op["requestBody"]["content"]["application/json"]
        assert _fields(_ours(o_body["schema"])) == _fields(_contract(c_body["schema"], name)[0])

    c_res = c_op["responses"][c_codes[0]].get("content", {}).get("application/json")
    if not c_res:
        return
    c_schema, c_doc = _contract(c_res["schema"], name)
    o_schema = _ours(op["responses"][c_codes[0]]["content"]["application/json"]["schema"])
    (c_props, c_req), (o_props, o_req) = _fields(c_schema), _fields(o_schema)
    assert o_props == c_props, "response fields"
    assert c_req <= o_req, "fields required by the contract are optional here"
    if "items" in c_props and c_schema["properties"]["items"].get("type") == "array":
        c_item = _contract(c_schema["properties"]["items"]["items"], c_doc)[0]
        o_item = _ours(o_schema["properties"]["items"]["items"])
        assert _fields(o_item)[0] == _fields(c_item)[0], "list item fields"
        assert _fields(c_item)[1] <= _fields(o_item)[1], "list item required fields"
