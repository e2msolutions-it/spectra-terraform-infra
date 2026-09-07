terraform {
  cloud {
    hostname     = "e2msolutions.scalr.io"
    organization = "env-v0o989aoif8oc5ddf"

    workspaces {
      name = "spectra-stag-01"
    }
  }
}
