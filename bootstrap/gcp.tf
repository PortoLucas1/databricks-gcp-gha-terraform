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

# Apply identity project IAM.
#
# Default (least_privilege_apply = true): custom role without
# compute.firewalls.create, compute.firewalls.update, or
# compute.networks.updatePolicy. Pair with LPM workspace create (databricks/).
#
# Lab fallback (least_privilege_apply = false): roles/owner on this project.
#trivy:ignore:GCP-0007
#trivy:ignore:AVD-GCP-0007
resource "google_project_iam_custom_role" "apply_no_firewall" {
  count = var.least_privilege_apply ? 1 : 0

  role_id     = "gha_apply_no_firewall"
  title       = "GitHub Actions apply (no firewall)"
  description = "GCP stack + LPM grants. Omits compute.firewalls.create/update and compute.networks.updatePolicy."
  permissions = [
    # Resource manager / IAM / service usage
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.setIamPolicy",
    "iam.roles.get",
    "iam.roles.list",
    "iam.serviceAccounts.actAs",
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.delete",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.setIamPolicy",
    "serviceusage.services.enable",
    "serviceusage.services.get",
    "serviceusage.services.list",
    "serviceusage.services.use",
    # Compute: networks and PSC (no firewalls.*, no networks.updatePolicy)
    "compute.networks.create",
    "compute.networks.delete",
    "compute.networks.get",
    "compute.networks.list",
    "compute.networks.update",
    "compute.networks.use",
    "compute.subnetworks.create",
    "compute.subnetworks.delete",
    "compute.subnetworks.get",
    "compute.subnetworks.getIamPolicy",
    "compute.subnetworks.list",
    "compute.subnetworks.setIamPolicy",
    "compute.subnetworks.update",
    "compute.subnetworks.use",
    "compute.routers.create",
    "compute.routers.delete",
    "compute.routers.get",
    "compute.routers.list",
    "compute.routers.update",
    "compute.routers.use",
    "compute.addresses.create",
    "compute.addresses.createInternal",
    "compute.addresses.delete",
    "compute.addresses.deleteInternal",
    "compute.addresses.get",
    "compute.addresses.list",
    "compute.addresses.setLabels",
    "compute.addresses.use",
    "compute.addresses.useInternal",
    "compute.forwardingRules.create",
    "compute.forwardingRules.delete",
    "compute.forwardingRules.get",
    "compute.forwardingRules.list",
    "compute.forwardingRules.pscCreate",
    "compute.forwardingRules.pscDelete",
    "compute.forwardingRules.pscSetLabels",
    "compute.forwardingRules.pscUpdate",
    "compute.forwardingRules.setLabels",
    "compute.forwardingRules.use",
    "compute.serviceAttachments.use",
    # PSC consumer endpoints register in Service Directory (goog-psc-default).
    "servicedirectory.endpoints.create",
    "servicedirectory.endpoints.delete",
    "servicedirectory.endpoints.get",
    "servicedirectory.endpoints.list",
    "servicedirectory.endpoints.update",
    "servicedirectory.namespaces.create",
    "servicedirectory.namespaces.delete",
    "servicedirectory.namespaces.get",
    "servicedirectory.namespaces.list",
    "servicedirectory.namespaces.update",
    "servicedirectory.services.create",
    "servicedirectory.services.delete",
    "servicedirectory.services.get",
    "servicedirectory.services.list",
    "servicedirectory.services.update",
    "compute.regions.get",
    "compute.regions.list",
    "compute.zones.get",
    "compute.zones.list",
    "compute.globalOperations.get",
    "compute.regionOperations.get",
    "compute.zoneOperations.get",
    # Optional runner VM
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setTags",
    "compute.instances.update",
    "compute.disks.create",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.list",
    "compute.disks.use",
    "compute.disks.setLabels",
    "compute.images.get",
    "compute.images.useReadOnly",
    # DNS
    "dns.managedZones.create",
    "dns.managedZones.delete",
    "dns.managedZones.get",
    "dns.managedZones.list",
    "dns.managedZones.update",
    "dns.changes.create",
    "dns.changes.get",
    "dns.changes.list",
    "dns.networks.bindPrivateDNSZone",
    "dns.networks.bindDNSResponsePolicy",
    "dns.networks.targetWithPeeringZone",
    "dns.policies.create",
    "dns.policies.delete",
    "dns.policies.get",
    "dns.policies.list",
    "dns.policies.update",
    "dns.resourceRecordSets.create",
    "dns.resourceRecordSets.delete",
    "dns.resourceRecordSets.get",
    "dns.resourceRecordSets.list",
    "dns.resourceRecordSets.update",
    "dns.responsePolicies.create",
    "dns.responsePolicies.delete",
    "dns.responsePolicies.get",
    "dns.responsePolicies.list",
    "dns.responsePolicies.update",
    "dns.responsePolicyRules.create",
    "dns.responsePolicyRules.delete",
    "dns.responsePolicyRules.get",
    "dns.responsePolicyRules.list",
    "dns.responsePolicyRules.update",
    # State / artifact buckets
    "storage.buckets.create",
    "storage.buckets.delete",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
    "storage.buckets.setIamPolicy",
    "storage.buckets.update",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
  ]
}

resource "google_project_iam_member" "apply" {
  project = var.project_id
  role    = var.least_privilege_apply ? google_project_iam_custom_role.apply_no_firewall[0].id : "roles/owner"
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
