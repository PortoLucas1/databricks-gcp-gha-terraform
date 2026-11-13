# ---------------------------------------------------------------------------
# Each workspace's DNS names, written here because this is where a
# workspace's deployment name (<workspace-id>.<n>) becomes known. The zone and
# the response policy are the GCP stack's (psc.tf, frontend.tf); the records
# and rules are this stack's, as the apply identity (the job's Google login).
#
#   back end   gha-test-psc's URL and dp- name in the compute plane's zone,
#              to the REST endpoint: its clusters need them to start.
#   front end  both workspaces' URL and dp- name in the users' response
#              policy, to the front-end endpoint.
# ---------------------------------------------------------------------------

variable "dns" {
  description = "Names and addresses from the GCP stack: the back end's private zone and REST endpoint, the front end's response policy and endpoint."
  type = object({
    psc_zone            = string
    psc_rest_address    = string
    fe_response_policy  = string
    fe_endpoint_address = string
  })
}

provider "google" {
  project = var.gcp_project_id
}

locals {
  deployments = {
    classic = restful_resource.workspace.output.deployment_name
    psc     = restful_resource.workspace_psc.output.deployment_name
  }

  # Static keys, so for_each is known at plan time; values after create.
  workspace_names = merge([
    for ws, d in local.deployments : {
      "${ws}-url" = "${d}.gcp.databricks.com"
      "${ws}-dp"  = "dp-${d}.gcp.databricks.com"
    }
  ]...)
}

resource "google_dns_record_set" "psc_workspace" {
  for_each = { for k, v in local.workspace_names : k => v if startswith(k, "psc-") }

  managed_zone = var.dns.psc_zone
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.dns.psc_rest_address]
}

resource "google_dns_response_policy_rule" "fe_workspace" {
  for_each = local.workspace_names

  response_policy = var.dns.fe_response_policy
  rule_name       = "dbx-${each.key}"
  dns_name        = "${each.value}."

  local_data {
    local_datas {
      name    = "${each.value}."
      type    = "A"
      ttl     = 300
      rrdatas = [var.dns.fe_endpoint_address]
    }
  }
}
