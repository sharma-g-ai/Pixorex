-- =============================================================================
-- Pixorex V1: one-time setup of the database and its roles.
-- Run ONCE per PostgreSQL server as a superuser (e.g. postgres), BEFORE run_all.sql:
--   psql -h localhost -U postgres -f api/migrations/baseline/setup_roles_and_database.sql
--
-- DRAFT FOR ARCHITECT REVIEW (DB roles are A0, CONSTITUTION §5 BC-04).
-- No passwords here: they come from Vault (CONSTITUTION §2.10). For local
-- development set them afterwards, for example:
--   ALTER ROLE pixorex_owner  PASSWORD 'local-only';
--   ALTER ROLE pixorex_app    PASSWORD 'local-only';
--   ALTER ROLE pixorex_worker PASSWORD 'local-only';
-- =============================================================================

\set ON_ERROR_STOP on

-- Owns the tables; used only to run migrations (ARCHITECTURE §4.4).
SELECT 'CREATE ROLE pixorex_owner LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pixorex_owner') \gexec

-- The API. Cannot bypass row-level security.
SELECT 'CREATE ROLE pixorex_app LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pixorex_app') \gexec

-- Outbox worker and scheduled jobs. Cannot bypass row-level security.
SELECT 'CREATE ROLE pixorex_worker LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE'
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pixorex_worker') \gexec

SELECT 'CREATE DATABASE pixorex OWNER pixorex_owner ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'pixorex') \gexec
