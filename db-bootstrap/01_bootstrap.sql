-- Spectra logical DB bootstrap — run as the RDS master (admin), connected to the
-- default `postgres` database. Idempotent: safe to re-run.
--
-- Model: databases are owned by the MASTER. The per-env app role is LOGIN +
-- rds_iam (IAM-token auth) and gets DML privileges only (see run-bootstrap.sh).
--
-- IMPORTANT (RDS behaviour): a role that is a member of `rds_iam` can ONLY
-- authenticate with IAM tokens — its password login is disabled. So we must
-- NEVER grant an app role (which carries rds_iam) to the master, or the master
-- itself loses password auth. Hence: master owns the databases; the app role is
-- granted privileges, not the other way around.

\set ON_ERROR_STOP on

-- ---- Roles: LOGIN + rds_iam (IAM token auth, no password) ----
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'spectra_prod_app') THEN
    CREATE ROLE spectra_prod_app WITH LOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'spectra_stag_app') THEN
    CREATE ROLE spectra_stag_app WITH LOGIN;
  END IF;
END
$$;

GRANT rds_iam TO spectra_prod_app;
GRANT rds_iam TO spectra_stag_app;

-- NOTE: we deliberately never grant an app role to the master. An app role is a
-- member of rds_iam, and granting it to the master would make the master a
-- transitive rds_iam member — which disables the master's password login on RDS.
-- The master owns the databases and runs migrations directly; the app role gets
-- privileges (see run-bootstrap.sh), never the reverse.

-- ---- Databases owned by the master (no OWNER clause). \gexec runs CREATE
--      DATABASE outside a transaction and makes it idempotent. ----
SELECT 'CREATE DATABASE spectra_prod'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'spectra_prod')\gexec

SELECT 'CREATE DATABASE spectra_stag'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'spectra_stag')\gexec

REVOKE ALL ON DATABASE spectra_prod FROM PUBLIC;
REVOKE ALL ON DATABASE spectra_stag FROM PUBLIC;
GRANT CONNECT ON DATABASE spectra_prod TO spectra_prod_app;
GRANT CONNECT ON DATABASE spectra_stag TO spectra_stag_app;
