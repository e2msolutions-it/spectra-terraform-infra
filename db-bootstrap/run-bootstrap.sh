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
    -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO $ROLE;"

  if [ "${SKIP_MIGRATIONS:-0}" = "1" ]; then
    echo ">> [$DB] SKIP_MIGRATIONS=1 - roles + database + grants done, schema deferred to Phase 1"
  else
    echo ">> [$DB] applying migrations as master ($ADMIN_USER)"
    FILES=(); for f in "$MIG_DIR"/0*.sql; do FILES+=(-f "$f"); done
    psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 "${FILES[@]}"

    echo ">> [$DB] granting DML on the objects just created to $ROLE"
    psql "$CONN dbname=$DB" -v ON_ERROR_STOP=1 \
      -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $ROLE;" \
      -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $ROLE;"
  fi
done

echo ">> Bootstrap complete: spectra_prod + spectra_stag ready (app role = IAM auth, DML only)."
