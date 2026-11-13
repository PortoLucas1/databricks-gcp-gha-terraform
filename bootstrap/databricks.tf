# ---------------------------------------------------------------------------
# Databricks: the automation service principal and its federation policy
#
# The same GitHub OIDC token, requested with the Databricks account ID as its
# audience, is exchanged at the account's token endpoint
# (/oidc/accounts/<account-id>/v1/token, grant type token-exchange,
# client_id = the principal's application ID) for a Databricks OAuth token as
# this principal, if the token matches the principal's federation policy:
# issuer, subject, audience. The SDK, CLI and Terraform provider do this
# themselves with auth type github-oidc. No secret exists anywhere.
# ---------------------------------------------------------------------------

# At account level the provider only deactivates a principal on destroy
# unless told otherwise; a teardown should leave nothing behind.
resource "databricks_service_principal" "automation" {
  display_name             = "github-terraform-ci"
  disable_as_user_deletion = false
}

# Account-level APIs need account admin; there is no read-only account role,
# which is why Databricks plans run on main only.
resource "databricks_service_principal_role" "automation_account_admin" {
  service_principal_id = databricks_service_principal.automation.id
  role                 = "account_admin"
}

# GitHub issues the immutable-ID subject, repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:<ref>,
# not the name-only form in older documentation; Databricks matches the
# subject exactly. A wrong subject fails the exchange with
# TOKEN_SUBJECT_INVALID, which names the subject the token carried.
# The audience is left at its default, the account ID.
resource "databricks_service_principal_federation_policy" "github_main" {
  service_principal_id = tonumber(databricks_service_principal.automation.id)
  description          = "GitHub Actions, ${var.github.owner}/${var.github.repository}, main only."

  oidc_policy = {
    issuer  = "https://token.actions.githubusercontent.com"
    subject = "repo:${var.github.owner}@${var.github.owner_id}/${var.github.repository}@${var.github.repository_id}:ref:refs/heads/main"
  }
}
