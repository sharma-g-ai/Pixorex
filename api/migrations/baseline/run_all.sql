-- Runs the whole baseline in order. First run setup_roles_and_database.sql once
-- as a superuser, then run this as the owner role on the empty pixorex database:
--   psql -h localhost -U pixorex_owner -d pixorex -f api/migrations/baseline/run_all.sql
\set ON_ERROR_STOP on
\ir 00_foundation.sql
\ir 01_domain1_tenancy.sql
\ir 02_domain2_locations.sql
\ir 03_domain3_equipment_types.sql
\ir 04_domain4_scans.sql
\ir 05_domain5_review.sql
\ir 06_domain6_audit_ops.sql
\ir 07_triggers.sql
\ir 08_roles_grants.sql
\ir 09_rls.sql
