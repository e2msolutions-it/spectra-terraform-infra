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
ORG_NAME="${ORG_NAME:-E2M Tech}"          # the single tenant; override to seed another

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
  [ -f "$here/allowlist-template.csv" ] && \
    aws s3 cp "$here/allowlist-template.csv" "$dest/allowlist-template.csv" --region "$REGION"
  echo
  log "in a fresh CloudShell VPC environment, run:"
  echo "  aws s3 cp $dest/spectra-db.sh . && chmod +x spectra-db.sh && S3_BASE=$dest ./spectra-db.sh migrate"
}

# ---------- seeding (org / enrollment secret / device allowlist) ----------
# These three are what turn an empty schema into something an agent can enrol
# against. All idempotent, all safe to re-run.

org_id_for() {
  # $1 = database, $2 = org name. Creates the row if missing, echoes the UUID.
  local db="$1" org="$2"
  psql "$BASE dbname=$db" -v ON_ERROR_STOP=1 -q \
    -c "INSERT INTO organization (name)
        SELECT \$\$${org}\$\$
        WHERE NOT EXISTS (SELECT 1 FROM organization WHERE name = \$\$${org}\$\$);" >/dev/null
  psql "$BASE dbname=$db" -tAc "SELECT id FROM organization WHERE name = \$\$${org}\$\$;"
}

cmd_seed() {
  local db="${1:?usage: seed <database> [\"Org Name\"]}"
  local org="${2:-$ORG_NAME}"
  ensure_psql; discover
  local id; id="$(org_id_for "$db" "$org")"
  [ -n "$id" ] || die "could not create/find organization '$org'"
  log "$db: organization '$org' = $id"
  psql "$BASE dbname=$db" -tAc \
    "SELECT '   employees: '||(SELECT count(*) FROM employee WHERE org_id='$id')
          ||'   allowlist: '||(SELECT count(*) FROM device_allowlist WHERE org_id='$id')
          ||'   devices: '||(SELECT count(*) FROM device WHERE org_id='$id')
          ||'   active enrollments: '||(SELECT count(*) FROM agent_enrollment
                                         WHERE org_id='$id' AND revoked_at IS NULL AND expires_at > now());"
}

cmd_enroll_secret() {
  local db="${1:?usage: enroll-secret <database> [secrets-manager-arn]}"
  local arn="${2:-}"
  local org="${ORG_NAME}"
  ensure_psql; discover
  local id; id="$(org_id_for "$db" "$org")"
  [ -n "$id" ] || die "no organization '$org' in $db - run 'seed $db' first"

  # 64 hex chars: no base64 padding or slashes to escape in the MSI config,
  # 256 bits of entropy. The DB only ever sees the sha256 of this.
  local secret hash
  secret="$(openssl rand -hex 32)"
  hash="$(printf '%s' "$secret" | sha256sum | cut -d' ' -f1)"

  # Rotation is a revoke + insert, NOT a delete: already-enrolled devices
  # authenticate with their own keypair, so they are unaffected. Only new
  # installs need the new MSI.
  psql "$BASE dbname=$db" -v ON_ERROR_STOP=1 -q -c "
    BEGIN;
    UPDATE agent_enrollment SET revoked_at = now()
     WHERE org_id = '$id' AND kind = 'shared' AND revoked_at IS NULL;
    INSERT INTO agent_enrollment (org_id, token_hash, expires_at, kind, max_uses, label)
    VALUES ('$id', '$hash', now() + interval '10 years', 'shared', NULL,
            'fleet secret issued $(date -u +%Y-%m-%dT%H:%MZ)');
    COMMIT;"
  log "$db: registered new fleet enrollment secret (previous shared secrets revoked)"

  if [ -n "$arn" ]; then
    aws secretsmanager put-secret-value --region "$REGION" --secret-id "$arn" \
      --secret-string "{\"enrollment_secret\":\"$secret\"}" \
      --query 'VersionId' --output text >/dev/null \
      || die "could not write to $arn (need secretsmanager:PutSecretValue)"
    log "stored plaintext in Secrets Manager: $arn"
    log "retrieve later with:"
    echo "  aws secretsmanager get-secret-value --region $REGION --secret-id $arn --query SecretString --output text"
  else
    printf '\033[1;33m!!\033[0m no secret ARN given - the plaintext below is NOT stored anywhere.\n'
    printf '   Get the ARN from the app cell output: terraform output enrollment_secret_arn\n'
  fi

  echo
  printf '\033[1;32m>>\033[0m enrollment secret (put this in the MSI config):\n\n    %s\n\n' "$secret"
  printf '   This is the last time it is printed. The database stores only its SHA-256.\n'
}

