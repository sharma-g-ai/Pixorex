from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

from fastapi import HTTPException
from psycopg import Connection

from app.db import connection, set_rls
from app.deps import CurrentUser
from app.services import me as me_service


@contextmanager
def rls_connection(
    user: CurrentUser,
    *,
    require_ea: bool = False,
    require_admin: bool = False,
) -> Iterator[Connection]:
    """Open a connection, set RLS, and commit on clean exit (no generator-close rollback)."""
    with connection() as conn:
        with conn.transaction():
            set_rls(
                conn,
                tenant_id=str(user.tenant_id),
                user_id=str(user.app_user_id),
                bu_ids=[],
                is_ea=False,
            )
            roles = me_service.load_unit_roles(conn, user.app_user_id)
            bu_ids = [str(r["bu_id"]) for r in roles if r.get("bu_id")]
            is_ea = any(r["role"] == "enterprise_admin" for r in roles)
            is_bu = any(r["role"] == "bu_admin" for r in roles)
            if require_ea and not is_ea:
                raise HTTPException(status_code=403, detail={"title": "Forbidden"})
            if require_admin and not is_ea and not is_bu:
                raise HTTPException(status_code=403, detail={"title": "Forbidden"})
            set_rls(
                conn,
                tenant_id=str(user.tenant_id),
                user_id=str(user.app_user_id),
                bu_ids=bu_ids,
                is_ea=is_ea,
            )
            yield conn
