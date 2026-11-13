# The bootstrap: everything the pipeline authenticates with, created once by
# administrators, locally, with their own credentials. Nothing in the
# pipeline can create these: they are what lets the pipeline in.
#
#   gcp.tf         Google workload identity federation for this repository:
#                  pool, OIDC provider, the apply and plan identities, the
#                  state bucket the stacks keep their state in.
#   databricks.tf  The Databricks automation service principal, account
#                  admin, and its federation policy trusting this
#                  repository's main branch.
#
# Run as: a GCP administrator (project IAM, service accounts, workload
# identity pools) through gcloud application default credentials, and a
# Databricks account admin through a Databricks CLI profile. See
# docs/AUTH_BOOTSTRAP.md.

terraform {
  required_version = "~> 1.15"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.142"
    }
  }

  # In a bucket the administrators already have, not the one this creates:
  # -backend-config="bucket=<admin bucket>" -backend-config="prefix=<path>".
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
}

# Account level, as the person running this (a Databricks CLI profile on the
# account console, signed in through the IdP).
provider "databricks" {
  host       = "https://accounts.gcp.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_profile
}
