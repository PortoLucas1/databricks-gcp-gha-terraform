# ---------------------------------------------------------------------------
# Least-privilege workspace (LPM) roles
#
# The apply identity is the workspace creator: its Google access token goes in
# X-Databricks-GCP-SA-Access-Token. With LPM it only needs read-level checks
# during create (this creator role). After create returns the Databricks-owned
# workspace service account, the databricks/ stack grants the three operator
# roles below, then PATCHes the workspace to RUNNING.
#
# Docs:
#   https://docs.databricks.com/gcp/en/admin/workspace/create-least-privilege-workspace
#   https://docs.databricks.com/gcp/en/admin/cloud-configurations/gcp/permissions
# ---------------------------------------------------------------------------

resource "google_project_iam_custom_role" "lpm_creator" {
  role_id     = "lpm_databricks_creator"
  title       = "Databricks LPM workspace creator"
  description = "Read-only checks for least-privilege classic workspace create (standalone VPC)."
  permissions = [
    "compute.networks.get",
    "compute.projects.get",
    "compute.subnetworks.get",
    "compute.subnetworks.getIamPolicy",
    "iam.roles.get",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "resourcemanager.projects.get",
    "resourcemanager.projects.getIamPolicy",
    "serviceusage.services.get",
    "serviceusage.services.list",
  ]
}

resource "google_project_iam_custom_role" "lpm_operator_project" {
  role_id     = "lpm_databricks_project"
  title       = "Databricks LPM operator project"
  description = "Workspace service account: project-level operate permissions."
  permissions = [
    "compute.disks.list",
    "compute.globalOperations.list",
    "compute.instances.list",
    "compute.regionOperations.list",
    "compute.regions.get",
    "compute.reservations.get",
    "compute.reservations.list",
    "compute.spotAssistants.get",
    "compute.zoneOperations.list",
    "compute.zones.get",
    "compute.zones.list",
    "iam.serviceAccounts.actAs",
    "resourcemanager.projects.get",
    "serviceusage.quotas.get",
    "serviceusage.services.list",
    "storage.buckets.list",
  ]
}

resource "google_project_iam_custom_role" "lpm_operator_resource" {
  role_id     = "lpm_databricks_resource"
  title       = "Databricks LPM operator resource"
  description = "Workspace service account: resource-level operate permissions (IAM-conditioned per workspace)."
  permissions = [
    "compute.disks.create",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.resize",
    "compute.disks.setLabels",
    "compute.disks.update",
    "compute.disks.use",
    "compute.disks.useReadOnly",
    "compute.instances.attachDisk",
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.detachDisk",
    "compute.instances.get",
    "compute.instances.getGuestAttributes",
    "compute.instances.getSerialPortOutput",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setServiceAccount",
    "compute.instances.setTags",
    "compute.instances.update",
    "storage.buckets.create",
    "storage.buckets.delete",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.setIamPolicy",
    "storage.buckets.update",
    "storage.multipartUploads.abort",
    "storage.multipartUploads.create",
    "storage.multipartUploads.list",
    "storage.multipartUploads.listParts",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.update",
  ]
}

resource "google_project_iam_custom_role" "lpm_operator_network" {
  role_id     = "lpm_databricks_network"
  title       = "Databricks LPM operator network"
  description = "Workspace service account: use the Databricks subnet."
  permissions = [
    "compute.subnetworks.get",
    "compute.subnetworks.use",
  ]
}

# Apply identity: LPM creator (Databricks validation) + IAM bind rights so the
# databricks/ stack can grant the operator roles after create. The broader GCP
# stack permissions stay on google_project_iam_member.apply in gcp.tf (narrowed
# when var.least_privilege_apply is true).
resource "google_project_iam_member" "apply_lpm_creator" {
  project = var.project_id
  role    = google_project_iam_custom_role.lpm_creator.id
  member  = "serviceAccount:${google_service_account.apply.email}"
}

# Pre-create the compute SA LPM expects (docs step 2). Skip if the project
# already has one (shared sandboxes).
variable "create_databricks_compute_sa" {
  description = "Create the databricks-compute service account used by clusters without a custom SA."
  type        = bool
  default     = true
}

resource "google_service_account" "databricks_compute" {
  count = var.create_databricks_compute_sa ? 1 : 0

  account_id   = "databricks-compute"
  display_name = "Databricks Compute"
  description  = "Default SA for clusters without a custom service account (LPM prerequisite)."
}

output "lpm_role_ids" {
  description = "Custom role IDs the databricks/ stack grants to each workspace service account."
  value = {
    creator  = google_project_iam_custom_role.lpm_creator.id
    project  = google_project_iam_custom_role.lpm_operator_project.id
    resource = google_project_iam_custom_role.lpm_operator_resource.id
    network  = google_project_iam_custom_role.lpm_operator_network.id
  }
}
