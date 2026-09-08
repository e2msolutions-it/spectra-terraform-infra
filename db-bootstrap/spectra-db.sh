#!/usr/bin/env bash
# Spectra DB helper — designed for a THROWAWAY shell (CloudShell VPC env has no
# persistent storage and dies after ~15 min idle).
#
# Everything is derived at runtime, so there is nothing to export and nothing to
# upload each session:
#   * RDS endpoint          <- describe-db-instances
#   * master secret ARN     <- the instance's MasterUserSecret (manage_master_user_password)
#   * master password       <- Secrets Manager
#   * migration .sql files  <- S3
#
# ONE-TIME setup (from your Mac, once):
#   ./spectra-db.sh publish s3://<bucket>/spectra-db
#
# THEN, in any fresh CloudShell VPC environment (private subnet + ECS SG):
#   aws s3 cp s3://<bucket>/spectra-db/spectra-db.sh . && chmod +x spectra-db.sh
#   ./spectra-db.sh migrate           # apply pending migrations to both DBs
#   ./spectra-db.sh status            # what's applied where
#   ./spectra-db.sh psql spectra_stag # interactive shell
#   ./spectra-db.sh sql spectra_stag "SELECT count(*) FROM device;"
#
# Set S3_BASE below (or export S3_BASE) so the script knows where to fetch from.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
DB_INSTANCE="${DB_INSTANCE:-spectra-global-data-pg}"
S3_BASE="${S3_BASE:-}"                       # e.g. s3://my-bucket/spectra-db
DATABASES=("spectra_prod" "spectra_stag")

log() { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- prerequisites ----------
ensure_psql() {
  command -v psql >/dev/null && return
  log "installing postgresql client"
  sudo dnf install -y postgresql16 >/dev/null 2>&1 \
    || sudo dnf install -y postgresql15 >/dev/null 2>&1 \
    || die "could not install a psql client"
}

# ---------- discovery: no env vars, no copy-paste ----------
discover() {
  log "discovering RDS instance '$DB_INSTANCE' in $REGION"
  local json
  json="$(aws rds describe-db-instances --region "$REGION" \
            --db-instance-identifier "$DB_INSTANCE" \
            --query 'DBInstances[0].{ep:Endpoint.Address,secret:MasterUserSecret.SecretArn,user:MasterUsername,status:DBInstanceStatus}' \
            --output json)" || die "cannot describe $DB_INSTANCE (check credentials/region)"

  DB_HOST="$(printf '%s' "$json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["ep"])')"
  SECRET_ARN="$(printf '%s' "$json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["secret"] or "")')"
  ADMIN_USER="$(printf '%s' "$json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["user"])')"
  local status
  status="$(printf '%s' "$json" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')"

  [ -n "$DB_HOST" ]    || die "no endpoint found"
  [ -n "$SECRET_ARN" ] || die "instance has no MasterUserSecret (manage_master_user_password disabled?)"
  [ "$status" = "available" ] || log "WARNING: instance status is '$status'"

  log "endpoint  $DB_HOST"
  log "master    $ADMIN_USER"

  PGPASSWORD="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$REGION" \
                  --query SecretString --output text \
                | python3 -c 'import sys,json;print(json.load(sys.stdin)["password"])')" \
    || die "cannot read master secret (need secretsmanager:GetSecretValue)"
  export PGPASSWORD

  BASE="host=$DB_HOST port=5432 user=$ADMIN_USER sslmode=require"

  # Fail fast with a clear message rather than a psql timeout.
  timeout 5 bash -c "cat < /dev/null > /dev/tcp/$DB_HOST/5432" 2>/dev/null \
    || die "cannot reach $DB_HOST:5432 — is this shell in a PRIVATE SUBNET with the ECS security group?"
}

# ---------- migrations ----------
fetch_migrations() {
  MIG_DIR="${MIG_DIR:-$PWD/migrations}"
  if [ -d "$MIG_DIR" ] && ls "$MIG_DIR"/0*.sql >/dev/null 2>&1; then
    log "using local migrations in $MIG_DIR"
    return
  fi
  [ -n "$S3_BASE" ] || die "set S3_BASE (or MIG_DIR) so migrations can be fetched"
  log "fetching migrations from $S3_BASE/migrations"
  mkdir -p "$MIG_DIR"
  aws s3 sync "$S3_BASE/migrations" "$MIG_DIR" --region "$REGION" --only-show-errors \
    || die "s3 sync failed"
  ls "$MIG_DIR"/0*.sql >/dev/null 2>&1 || die "no 0*.sql files found in $MIG_DIR"
}

