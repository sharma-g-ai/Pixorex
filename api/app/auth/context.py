"""Request context (BC-01, BC-04): who is calling, and one database transaction under RLS.

A0, HUMAN-WRITTEN LOGIC. Ported from Iswarya's api/app/deps.py and api/app/db_ctx.py
(branch feature/PX-01-T08-invite-signin-api): token -> app_user -> roles -> SET LOCAL.
Added in the port: X-Device-Id is required, a signed-out device's old tokens are refused,
removed users are refused, and invite links get a context limited to their own units.
Needs architect review before use beyond local development (CONSTITUTION §5).
"""

from collections.abc import AsyncIterator, Iterable
from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth.tokens import unauthorized, verify_access_token
from app.core.db import Conn
from app.core.problems import ProblemError

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class UnitRole:
    bu_id: UUID | None  # None for enterprise_admin
    role: str


@dataclass(frozen=True)
class Caller:
    user_id: UUID
    tenant_id: UUID
    device_id: str
    roles: tuple[UnitRole, ...]

    @property
    def is_ea(self) -> bool:
        return any(r.role == "enterprise_admin" for r in self.roles)

    def units(self, role: str) -> frozenset[UUID]:
        return frozenset(r.bu_id for r in self.roles if r.role == role and r.bu_id)

    @property
    def bu_ids(self) -> frozenset[UUID]:
        return frozenset(r.bu_id for r in self.roles if r.bu_id)

    def require_ea(self) -> None:
        if not self.is_ea:
            raise ProblemError(403, "forbidden")

    def require_admin(self) -> None:
        if not self.is_ea and not self.units("bu_admin"):
            raise ProblemError(403, "forbidden")


@dataclass(frozen=True)
class Session:
    """What a signed-in endpoint gets: the caller and their transaction."""

    caller: Caller
    conn: Conn


async def set_context(
    conn: Conn,
    *,
    tenant_id: UUID,
    user_id: UUID | None = None,
    bu_ids: Iterable[UUID] = (),
    is_ea: bool = False,
) -> None:
    """SET LOCAL the values RLS reads (09_rls.sql). They end with the transaction."""
    await conn.execute(
        "SELECT set_config('app.tenant_id', %s, true), set_config('app.user_id', %s, true),"
        " set_config('app.bu_ids', %s, true), set_config('app.is_ea', %s, true)",
        (
            str(tenant_id),
            str(user_id) if user_id else "",
            ",".join(str(b) for b in bu_ids),
            "true" if is_ea else "false",
        ),
    )


def _device_id(x_device_id: str | None) -> str:
    device = (x_device_id or "").strip()
    if not device or len(device) > 128:
        raise ProblemError(400, "bad-request", "The X-Device-Id header is required.")
    return device


async def signed_in(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    x_device_id: Annotated[str | None, Header()] = None,
) -> AsyncIterator[Session]:
    device_id = _device_id(x_device_id)
    if credentials is None:
        raise unauthorized()
    state = request.app.state
    claims = await verify_access_token(credentials.credentials, state.settings, state.jwks)

    async with state.pool.connection() as conn, conn.transaction():
        # Tenant and user first: enough to read this user's own rows.
        await set_context(conn, tenant_id=claims.tenant_id, user_id=claims.user_id)
        user = await (
            await conn.execute("SELECT status FROM app_user WHERE id = %s", (claims.user_id,))
        ).fetchone()
        if user is None:
            raise unauthorized()
        if user["status"] == "removed":
            raise ProblemError(403, "account-removed", "This account was removed.")
        # Sign-out (contract 1.3) revokes this device's session: older tokens stop working.
        revoked = await (
            await conn.execute(
                "SELECT max(revoked_at) AS at FROM user_session"
                " WHERE user_id = %s AND device_id = %s",
                (claims.user_id, device_id),
            )
        ).fetchone()
        if revoked and revoked["at"] and revoked["at"] >= claims.issued_at:
            raise unauthorized()
        rows = await (
            await conn.execute(
                "SELECT bu_id, role FROM user_unit_role WHERE user_id = %s AND removed_at IS NULL",
                (claims.user_id,),
            )
        ).fetchall()
        caller = Caller(
            user_id=claims.user_id,
            tenant_id=claims.tenant_id,
            device_id=device_id,
            roles=tuple(UnitRole(bu_id=r["bu_id"], role=r["role"]) for r in rows),
        )
        await set_context(
            conn,
            tenant_id=caller.tenant_id,
            user_id=caller.user_id,
            bu_ids=caller.bu_ids,
            is_ea=caller.is_ea,
        )
        yield Session(caller=caller, conn=conn)


async def public(request: Request) -> AsyncIterator[Conn]:
    """A transaction with no tenant context: RLS shows nothing until a scope is set."""
    async with request.app.state.pool.connection() as conn, conn.transaction():
        yield conn


async def scope_to_invite(conn: Conn, token_hash: str) -> bool:
    """Invite links (contracts 1.6, 1.7) carry no sign-in. invite_scope() (migration 0002,
    A0 draft) returns only the tenant and units of that link's invite and of the same
    person's other pending invites; the transaction is limited to them. False: no such link.
    """
    rows = await (
        await conn.execute("SELECT tenant_id, bu_id FROM invite_scope(%s)", (token_hash,))
    ).fetchall()
    if not rows:
        return False
    await set_context(conn, tenant_id=rows[0]["tenant_id"], bu_ids=[r["bu_id"] for r in rows])
    return True


# scope="function": the transaction commits before the response is sent, so a client that
# reloads right after a 201 sees the change, and background tasks (emails) run only after
# a successful commit.
SignedIn = Annotated[Session, Depends(signed_in, scope="function")]
Public = Annotated[Conn, Depends(public, scope="function")]
