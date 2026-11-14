# Option C: the pipeline's Databricks identity owned in Entra (use case test
# U7, finding R16). The same GitHub token exchange as bootstrap/'s native
# principal; Entra owns, reviews and disables the identity.
#
# Step 1 (pipeline_principal_name set): the app registration and its service
# principal, with no secret and no API permissions.
# Between the steps: add the service principal to the Databricks account from
# Entra (account console). Its Databricks application ID is the Entra client
# ID. Terraform can't do this part: AIM provisions it.
# Step 2 (pipeline_principal_provisioned = true): account admin and the
# service principal federation policy trusting GitHub's token for main.

locals {
  option_c      = var.pipeline_principal_name != null
  option_c_live = local.option_c && var.pipeline_principal_provisioned
  github_sub    = "repo:${var.github.owner}@${var.github.owner_id}/${var.github.repository}@${var.github.repository_id}:ref:refs/heads/main"
}

resource "azuread_application" "pipeline" {
  count        = local.option_c ? 1 : 0
  display_name = var.pipeline_principal_name
}

resource "azuread_service_principal" "pipeline" {
  count     = local.option_c ? 1 : 0
  client_id = azuread_application.pipeline[0].client_id
}

# Only needed for option B (Entra tokens exchanged by Databricks): lets a
# GitHub job get an Entra token for this app. Option C doesn't use it. Entra
# matches the subject exactly, so it carries the immutable-ID form (R1).
resource "azuread_application_federated_identity_credential" "github_main" {
  count = local.option_c && var.entra_token_exchange != null ? 1 : 0

  application_id = azuread_application.pipeline[0].id
  display_name   = "github-main"
  description    = "GitHub Actions, ${var.github.owner}/${var.github.repository}, main only."
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = local.github_sub
  audiences      = ["api://AzureADTokenExchange"]
}

data "databricks_service_principal" "pipeline" {
  count          = local.option_c_live ? 1 : 0
  application_id = azuread_application.pipeline[0].client_id
}

resource "databricks_service_principal_role" "pipeline_account_admin" {
  count                = local.option_c_live ? 1 : 0
  service_principal_id = data.databricks_service_principal.pipeline[0].id
  role                 = "account_admin"
}

resource "databricks_service_principal_federation_policy" "pipeline_github_main" {
  count                = local.option_c_live ? 1 : 0
  service_principal_id = tonumber(data.databricks_service_principal.pipeline[0].id)
  description          = "GitHub Actions, ${var.github.owner}/${var.github.repository}, main only."

  oidc_policy = {
    issuer  = "https://token.actions.githubusercontent.com"
    subject = local.github_sub
  }
}

# Option B, untested: Databricks accepts Entra-issued tokens for any synced
# identity whose token carries this audience. Account-wide: keep the audience
# dedicated to the pipeline.
resource "databricks_account_federation_policy" "entra" {
  count       = var.entra_token_exchange != null ? 1 : 0
  description = "Entra-issued tokens for the pipeline (option B)."

  oidc_policy = {
    issuer        = "https://login.microsoftonline.com/${var.entra_tenant_id}/v2.0"
    audiences     = [var.entra_token_exchange.audience]
    subject_claim = var.entra_token_exchange.subject_claim
  }
}

output "pipeline_principal_client_id" {
  description = "Set as DATABRICKS_CLIENT_ID (repository variable) to run the pipeline as the Entra-owned principal, once step 2 is applied."
  value       = local.option_c ? azuread_application.pipeline[0].client_id : null
}
