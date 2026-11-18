# ---------------------------------------------------------------------------
# Least-privilege workspace (LPM): operator grants + attach
#
# After restful_resource.workspace / workspace_psc create in PROVISIONING, grant
# the three operator roles to the workspace service account, then PATCH each
# workspace with its network and private access settings and poll to RUNNING.
# The workspace SA is derived from the workspace ID (the GET does not return
# gcp_workspace_service_account); see local.lpm_workspaces.
#
# Requires expected_workspace_status=PROVISIONING on create (Private Preview
# on GCP). See docs/LPM_ENTRA.md.
# ---------------------------------------------------------------------------

# Role IDs match bootstrap/lpm.tf. Override only if the project uses different IDs.
variable "lpm_role_ids" {
  description = "LPM operator custom role IDs. Defaults match bootstrap/lpm.tf."
  type = object({
    project  = optional(string)
    resource = optional(string)
    network  = optional(string)
  })
  default = {}
}

locals {
  # Create returns PROVISIONING immediately; treat that as success.
  workspace_poll_provisioning = {
    status_locator = "body.workspace_status"
    status = {
      success = "PROVISIONING"
      pending = ["PROVISIONING"]
    }
    default_delay_sec = 5
  }

  lpm = {
    project  = coalesce(var.lpm_role_ids.project, "projects/${var.gcp_project_id}/roles/lpm_databricks_project")
    resource = coalesce(var.lpm_role_ids.resource, "projects/${var.gcp_project_id}/roles/lpm_databricks_resource")
    network  = coalesce(var.lpm_role_ids.network, "projects/${var.gcp_project_id}/roles/lpm_databricks_network")
  }

  # The workspace's Google service account. The create response carries it,
  # but the GET that refresh reads does not, so it can't be read back from
  # state. Every Databricks workspace SA in the sandbox IAM policy follows
  # db-<workspace_id>@prod-gcp-<region>. The grant fails if the account does
  # not exist, so a wrong name cannot pass silently.
  lpm_workspaces = {
    classic = {
      workspace_id = restful_resource.workspace.output.workspace_id
      sa           = "db-${restful_resource.workspace.output.workspace_id}@prod-gcp-${var.region}.iam.gserviceaccount.com"
      network_id   = restful_resource.network.output.network_id
      subnet       = var.subnet_name
    }
    psc = {
      workspace_id = restful_resource.workspace_psc.output.workspace_id
      sa           = "db-${restful_resource.workspace_psc.output.workspace_id}@prod-gcp-${var.region}.iam.gserviceaccount.com"
      network_id   = restful_resource.network_psc.output.network_id
      subnet       = var.psc.subnet_name
    }
  }
}

# --- Operator grants (phase 2) ---------------------------------------------

resource "google_project_iam_member" "lpm_operator_project" {
  for_each = local.lpm_workspaces

  project = var.gcp_project_id
  role    = local.lpm.project
  member  = "serviceAccount:${each.value.sa}"
}

resource "google_project_iam_member" "lpm_operator_resource" {
  for_each = local.lpm_workspaces

  project = var.gcp_project_id
  role    = local.lpm.resource
  member  = "serviceAccount:${each.value.sa}"

  condition {
    title       = "lpm-${each.key}-ws-scope"
    description = "Scope resource role to workspace ${each.value.workspace_id}"
    expression  = "resource.name.extract(\"{x}databricks\") != \"\" && resource.name.extract(\"{x}${each.value.workspace_id}\") != \"\""
  }
}

resource "google_compute_subnetwork_iam_member" "lpm_operator_network" {
  for_each = local.lpm_workspaces

  project    = var.gcp_project_id
  region     = var.region
  subnetwork = each.value.subnet
  role       = local.lpm.network
  member     = "serviceAccount:${each.value.sa}"
}

# --- Attach network + PAS, poll to RUNNING (phase 3) -----------------------

resource "restful_operation" "workspace_attach" {
  path   = "/workspaces/${restful_resource.workspace.output.workspace_id}"
  method = "PATCH"

  body = {
    network_id                 = restful_resource.network.output.network_id
    private_access_settings_id = databricks_mws_private_access_settings.this.private_access_settings_id
  }

  poll = local.workspace_poll

  depends_on = [
    google_project_iam_member.lpm_operator_project["classic"],
    google_project_iam_member.lpm_operator_resource["classic"],
    google_compute_subnetwork_iam_member.lpm_operator_network["classic"],
  ]
}

resource "restful_operation" "workspace_psc_attach" {
  path   = "/workspaces/${restful_resource.workspace_psc.output.workspace_id}"
  method = "PATCH"

  body = {
    network_id                 = restful_resource.network_psc.output.network_id
    private_access_settings_id = databricks_mws_private_access_settings.this.private_access_settings_id
  }

  poll = local.workspace_poll

  depends_on = [
    google_project_iam_member.lpm_operator_project["psc"],
    google_project_iam_member.lpm_operator_resource["psc"],
    google_compute_subnetwork_iam_member.lpm_operator_network["psc"],
    restful_resource.vpc_endpoint,
  ]
}
