# ---------------------------------------------------------------------------
# Google: workload identity federation for GitHub Actions
#
# GitHub signs a short-lived OIDC token for each job (permissions:
# id-token: write). google-github-actions/auth sends it to Google's Security
# Token Service, which checks it against the pool's provider (issuer, the
# attribute condition) and returns a federated token; that token impersonates
# one of the service accounts below, if the principal set it belongs to holds
# roles/iam.workloadIdentityUser on it. No key exists anywhere.
# ---------------------------------------------------------------------------

locals {
  repo = "${var.github.owner}/${var.github.repository}"
}

resource "google_project_service" "auth" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Tokens issued by GitHub Actions for ${local.repo}."

  depends_on = [google_project_service.auth]
}

# The claims Google keeps from GitHub's token, and the one condition every
# token must meet. Without the condition, any GitHub repository could mint
# tokens against this pool; the owner is matched by its numeric ID as well as
# the repository by name.
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub Actions OIDC" # 32 characters at most

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.event_name"          = "assertion.event_name"
    "attribute.runner_environment"  = "assertion.runner_environment"
  }

  attribute_condition = "assertion.repository_owner_id == \"${var.github.owner_id}\" && assertion.repository == \"${local.repo}\""
}

# The apply identity: plans on main and applies them; also the source of the
# X-Databricks-GCP-SA-Access-Token header. Needs no Databricks identity.
resource "google_service_account" "apply" {
  account_id   = "gha-apply"
  display_name = "Terraform apply (GitHub Actions)"
  description  = "Impersonated by ${local.repo} on refs/heads/main only."

  depends_on = [google_project_service.auth]
}

# Owner, bounded by this one project. Narrow it to the roles the stacks use
# where a project holds more than the lab.
#trivy:ignore:GCP-0007
#trivy:ignore:AVD-GCP-0007
resource "google_project_iam_member" "apply" {
  project = var.project_id
  role    = "roles/owner"
  member  = "serviceAccount:${google_service_account.apply.email}"
}

# main only: the ref claim, which GitHub sets from the branch the job runs on.
resource "google_service_account_iam_member" "apply_main" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/main"
}

# The plan identity, for pull requests: any ref of the repository, read-only.
# Anyone who can open a pull request can use it, so it must never hold a write
# permission.
resource "google_service_account" "plan" {
  account_id   = "gha-plan"
  display_name = "Terraform plan (GitHub pull requests)"
  description  = "Read-only identity for pull-request plans of ${local.repo}."

  depends_on = [google_project_service.auth]
}

resource "google_project_iam_member" "plan" {
  for_each = toset(["roles/viewer", "roles/iam.securityReviewer"])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.plan.email}"
}

resource "google_service_account_iam_member" "plan_any_ref" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.repo}"
}

# Every stack's state. The apply identity reaches it through owner; the plan
# identity reads it, so pull-request plans run with -lock=false.
resource "google_storage_bucket" "state" {
  name     = "${var.project_id}-tfstate"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.auth]
}

resource "google_storage_bucket_iam_member" "plan_state_read" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.plan.email}"
}

# U0 only (var.first_design_test): the provider's google_service_account path
# mints an ID token as the apply identity, using the apply identity's own
# federated credentials, so it needs token creator on itself.
resource "google_service_account_iam_member" "apply_self_token_creator" {
  count = var.first_design_test ? 1 : 0

  service_account_id = google_service_account.apply.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.apply.email}"
}
