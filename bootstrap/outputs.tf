# The repository variables the workflows read (Settings -> Secrets and
# variables -> Actions -> Variables). None of them is a secret.
output "repository_variables" {
  description = "Repository variable name => value."
  value = {
    GCP_WIF_PROVIDER      = google_iam_workload_identity_pool_provider.github.name
    GCP_APPLY_SA          = google_service_account.apply.email
    GCP_PLAN_SA           = google_service_account.plan.email
    TF_STATE_BUCKET       = google_storage_bucket.state.name
    DATABRICKS_ACCOUNT_ID = var.databricks_account_id
    DATABRICKS_CLIENT_ID  = databricks_service_principal.automation.application_id
  }
}

output "federation_subject" {
  description = "The subject the Databricks federation policy trusts."
  value       = databricks_service_principal_federation_policy.github_main.oidc_policy.subject
}
