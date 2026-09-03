# Spectra infrastructure — conventions & locked decisions

Fixed decisions for the `infra/` Terraform. Follow exactly; don't re-introduce old
defaults. Changing any rule here requires an explicit decision.
(This doc mirrors the `spectra-infra` assistant skill so the rules live in git too.)

## Non-negotiables

- **Terraform `required_version` = `>= 1.5.7`** in every root's `versions.tf`. Never `>= 1.6.0`, never bump.
- **AWS provider** `version = "~> 5.60"`, `source = "hashicorp/aws"`. Don't change pins (lockfile may resolve to a 5.x patch — fine).
- **Region = `us-east-1`** everywhere (variable defaults + every `terraform.tfvars`).
- **No tarballs** for delivery — edit files directly in the tree (git workflow).
- Never sed/replace inside `.terraform/` (gitignored provider/module cache).

## State & tooling

- **Scalr** manages state + locking, one workspace per root dir → **no `backend` block**, **no S3/DynamoDB bootstrap**.
- `terraform fmt` + `terraform validate` per root before commit.

## Layout

```
infra/
  modules/            network, security-baseline, postgres, ecs-cluster, ecr,
                      cognito, screenshots-bucket, app-alb, observability-pagerduty
  workspace/global/   network/  data/  edge/  observability/   (shared layer)
  apps/               spectra-prod-01/  spectra-stag-01/        (thin per-env cells)
```
Cell naming `spectra-<env>-NN`; seed globally-unique names from the `instance`/`name` var.

## Shared vs isolated

- **Shared (workspace/global):** VPC, single NAT gateway, KMS, SGs, WAF (network); one RDS instance (data); one ALB, host-based routing (edge); PagerDuty (observability).
- **Isolated per env (apps/*):** ECS cluster + ASG + capacity provider, ECR repos, screenshots S3 bucket, Cognito pool, task IAM. Staging sized smaller than prod via tfvars.
- **DB isolation in the one instance:** per-env database + least-priv role (`spectra_prod`/`spectra_stag`; roles `*_app` with `GRANT rds_iam`). Bootstrap SQL in `infra/README.md`; migrations in `agent-api/db/migrations`.

## Cross-layer wiring

- **Scalr remote-state sharing only** (`terraform_remote_state`, `backend = "remote"`). No `aws_ssm_parameter` for passing resource IDs. The only allowed `aws_ssm_parameter` is the data-source read of AWS's ECS-optimized AMI id (in `modules/ecs-cluster`).
- **Secrets** → Secrets Manager (RDS-managed master password) or Scalr sensitive variables (e.g. `pagerduty_token`). Never a plain SSM String; never in state/git/tfvars.

## Networking / cost

- `single_nat_gateway = true`; private subnets (no public IP) + public subnets + NAT.
- **No interface VPC endpoints** (standing fee not worth it at our volume). Keep only the free **S3 gateway endpoint**. Re-add a specific interface endpoint only if proven high-volume.

## RDS / security

- `iam_database_authentication_enabled = true`; apps use short-lived IAM tokens (`rds-db:connect` on the task role, scoped to `dbuser/<db_name>_app`) and never receive the master secret.
- `storage_encrypted` w/ shared KMS; `deletion_protection = true`; `publicly_accessible = false`; `manage_master_user_password = true`.
- S3: SSE-KMS, public access blocked, TLS-only policy, lifecycle IA@30d / expire@180d.
- ALBs: placeholder HTTP:80 listener in Phase 0; Phase 1 adds ACM + HTTPS + host-based rules (distinct rule-priority range per env).

## Apply order

`global-network` → `global-data` → `global-edge` → `global-observability` → logical DB bootstrap → `spectra-prod-01` / `spectra-stag-01`.
