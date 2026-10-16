#!/bin/sh
# Local Compose only: runs once on an empty postgres volume (docker-entrypoint-initdb.d).
# Creates the roles and the pixorex database, then gives the roles LOCAL-ONLY passwords.
# Deployed environments get passwords from Vault (PX-10-T03).
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -f /baseline/setup_roles_and_database.sql
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -c "
  ALTER ROLE pixorex_owner  PASSWORD 'local-only';
  ALTER ROLE pixorex_app    PASSWORD 'local-only';
  ALTER ROLE pixorex_worker PASSWORD 'local-only';"
