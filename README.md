# Spectra — Infrastructure (layered, Scalr)

Reusable, cost-efficient Terraform for running Spectra in multiple environments from
one codebase. Layout:

```
infra/
  modules/                     # reusable building blocks (pin by version in Scalr registry)
    network/  security-baseline/  postgres/  ecs-cluster/  ecr/
    cognito/  screenshots-bucket/  app-alb/  observability-pagerduty/
  workspace/global/            # shared layer — applied once, consumed by every app
    network/                   # VPC, subnets, NAT, S3 gateway endpoint, KMS, SGs, WAF -> outputs
    data/                      # single shared RDS PostgreSQL                  -> outputs
    compute/                   # shared ECS-on-EC2 cluster + ECR repos         -> outputs
    observability/             # PagerDuty escalation + services
  apps/                        # thin per-environment roots (real values in tfvars)
    spectra-prod-01/           # prod cell
    spectra-stag-01/           # staging cell
```

## Model (per your decisions)

- **Fully shared** VPC, NAT, ECS cluster, ECR, and **one RDS instance** across prod and
  staging — cheapest and simplest.
- **Logical isolation inside the shared DB:** each environment uses its own database
  (`spectra_prod`, `spectra_stag`) and a least-privilege role, so environments can't read
  each other's data. See "Logical DB bootstrap" below.
- **Per-environment** screenshots bucket + Cognito pool + ALBs (buckets/pools are free, so
  isolate them).
- **Wiring is Scalr remote-state sharing.** Each layer exposes `outputs`; downstream
  workspaces read them with `terraform_remote_state` (native list/map types preserved). No
  SSM parameters are used to pass resource IDs around — those values aren't secrets. Real
  secrets use **Secrets Manager** (RDS-managed DB password) or **Scalr variables** (the
  PagerDuty token). The only `aws_ssm_parameter` in the code is a *data source* reading AWS's
  published ECS-optimized AMI ID — a standard lookup, not our storage.

## Scalr

One Scalr **workspace per root directory** (VCS-driven; Scalr manages state + locking, so
there is no backend block in the code):

| Workspace | Working directory |
|---|---|
| `global-network` | `workspace/global/network` |
| `global-data` | `workspace/global/data` |
| `global-compute` | `workspace/global/compute` |
| `global-observability` | `workspace/global/observability` |
| `spectra-prod-01` | `apps/spectra-prod-01` |
| `spectra-stag-01` | `apps/spectra-stag-01` |

Recommended Scalr setup: put the global workspaces in a `spectra-global` environment and the
apps in `spectra-prod` / `spectra-staging` environments with their own AWS credentials and
approval policies (prod requires approval). Add **run triggers** so app workspaces re-plan
when `global-network` / `global-data` / `global-compute` change. Set `pagerduty_token` as a
sensitive variable on `global-observability`. Use OPA policies for guardrails (tags,
deny-public-S3, cost limits).

## Apply order (first time)

1. `global-network`  → VPC/subnets/SGs/KMS/WAF (exposed as outputs)
2. `global-data`     → single RDS instance (reads network via remote state)
3. `global-compute`  → shared ECS cluster + ECR (reads network via remote state)
4. `global-observability` → PagerDuty (needs token)
5. **Logical DB bootstrap** (once) — see below
6. `spectra-prod-01`, `spectra-stag-01` → per-env buckets, Cognito, ALBs, IAM

## Logical DB bootstrap (shared instance, isolated databases)

The RDS instance is private, so run this from inside the VPC (a Scalr agent in the VPC, a
bastion, or an in-VPC CI job). Pull the master password from the Secrets Manager secret named by the `db_master_secret_arn` output (an RDS-managed secret).

```sql
-- prod (IAM auth: role logs in with an IAM token, no password)
CREATE ROLE spectra_prod_app LOGIN;
GRANT rds_iam TO spectra_prod_app;
CREATE DATABASE spectra_prod OWNER spectra_prod_app;
REVOKE ALL ON DATABASE spectra_prod FROM PUBLIC;
-- staging
CREATE ROLE spectra_stag_app LOGIN;
GRANT rds_iam TO spectra_stag_app;
CREATE DATABASE spectra_stag OWNER spectra_stag_app;
REVOKE ALL ON DATABASE spectra_stag FROM PUBLIC;
```

Then apply the schema migrations (see `agent-api/db/migrations`) into each database. If you'd
prefer this managed in Terraform, we can add a `postgresql`-provider root that runs in-VPC.

## Notes

- No S3/DynamoDB state bootstrap needed — Scalr holds state per workspace.
- `single_nat_gateway = true` on the shared network keeps NAT cost down. The **free S3
  gateway endpoint** keeps the heavy screenshot traffic off NAT. No interface VPC endpoints -
  their ~$0.01/hr/AZ standing fee isn't worth it for our low-volume ECR/Secrets/KMS/Logs
  traffic, which just uses NAT. Re-add specific ones only if a service proves high-volume.
- ALBs come up with placeholder HTTP:80 listeners; Phase 1 adds ACM + HTTPS + target groups.
- Run `terraform fmt` and `terraform validate` per root before committing.
