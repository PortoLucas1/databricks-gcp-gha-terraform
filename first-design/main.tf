# The first design's Databricks sign-in (use case §2, test U0), kept apart from
# the reference implementation.
#
# The provider impersonates a Google service account and signs in to the
# account with a Google ID token minted as that account, as the Platform
# Deployment Kit's GCP template does. Own-IdP SSO turns that path off for the
# whole account (F2), so with SSO on this plan is expected to fail on the first
# account call (H1). Read only: one data source, no resources, no state.
#
# For the test, bootstrap/ (first_design_test = true) makes the apply identity
# a Databricks account admin and lets it mint tokens as itself. The workflow
# first-design.yml signs in to Google as the apply identity and runs the plan.

terraform {
  required_version = ">= 1.11"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.142"
    }
  }
}

variable "google_service_account_email" {
  description = "The Google service account the provider impersonates (the apply identity, GCP_APPLY_SA)."
  type        = string
}

variable "databricks_account_id" {
  description = "Databricks account ID (DATABRICKS_ACCOUNT_ID)."
  type        = string
}

provider "databricks" {
  host                   = "https://accounts.gcp.databricks.com"
  google_service_account = var.google_service_account_email
  account_id             = var.databricks_account_id
}

data "databricks_mws_workspaces" "all" {}

# A count, not the names or IDs: run logs stay free of identifiers.
output "workspace_count" {
  description = "Number of workspaces the service account can see, if the sign-in works."
  value       = length(data.databricks_mws_workspaces.all.ids)
}
