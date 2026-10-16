"""Cursor paging (contracts/common.yaml: Cursor, Limit, PageInfo). Cursors are opaque to clients."""

import base64
import json
from typing import Annotated, Any

from fastapi import Query
from pydantic import BaseModel

from app.core.problems import ProblemError

Limit = Annotated[int, Query(ge=1, le=100)]
Cursor = Annotated[str | None, Query()]


class PageInfo(BaseModel):
    next_cursor: str | None


def encode_cursor(*values: Any) -> str:
    return base64.urlsafe_b64encode(json.dumps([str(v) for v in values]).encode()).decode()


def decode_cursor(cursor: str | None, size: int) -> list[str] | None:
    if cursor is None:
        return None
    try:
        values = json.loads(base64.urlsafe_b64decode(cursor.encode()))
    except ValueError:
        values = None
    if not isinstance(values, list) or len(values) != size:
        raise ProblemError(400, "bad-request", "The cursor is not valid.")
    return [str(v) for v in values]
