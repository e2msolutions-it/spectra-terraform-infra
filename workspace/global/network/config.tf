terraform {
  cloud {
    hostname     = "e2msolutions.scalr.io"
    organization = "env-v0o989ah28npjf8t6"

    workspaces {
      name = "spectra-global-network"
    }
  }
}