# Shared CI/CD plumbing: ONE GitHub connection and ONE artifact bucket, used by
# every pipeline in every app cell.
#
# Both are deliberately shared rather than per-environment: a CodeConnections
# connection requires a manual browser handshake to authorise, so creating four
# of them would mean four manual steps and four things to re-authorise.
#
# The pipelines themselves live in the app cells (apps/spectra-*-01), because a
# pipeline deploys to that cell's cluster and services.
data "terraform_remote_state" "network" {
  backend = "remote"
  config = {
    hostname     = var.scalr_hostname
    organization = var.scalr_environment
    workspaces   = { name = var.network_workspace }
  }
}

locals {
  net = data.terraform_remote_state.network.outputs
}

# Created in PENDING state. It must be authorised ONCE in the console
# (Developer Tools -> Settings -> Connections -> Update pending connection),
# where you grant access to the GitHub org/repos. Terraform cannot complete
# an OAuth handshake, so this is unavoidable - but it is genuinely one-time.
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

module "artifacts" {
  source = "../../../modules/artifacts-bucket"

  name        = var.name
  suffix      = "artifacts"
  kms_key_arn = local.net.kms_key_arn

  # Build artifacts are disposable; no need to keep old versions for long.
  noncurrent_version_days = 7
}
