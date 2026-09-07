# Spectra — logical DB bootstrap

One-time setup that carves the single shared RDS instance into isolated
per-environment databases + IAM-auth roles, and loads the schema.

- `01_bootstrap.sql` — creates `spectra_prod` / `spectra_stag` databases and the
  passwordless `spectra_prod_app` / `spectra_stag_app` roles (`GRANT rds_iam`).
- `run-bootstrap.sh` — fetches the master password from Secrets Manager, runs
  `01_bootstrap.sql`, enables `pgcrypto`, and applies `agent-api/db/migrations`
  into each database **as the owning app role**.

Idempotent — safe to re-run. Verified against PostgreSQL 16.

## Gotcha: rds_iam disables password auth (never grant app roles to the master)

On RDS, any role that is a member of `rds_iam` can only authenticate with IAM
tokens — its password login is disabled. This bootstrap therefore never grants an
app role to the master, and the master (not the app role) owns the databases.

If the master ever shows `PAM authentication failed for user spectra_admin`, it
became a (transitive) `rds_iam` member. Recover with an IAM token, then re-run:

```bash
ENDPOINT=<db_address>
TOKEN="$(aws rds generate-db-auth-token --hostname "$ENDPOINT" --port 5432 --region us-east-1 --username spectra_admin)"
PGPASSWORD="$TOKEN" psql "host=$ENDPOINT port=5432 dbname=postgres user=spectra_admin sslmode=require" \
  -c "REVOKE spectra_prod_app FROM spectra_admin;" \
  -c "REVOKE spectra_stag_app FROM spectra_admin;"
```

## Do I need the migrations now?

No. `01_bootstrap.sql` (databases + roles) is enough for now; the schema migrations
in `agent-api/db/migrations` create *application* tables that only the agent-api /
worker / portal use, so run them in Phase 1. Create roles + DBs only with
`SKIP_MIGRATIONS=1 ./run-bootstrap.sh`, or skip the whole bootstrap until Phase 1 -
the remaining Phase 0 app cells don't touch the database.

## Why it must run inside the VPC

The RDS instance is private (`publicly_accessible = false`) and its security group
allows ingress **only from the ECS security group** (`global-network` output
`ecs_security_group_id`). So the machine you run this from must be **inside the VPC
and using that ECS security group** (or you temporarily add its SG to the RDS SG).

## Values you need

| Var | Where |
|---|---|
| `DB_HOST` | `global-data` output `db_address` |
| `SECRET_ID` | `global-data` output `db_master_secret_arn` |
| ECS SG (for the runner) | `global-network` output `ecs_security_group_id` |
| private subnet | `global-network` output `private_subnet_ids` |

Get outputs from Scalr (the workspace's Outputs tab) or `terraform output` in that root.

## Run it — Option A: AWS CloudShell VPC environment (recommended, no standing cost)

1. AWS Console -> CloudShell -> **Actions -> Create VPC environment**. Pick the Spectra
   VPC, a **private subnet**, and the **ECS security group**.
2. In the shell:
   ```bash
   sudo dnf install -y postgresql15   # psql client
   git clone <your-repo> && cd <repo>/infra/db-bootstrap   # or upload these files
   export DB_HOST='<db_address>'
   export SECRET_ID='<db_master_secret_arn>'
   export AWS_REGION=us-east-1
   ./run-bootstrap.sh
   ```

## Run it — Option B: throwaway EC2 via SSM Session Manager

1. Launch a `t3.micro` in a **private subnet** with the **ECS security group** and an
   instance profile granting `AmazonSSMManagedInstanceCore` + `secretsmanager:GetSecretValue`
   on the master secret.
2. `aws ssm start-session --target <id>`, install `postgresql` + `awscli`, copy these
   files over, set the env vars as above, run `./run-bootstrap.sh`, then **terminate** it.

## Run it — Option C: ECS run-task (later)

Once an app cell's cluster exists, run a one-off task from a `postgres`-client image
with these files, env vars, and a task role allowed to read the secret. Good for
re-running as part of CI.

## After bootstrap

Each environment has its own database + role, authenticated by short-lived IAM
tokens (no passwords). The ECS task role already carries `rds-db:connect` scoped to
`dbuser/<db_name>_app` (added in the app cells), so services connect with a token as
`spectra_prod_app` / `spectra_stag_app`.