ledger() {
  psql "$BASE dbname=$1" -v ON_ERROR_STOP=1 -q -c "
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );"
}

cmd_migrate() {
  ensure_psql; discover; fetch_migrations
  for DB in "${DATABASES[@]}"; do
    echo; log "===== $DB ====="
    ledger "$DB"
    local applied=0
    for f in "$MIG_DIR"/0*.sql; do
      local base; base="$(basename "$f")"

      # Truncation guard: every Spectra migration starts with '--'. A mangled
      # upload is the single most common failure here.
      [ "$(head -c 2 "$f")" = "--" ] \
        || die "$base does not start with '--' — file is truncated/corrupted, re-publish it"

      if [ "$(psql "$BASE dbname=$DB" -tAc "SELECT 1 FROM schema_migrations WHERE filename='$base';")" = "1" ]; then
        printf '   - %s (already applied)\n' "$base"; continue
      fi
      printf '   + %s\n' "$base"
      psql "$BASE dbname=$DB" -v ON_ERROR_STOP=1 -q -f "$f"
      psql "$BASE dbname=$DB" -v ON_ERROR_STOP=1 -q \
        -c "INSERT INTO schema_migrations(filename) VALUES ('$base');"
      applied=$((applied+1))
    done

    # Grants + partitions are idempotent, so just always reconcile them.
    local role="${DB}_app"
    psql "$BASE dbname=$DB" -v ON_ERROR_STOP=1 -q \
      -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $role;" \
      -c "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO $role;" \
      -c "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO $role;"
    local created
    created="$(psql "$BASE dbname=$DB" -tAc "SELECT spectra_ensure_month_partitions(2);" 2>/dev/null || echo "n/a")"
    log "$DB: $applied migration(s) applied, grants reconciled, partitions created=$created"
  done
  echo; log "done"
}

cmd_status() {
  ensure_psql; discover
  for DB in "${DATABASES[@]}"; do
    echo; log "===== $DB ====="
    psql "$BASE dbname=$DB" -tAc \
      "SELECT filename||'   '||to_char(applied_at,'YYYY-MM-DD HH24:MI') FROM schema_migrations ORDER BY filename;" \
      2>/dev/null || echo "   (no schema_migrations table)"
    psql "$BASE dbname=$DB" -tAc \
      "SELECT '   tables: '||count(*) FROM pg_tables WHERE schemaname='public';"
  done
}

cmd_psql()  { ensure_psql; discover; psql "$BASE dbname=${1:?usage: psql <database>}"; }
cmd_sql()   { ensure_psql; discover; psql "$BASE dbname=${1:?usage: sql <database> \"<statement>\"}" -c "${2:?missing statement}"; }

# ---------- publish (run from your Mac) ----------
cmd_publish() {
  local dest="${1:?usage: publish s3://bucket/prefix}"
  local here; here="$(cd "$(dirname "$0")" && pwd)"
  local migs="$here/../../agent-api/db/migrations"
  [ -d "$migs" ] || die "cannot find migrations at $migs"
  log "publishing script + migrations to $dest"
  aws s3 cp "$here/spectra-db.sh" "$dest/spectra-db.sh" --region "$REGION"
  aws s3 sync "$migs" "$dest/migrations" --exclude '*' --include '0*.sql' --region "$REGION"
  echo
  log "in a fresh CloudShell VPC environment, run:"
  echo "  aws s3 cp $dest/spectra-db.sh . && chmod +x spectra-db.sh && S3_BASE=$dest ./spectra-db.sh migrate"
}

case "${1:-}" in
  migrate) shift; cmd_migrate "$@" ;;
  status)  shift; cmd_status  "$@" ;;
  psql)    shift; cmd_psql    "$@" ;;
  sql)     shift; cmd_sql     "$@" ;;
  publish) shift; cmd_publish "$@" ;;
  *) cat <<EOF
Spectra DB helper

  ./spectra-db.sh publish s3://bucket/prefix   (from your Mac, once per change)
  ./spectra-db.sh migrate                      apply pending migrations to both DBs
  ./spectra-db.sh status                       show what's applied
  ./spectra-db.sh psql <database>              interactive shell
  ./spectra-db.sh sql  <database> "<sql>"      one statement

Environment (all optional):
  AWS_REGION   default us-east-1
  DB_INSTANCE  default spectra-global-data-pg
  S3_BASE      where publish put things, e.g. s3://bucket/spectra-db
  MIG_DIR      use local .sql files instead of fetching from S3
EOF
     exit 1 ;;
esac
