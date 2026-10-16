"""Operator command bootstrap_tenant.py (SPEC-PX-04 REQ-04.05) against PostgreSQL."""

import uuid
from typing import Any

import psycopg
import pytest

from scripts import bootstrap_tenant
from tests.integration.conftest import Api
from tests.integration.helpers import make_token


@pytest.fixture
def owner(database: dict[str, str]) -> Any:
    with psycopg.connect(database["owner"]) as conn:
        yield conn


def test_creates_company_admin_retention_and_audit_once(owner: Any, owner_sql: Any) -> None:
    name = f"Acme {uuid.uuid4().hex[:6]}"
    first = bootstrap_tenant.create_company(
        owner, name=name, package="standard", email="jane@example.com", full_name="Jane Doe"
    )
    assert first.created
    counts = owner_sql(
        "SELECT (SELECT count(*) FROM app_user WHERE tenant_id = %(t)s AND status = 'invited'),"
        " (SELECT count(*) FROM user_unit_role WHERE tenant_id = %(t)s"
        "  AND role = 'enterprise_admin' AND bu_id IS NULL AND is_primary),"
        " (SELECT count(*) FROM retention_config WHERE tenant_id = %(t)s AND bu_id IS NULL),"
        " (SELECT count(*) FROM audit_log WHERE tenant_id = %(t)s AND actor_type = 'system')",
        {"t": first.tenant_id},
    )
    assert counts[0] == (1, 1, len(bootstrap_tenant.RETENTION_DEFAULTS), 1)

    again = bootstrap_tenant.create_company(
        owner, name=name.upper(), package="standard", email="other@example.com", full_name="X"
    )
    assert not again.created  # REQ-04.05: an existing company: no changes
    assert (again.tenant_id, again.user_id, again.email) == (
        first.tenant_id,
        first.user_id,
        "jane@example.com",
    )
    assert (
        owner_sql("SELECT count(*) FROM tenant WHERE lower(name) = lower(%s)", (name,))[0][0] == 1
    )


def test_the_new_admin_signs_in_to_an_empty_company(owner: Any, api: Api) -> None:
    admin = bootstrap_tenant.create_company(
        owner,
        name=f"Beta {uuid.uuid4().hex[:6]}",
        package="standard",
        email="lee@example.com",
        full_name="Lee Admin",
    )
    token = make_token(str(admin.user_id), tenant_id=str(admin.tenant_id))
    me = api.get("/me", token=token).json()
    assert (me["status"], me["units"][0]["role"]) == ("active", "enterprise_admin")
    assert api.get("/business-units", token=token).json()["items"] == []  # sees no other company


def test_bad_input_is_refused_before_anything_is_written() -> None:
    with pytest.raises(SystemExit, match="valid email"):
        bootstrap_tenant.main(["--name", "X", "--ea-email", "not-an-email", "--ea-name", "Y"])
    with pytest.raises(SystemExit, match="must not be empty"):
        bootstrap_tenant.main(["--name", " ", "--ea-email", "a@example.com", "--ea-name", "Y"])
