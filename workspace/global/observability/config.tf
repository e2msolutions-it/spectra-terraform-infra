terraform {
  cloud {
    hostname     = "e2msolutions.scalr.io"
    organization = "Production"

    workspaces {
      name = "spectra-global-observability"
    }
  }
}
