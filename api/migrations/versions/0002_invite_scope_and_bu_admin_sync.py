"""Invite links without the owner role; business_unit.bu_admin_user_id kept in sync.

DRAFT FOR ARCHITECT REVIEW. Privileged functions are A0 (CONSTITUTION §5, BC-04).

1. invite_scope(token_hash): the invite preview and accept endpoints (contracts 1.6, 1.7)
   carry no sign-in, so RLS shows them nothing. This function returns only the tenant and
   units of that link's invite, plus the same person's other pending invites (accept takes
   them all, D-09). The API then limits its transaction to exactly those units and runs
   every query as pixorex_app under RLS. Knowing the 256-bit token is the permission.
2. sync_unit_bu_admin(): business_unit.bu_admin_user_id mirrors the active bu_admin row of
   user_unit_role. A trigger keeps them equal on every path (invite accept, edit units,
   removal), since only the EA may update business_unit directly (09_rls.sql).

Revision ID: 0002
Revises: 0001
"""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None

SQL = """
CREATE FUNCTION invite_scope(p_token_hash text)
RETURNS TABLE (tenant_id uuid, bu_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH link AS (
    SELECT i.tenant_id, lower(i.email) AS email, i.role
      FROM invite i
     WHERE i.token_hash = p_token_hash
     LIMIT 1
  )
  SELECT DISTINCT i.tenant_id, i.bu_id
    FROM invite i
    JOIN link l ON i.tenant_id = l.tenant_id AND lower(i.email) = l.email AND i.role = l.role
   WHERE i.token_hash = p_token_hash OR i.status = 'pending'
$$;
REVOKE ALL ON FUNCTION invite_scope(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION invite_scope(text) TO pixorex_app;

CREATE FUNCTION sync_unit_bu_admin() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.role <> 'bu_admin' OR NEW.bu_id IS NULL THEN
    RETURN NULL;
  END IF;
  IF NEW.removed_at IS NULL THEN
    UPDATE business_unit SET bu_admin_user_id = NEW.user_id
     WHERE tenant_id = NEW.tenant_id AND id = NEW.bu_id;
  ELSE
    UPDATE business_unit SET bu_admin_user_id = NULL
     WHERE tenant_id = NEW.tenant_id AND id = NEW.bu_id AND bu_admin_user_id = NEW.user_id;
  END IF;
  RETURN NULL;
END
$$;
REVOKE ALL ON FUNCTION sync_unit_bu_admin() FROM PUBLIC;

CREATE TRIGGER trg_user_unit_role_sync_bu_admin
  AFTER INSERT OR UPDATE OF removed_at ON user_unit_role
  FOR EACH ROW EXECUTE FUNCTION sync_unit_bu_admin();
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)


def downgrade() -> None:
    raise NotImplementedError("Forward-only.")
