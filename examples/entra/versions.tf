# Entra-side Terraform for the use case (docs/USE_CASE.md): the Entra groups
# people get workspace access from, and an Entra-owned pipeline principal
# (option C in docs/AIM_ENTRA_ASSESSMENT.md). Applied locally by an Entra
# administrator and a Databricks account admin, like bootstrap/; not by the
# pipeline. See README.md for the order: AIM has to provision objects from
# Entra between the Entra and the Databricks parts.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.142"
    }
  }

  backend "gcs" {}
}

# Signed in with `az login` to the tenant behind the account's SSO and AIM.
provider "azuread" {
  tenant_id = var.entra_tenant_id
}

provider "databricks" {
  host       = "https://accounts.gcp.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_profile
}
