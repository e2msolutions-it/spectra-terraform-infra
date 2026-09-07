#!/usr/bin/env bash
# Spectra logical DB bootstrap — run ONCE, from inside the VPC (the RDS instance
# is private). Creates per-env roles + databases (IAM auth), enables pgcrypto,
# grants the app role DML privileges, and (unless skipped) applies the schema
# migrations as the master (the schema owner).
#
# Idempotent: safe to re-run.
#
# Privilege model: databases are owned by the MASTER; migrations run as the
# master; the app role (LOGIN + rds_iam) gets DML only (SELECT/INSERT/UPDATE/
# DELETE) via default privileges — it cannot create or drop tables. The app role
# is never granted to the master (that would disable the master's password).
#
# Required env vars:
#   DB_HOST    RDS endpoint address        (global-data output: db_address)
#   SECRET_ID  master secret ARN           (global-data output: db_master_secret_arn)
# Optional:
#   AWS_REGION       default us-east-1
#   MIG_DIR          default ../../agent-api/db/migrations (relative to this script)
#   SKIP_MIGRATIONS  set to 1 to create roles + databases + grants only (defer schema to Phase 1)
#
# Needs: aws cli, psql, python3, and network access to DB_HOST:5432.

set -euo pipefail

DB_HOST="${DB_HOST:?set DB_HOST to the RDS endpoint (global-data output db_address)}"
SECRET_ID="${SECRET_ID:?set SECRET_ID to the master secret ARN (global-data output db_master_secret_arn)}"
REGION="${AWS_REGION:-us-east-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MIG_DIR="${MIG_DIR:-$(cd "$HERE/../../agent-api/db/migrations" && pwd)}"

echo ">> Fetching master credentials from Secrets Manager"
SECRET_JSON="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
ADMIN_USER="$(printf '%s' "$SECRET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["username"])')"
export PGPASSWORD="$(printf '%s' "$SECRET_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')"

CONN="host=$DB_HOST port=5432 user=$ADMIN_USER sslmode=require"

echo ">> Creating roles + databases (01_bootstrap.sql)"
psql "$CONN dbname=postgres" -v ON_ERROR_STOP=1 -f "$HERE/01_bootstrap.sql"

for pair in "spectra_prod:spectra_prod_app" "spectra_stag:spectra_stag_app"; do
  DB="${pair%%:*}"; ROLE="${pair##*:}"

  echo ">> [$DB] pgcrypto + schema usage + default DML privileges for $ROLE"
  psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 \
    -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" \
    -c "GRANT USAGE ON SCHEMA public TO $ROLE;" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $ROLE;" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO $ROLE;" \
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO $ROLE;"

  if [ "${SKIP_MIGRATIONS:-0}" = "1" ]; then
    echo ">> [$DB] SKIP_MIGRATIONS=1 - roles + database + grants done, schema deferred to Phase 1"
  else
    echo ">> [$DB] applying migrations as master ($ADMIN_USER)"

    # Migration ledger: each file is applied at most once and recorded, so a
    # failure part-way through is resumable (re-run and it picks up where it
    # stopped) instead of blowing up on "relation already exists".
    psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 -q -c "
      CREATE TABLE IF NOT EXISTS schema_migrations (
        filename   TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );"

    for f in "$MIG_DIR"/0*.sql; do
      base="$(basename "$f")"

      # Integrity guard: every Spectra migration starts with a "--" comment.
      # If it doesn't, the file was truncated/mangled in transit - stop rather
      # than feeding a broken file to psql.
      if [ "$(head -c 2 "$f")" != "--" ]; then
        echo "!! $base does not start with '--' - file looks truncated or corrupted."
        echo "!! Re-upload it (binary-safe) and compare sha256 before re-running."
        exit 1
      fi

      if [ "$(psql "$CONN dbname=$DB" -tAc "SELECT 1 FROM schema_migrations WHERE filename='$base';")" = "1" ]; then
        echo "   - $base (already applied, skipping)"
        continue
      fi

      echo "   + $base"
      psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 -q -f "$f"
      psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 -q \
        -c "INSERT INTO schema_migrations(filename) VALUES ('$base');"
    done

    echo ">> [$DB] granting DML + function EXECUTE on the objects just created to $ROLE"
    # EXECUTE covers the SECURITY DEFINER partition helpers (0005). The app role
    # stays DML-only: it can CALL them (they run as the master) but still cannot
    # create or drop tables itself.
    psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 \
      -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $ROLE;" \
      -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $ROLE;" \
      -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO $ROLE;"

    echo ">> [$DB] creating initial monthly partitions"
    psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 \
      -c "SELECT spectra_ensure_month_partitions(2);"
  fi
done

echo ">> Bootstrap complete: spectra_prod + spectra_stag ready (app role = IAM auth, DML only)."