cmd_allowlist() {
  # CSV columns (header required, order free):
  #   hostname,email,full_name[,employee_code][,note]
  local db="${1:?usage: allowlist <database> <file.csv>}"
  local csv="${2:?usage: allowlist <database> <file.csv>}"
  [ -f "$csv" ] || die "no such file: $csv"
  ensure_psql; discover
  local id; id="$(org_id_for "$db" "$ORG_NAME")"
  [ -n "$id" ] || die "no organization '$ORG_NAME' in $db - run 'seed $db' first"

  log "building SQL from $csv"
  ORG_ID="$id" python3 - "$csv" > /tmp/spectra-allowlist.sql <<'PY'
import csv, os, sys

def lit(v):
    return "NULL" if v in (None, "") else "$sq$" + str(v) + "$sq$"

org = os.environ["ORG_ID"]
rows, bad = [], []
with open(sys.argv[1], newline="", encoding="utf-8-sig") as fh:
    rd = csv.DictReader(fh)
    if not rd.fieldnames:
        sys.exit("CSV has no header row")
    cols = {(c or "").strip().lower(): c for c in rd.fieldnames}
    need = {"hostname", "email", "full_name"}
    missing = need - set(cols)
    if missing:
        sys.exit("CSV is missing required column(s): " + ", ".join(sorted(missing)))
    for n, r in enumerate(rd, start=2):
        g = lambda k: (r.get(cols[k]) or "").strip() if k in cols else ""
        host, email, name = g("hostname").lower(), g("email").lower(), g("full_name")
        if not host or not email or not name:
            bad.append((n, "hostname, email and full_name are all required"))
            continue
        rows.append((host, email, name, g("employee_code"), g("note")))

if bad:
    for n, why in bad:
        print(f"-- SKIPPED line {n}: {why}", file=sys.stderr)
if not rows:
    sys.exit("no usable rows in CSV")

print("BEGIN;")
for host, email, name, code, note in rows:
    # employee: one row per person, keyed on (org_id, email). Re-running an
    # import refreshes the name/code rather than duplicating the person.
    print(f"""
INSERT INTO employee (org_id, email, full_name, employee_code)
VALUES ('{org}', {lit(email)}, {lit(name)}, {lit(code)})
ON CONFLICT (org_id, email) DO UPDATE
   SET full_name = EXCLUDED.full_name,
       employee_code = COALESCE(EXCLUDED.employee_code, employee.employee_code);

INSERT INTO device_allowlist (org_id, match_type, match_value, employee_id, note)
SELECT '{org}', 'hostname', {lit(host)}, e.id, {lit(note)}
  FROM employee e
 WHERE e.org_id = '{org}' AND e.email = {lit(email)}
ON CONFLICT (org_id, match_type, match_value) DO UPDATE
   SET employee_id = EXCLUDED.employee_id,
       note        = COALESCE(EXCLUDED.note, device_allowlist.note);""")
print("COMMIT;")
print(f"-- {len(rows)} machine(s)", file=sys.stderr)
PY

  psql "$BASE dbname=$db" -v ON_ERROR_STOP=1 -q -f /tmp/spectra-allowlist.sql \
    || die "import failed - nothing was committed"
  rm -f /tmp/spectra-allowlist.sql
  psql "$BASE dbname=$db" -tAc \
    "SELECT '   employees: '||(SELECT count(*) FROM employee WHERE org_id='$id')
          ||'   allowlisted machines: '||(SELECT count(*) FROM device_allowlist WHERE org_id='$id');"
  log "done"
}

case "${1:-}" in
  migrate) shift; cmd_migrate "$@" ;;
  status)  shift; cmd_status  "$@" ;;
  psql)    shift; cmd_psql    "$@" ;;
  sql)     shift; cmd_sql     "$@" ;;
  publish) shift; cmd_publish "$@" ;;
  seed)          shift; cmd_seed          "$@" ;;
  enroll-secret) shift; cmd_enroll_secret "$@" ;;
  allowlist)     shift; cmd_allowlist     "$@" ;;
  *) cat <<EOF
Spectra DB helper

  ./spectra-db.sh publish s3://bucket/prefix   (from your Mac, once per change)
  ./spectra-db.sh migrate                      apply pending migrations to both DBs
  ./spectra-db.sh status                       show what's applied
  ./spectra-db.sh psql <database>              interactive shell
  ./spectra-db.sh sql  <database> "<sql>"      one statement

Seeding (run once per environment, in this order):
  ./spectra-db.sh seed <database>                     ensure the organization row
  ./spectra-db.sh allowlist <database> <file.csv>     import machines + employees
  ./spectra-db.sh enroll-secret <database> [arn]      issue/rotate the fleet secret

  CSV header: hostname,email,full_name[,employee_code][,note]
  The [arn] is the app cell's 'terraform output enrollment_secret_arn'; pass it
  and the plaintext is stored in Secrets Manager instead of printed only once.

Environment (all optional):
  AWS_REGION   default us-east-1
  DB_INSTANCE  default spectra-global-data-pg
  S3_BASE      where publish put things, e.g. s3://bucket/spectra-db
  MIG_DIR      use local .sql files instead of fetching from S3
  ORG_NAME     default 'E2M Tech'
EOF
     exit 1 ;;
esac
