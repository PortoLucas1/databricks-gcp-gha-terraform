# ---------------------------------------------------------------------------
# The objects the Databricks provider can't create or update with own-IdP SSO
#
# Workspaces and network configurations need a Google access token in the
# X-Databricks-GCP-SA-Access-Token header, which the Databricks provider only
# sends on Google ID token auth, and the account refuses Google ID tokens once
# SSO is on. A generic REST provider sends it: the same Accounts API calls the
# Databricks provider makes, with both tokens.
#
# Both tokens are ephemeral variables: Terraform never writes them to the plan
# file or state, and a saved plan's apply has to be given them again. The
# workflows mint them in the step that runs Terraform:
#   databricks_token  the job's GitHub OIDC token exchanged for a Databricks
#                     token as the automation principal (.github/scripts/
#                     databricks-token.sh)
#   gcp_access_token  the apply identity's Google access token, from the
#                     job's workload identity login
# ---------------------------------------------------------------------------

variable "databricks_token" {
  description = "Databricks OAuth token for the automation principal."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "gcp_access_token" {
  description = "Google access token of the identity that owns the workspace project, for the X-Databricks-GCP-SA-Access-Token header."
  type        = string
  sensitive   = true
  ephemeral   = true
}

provider "restful" {
  base_url = "https://accounts.gcp.databricks.com/api/2.0/accounts/${var.account_id}"

  security = {
    http = {
      token = {
        token = var.databricks_token
      }
    }
  }

  header = {
    "X-Databricks-GCP-SA-Access-Token" = var.gcp_access_token
  }
}

locals {
  # Workspace creation and updates are asynchronous: the API answers at once,
  # and the workspace goes through PROVISIONING to RUNNING.
  workspace_poll = {
    status_locator = "body.workspace_status"
    status = {
      success = "RUNNING"
      pending = ["PROVISIONING"]
    }
    default_delay_sec = 30
  }

  # Deletion is asynchronous too: the workspace answers 200 until it's gone.
  # Its network configuration can't be deleted before that.
  workspace_delete_poll = {
    status_locator    = "code"
    status            = { success = "404", pending = ["200"] }
    default_delay_sec = 30
  }
}

# Scenario A (docs/PSC_SCENARIOS.md): a classic workspace on gha-test-vpc,
# without back-end PSC. The Databricks provider can't create a network
# configuration or a workspace on federation with SSO on (C3, C6), so both
# are the REST provider's. Only the attributes in body are compared with the
# API's.
resource "restful_resource" "network" {
  path          = "/networks"
  read_path     = "/networks/$(body.network_id)"
  create_method = "POST"

  body = {
    network_name = "gha-test-network"
    gcp_network_info = {
      network_project_id = var.gcp_project_id
      vpc_id             = var.vpc_name
      subnet_id          = var.subnet_name
      subnet_region      = var.region
    }
  }
}

# Updates are a PATCH with update_mask naming the fields that change; the API
# refuses a PATCH without one. The mask is static, so it must name exactly the
# fields a change touches: add the field here in the same change.
resource "restful_resource" "workspace" {
  path          = "/workspaces"
  read_path     = "/workspaces/$(body.workspace_id)"
  create_method = "POST"
  update_method = "PATCH"
  update_query  = { update_mask = ["private_access_settings_id"] }

  body = {
    workspace_name = "gha-test-classic"
    location       = var.region
    cloud_resource_container = {
      gcp = {
        project_id = var.gcp_project_id
      }
    }
    network_id = restful_resource.network.output.network_id
    # Switched to a second set and back again through the REST provider
    # (PATCH with update_mask): a change of private access settings is
    # reversible.
    private_access_settings_id = databricks_mws_private_access_settings.this.private_access_settings_id
  }

  poll_create = local.workspace_poll
  poll_update = local.workspace_poll
  poll_delete = local.workspace_delete_poll
}
