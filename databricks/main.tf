variable "account_id" {
  description = "Databricks account ID. Set from the DATABRICKS_ACCOUNT_ID repository variable, not committed."
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project that holds the VPC and the workspace."
  type        = string
}

variable "region" {
  description = "Region of the subnet and the workspace."
  type        = string
}

variable "vpc_name" {
  description = "Customer-managed VPC built by the GCP stack (the repository root)."
  type        = string
}

variable "subnet_name" {
  description = "Subnet in vpc_name for the workspace's classic compute."
  type        = string
}

# C2 / H2: can the automation principal, on github-oidc with SSO on, read
# the account API? A plan reads this data source, so a clean plan answers it.
data "databricks_mws_workspaces" "all" {}


# C7 / H7: an account object that touches no GCP project, so the Databricks
# provider manages it. Private Service Connect's front-end settings, attached
# to both workspaces. Public access goes off once the front-end endpoint is
# registered (psc.tf, which this waits for): from then on the workspaces
# answer only through registered endpoints. var.psc.public_access turns it
# back on.
#
# ACCOUNT lets in any endpoint registered in the account. ENDPOINT with
# allowed_vpc_endpoint_ids is tighter, but how it treats the back-end REST
# endpoint on GCP is unverified, so the lab ran ACCOUNT.
resource "databricks_mws_private_access_settings" "this" {
  private_access_settings_name = "gha-test-pas-${var.region}"
  region                       = var.region
  public_access_enabled        = var.psc.public_access
  private_access_level         = "ACCOUNT"

  depends_on = [restful_resource.vpc_endpoint["frontend"]]
}


# A count, not the names or ids: run logs stay free of identifiers.
output "workspace_count" {
  description = "Number of workspaces the principal can see in the account."
  value       = length(data.databricks_mws_workspaces.all.ids)
}

output "network_name" {
  description = "Name of the network configuration, which the probe looks up."
  value       = restful_resource.network.output.network_name
}
