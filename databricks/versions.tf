terraform {
  required_version = "~> 1.15"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.142"
    }
    # Each workspace's DNS records (dns.tf), as the apply identity.
    google = {
      source  = "hashicorp/google"
      version = "~> 8.10"
    }
    # The objects the Databricks provider can't create or update with SSO on
    # (rest.tf). Pinned exactly: a 0.x provider.
    restful = {
      source  = "magodo/restful"
      version = "0.25.2"
    }
  }

  # Same bucket as the GCP stack, its own prefix (-backend-config).
  backend "gcs" {}
}

# Account-level provider. No credentials here: the workflow sets
# DATABRICKS_AUTH_TYPE=github-oidc and DATABRICKS_CLIENT_ID, and the SDK
# exchanges the job's GitHub token for a Databricks token as the automation
# principal. The token's audience defaults to the account ID, which is what
# the principal's federation policy expects.
provider "databricks" {
  host       = "https://accounts.gcp.databricks.com"
  account_id = var.account_id
}
