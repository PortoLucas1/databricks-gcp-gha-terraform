# ---------------------------------------------------------------------------
# Scenario B: a workspace with back-end Private Service Connect from creation
# (docs/PSC_SCENARIOS.md). The GCP stack's psc.tf builds the VPC and the two
# endpoints; apply it first.
#
# Every object here needs the Google token header, so all of it is the REST
# provider's: endpoint registration (which is also what makes Databricks
# accept the endpoints, PENDING to ACCEPTED), the network configuration that
# lists them, and the workspace.
# ---------------------------------------------------------------------------

variable "psc" {
  description = "Scenario B's VPC and compute subnet, the back-end and front-end endpoint (forwarding rule) names as the GCP stack builds them, and whether the workspaces keep public access."
  type = object({
    vpc_name          = string
    subnet_name       = string
    rest_endpoint     = string
    relay_endpoint    = string
    frontend_endpoint = string
    public_access     = bool
  })
}

# Registration is what makes Databricks accept an endpoint. Back end and front
# end register the same way: a back end is one listed in a network
# configuration, and a front end is any registered endpoint the private access
# settings let in (level ACCOUNT, main.tf).
locals {
  psc_registrations = {
    rest     = var.psc.rest_endpoint
    relay    = var.psc.relay_endpoint
    frontend = var.psc.frontend_endpoint
  }
}

resource "restful_resource" "vpc_endpoint" {
  for_each = local.psc_registrations

  path          = "/vpc-endpoints"
  read_path     = "/vpc-endpoints/$(body.vpc_endpoint_id)"
  create_method = "POST"

  body = {
    vpc_endpoint_name = "gha-test-${each.key}-${var.region}"
    gcp_vpc_endpoint_info = {
      project_id        = var.gcp_project_id
      psc_endpoint_name = each.value
      endpoint_region   = var.region
    }
  }
}

resource "restful_resource" "network_psc" {
  path          = "/networks"
  read_path     = "/networks/$(body.network_id)"
  create_method = "POST"

  body = {
    network_name = "gha-test-network-psc"
    gcp_network_info = {
      network_project_id = var.gcp_project_id
      vpc_id             = var.psc.vpc_name
      subnet_id          = var.psc.subnet_name
      subnet_region      = var.region
    }
    vpc_endpoints = {
      rest_api        = [restful_resource.vpc_endpoint["rest"].output.vpc_endpoint_id]
      dataplane_relay = [restful_resource.vpc_endpoint["relay"].output.vpc_endpoint_id]
    }
  }
}

# Created by Terraform through the REST provider, the first real workspace
# create that way (gha-test-classic was created by the probe and imported).
# The private access settings are scenario A's, public access on: the front
# end is the same step in both scenarios and comes later.
resource "restful_resource" "workspace_psc" {
  path          = "/workspaces"
  read_path     = "/workspaces/$(body.workspace_id)"
  create_method = "POST"
  update_method = "PATCH"
  update_query  = { update_mask = ["private_access_settings_id"] }

  body = {
    workspace_name = "gha-test-psc"
    location       = var.region
    cloud_resource_container = {
      gcp = {
        project_id = var.gcp_project_id
      }
    }
    network_id                 = restful_resource.network_psc.output.network_id
    private_access_settings_id = databricks_mws_private_access_settings.this.private_access_settings_id
  }

  poll_create = local.workspace_poll
  poll_update = local.workspace_poll
  poll_delete = local.workspace_delete_poll
}

# The automation principal as workspace admin, for workspace-level Terraform
# (workspace/, on the self-hosted runner). An account call that touches no GCP
# project, so the Databricks provider makes it.
variable "automation_client_id" {
  description = "Application ID of the automation service principal (the DATABRICKS_CLIENT_ID repository variable)."
  type        = string
}

data "databricks_service_principal" "automation" {
  application_id = var.automation_client_id
}

resource "databricks_mws_permission_assignment" "automation_psc" {
  workspace_id = restful_resource.workspace_psc.output.workspace_id
  principal_id = tonumber(data.databricks_service_principal.automation.scim_id)
  permissions  = ["ADMIN"]
}

# The workspace stack reads this (terraform_remote_state) for its provider's
# host.
output "workspace_psc" {
  description = "The scenario B workspace's id, URL and status."
  value = {
    workspace_id = restful_resource.workspace_psc.output.workspace_id
    url          = "https://${restful_resource.workspace_psc.output.deployment_name}.gcp.databricks.com"
    status       = restful_resource.workspace_psc.output.workspace_status
  }
}
