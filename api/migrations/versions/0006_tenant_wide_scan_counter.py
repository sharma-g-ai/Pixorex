"""The next scan ID counts over the whole tenant, not only the unit the caller is working in.

DRAFT FOR ARCHITECT REVIEW. Privileged functions are A0 (CONSTITUTION §5, BC-04).

Scan IDs are one 9-digit counter per tenant (scan.tenant_id + record_no is unique), but the
API read the last number with max() through RLS, which shows only the active unit. A unit
with no scans (or fewer than another unit) therefore got a number that already existed, and
creating the scan failed with a 500.

last_record_counter(tenant) returns the highest counter in the tenant, whatever unit it is in,
and only for the caller's own tenant (app_tenant_id). It returns one number and no row data.
No new table or column.

Revision ID: 0006
Revises: 0005
"""

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None

SQL = """
CREATE FUNCTION last_record_counter(p_tenant_id uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT max(left(record_no, 9)::bigint)
    FROM scan
   WHERE tenant_id = p_tenant_id
     AND p_tenant_id = app_tenant_id()
     AND record_no ~ '^[0-9]{10}$'
$$;
REVOKE ALL ON FUNCTION last_record_counter(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION last_record_counter(uuid) TO pixorex_app;
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)


def downgrade() -> None:
    raise NotImplementedError("Forward-only.")
