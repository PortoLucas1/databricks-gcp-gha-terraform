# ---------------------------------------------------------------------------
# The front end: users (and later, workspace-level automation) reaching the
# workspace URL privately. The same step in both scenarios
# (docs/PSC_SCENARIOS.md), and one endpoint serves every workspace in the
# account.
#
# A VPC of its own: the front end and the
# compute plane need different DNS answers for the same names, so they can't
# share a private zone. In a client's estate this is the VPC their users or
# their on-premises link reach.
#
# Same service attachment as the back end's REST endpoint (plproxy); a
# separate endpoint, registered like the others (databricks/psc.tf).
# ---------------------------------------------------------------------------

locals {
  fe_vpc_name         = "gha-test-fe-vpc"
  fe_endpoint_name    = "psc-fe-plproxy-usc1"
  fe_endpoint_address = "10.252.1.4"

  # The region's browser authentication name: without psc-auth, REST works
  # and the UI login hangs. us-central1.psc is the compute plane's name and
  # stays out of this view. Each workspace's URL and dp- name are rules in
  # the same policy, written by the account stack (databricks/dns.tf).
  fe_dns_records = {
    "us-central1.psc-auth.gcp.databricks.com" = local.fe_endpoint_address
  }
}

resource "google_compute_network" "fe" {
  name                    = local.fe_vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.this]
}

# Where users' machines, a test VM or a self-hosted runner would sit.
# Pre-provisioned by the network team (docs/LPM_ENTRA.md, "Subnets").
data "google_compute_subnetwork" "fe_clients" {
  name    = "${local.fe_vpc_name}-${var.region}"
  region  = var.region
  project = var.project_id

  lifecycle {
    postcondition {
      condition     = self.ip_cidr_range == "10.252.0.0/24"
      error_message = "Subnet ${local.fe_vpc_name}-${var.region} must use 10.252.0.0/24."
    }
  }
}

data "google_compute_subnetwork" "fe_endpoint" {
  name    = "${local.fe_vpc_name}-psc-${var.region}"
  region  = var.region
  project = var.project_id

  lifecycle {
    postcondition {
      condition     = self.ip_cidr_range == "10.252.1.0/28"
      error_message = "Subnet ${local.fe_vpc_name}-psc-${var.region} must use 10.252.1.0/28."
    }
  }
}

resource "google_compute_address" "fe" {
  name         = local.fe_endpoint_name
  region       = var.region
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  subnetwork   = data.google_compute_subnetwork.fe_endpoint.id
  address      = local.fe_endpoint_address
  description  = "Databricks workspace web app and REST API, for users."
}

resource "google_compute_forwarding_rule" "fe" {
  name                  = local.fe_endpoint_name
  region                = var.region
  load_balancing_scheme = ""
  target                = local.psc_endpoints.psc-be-plproxy-usc1.target
  network               = google_compute_network.fe.id
  ip_address            = google_compute_address.fe.id
  no_automate_dns_zone  = true
  recreate_closed_psc   = true
  description           = "Databricks workspace web app and REST API, for users."
}

# A response policy, not a private zone for gcp.databricks.com. A private
# zone is the only authority for its whole domain in the VPC: every name it
# doesn't list is NXDOMAIN, accounts.gcp.databricks.com included, which users
# need for the login redirect and a CI runner for the token exchange and the
# account API. The policy overrides the listed names and passes everything
# else to public DNS. (The back end's zone in psc.tf can be a whole-domain
# zone: the compute plane needs no other Databricks name.)
resource "google_dns_response_policy" "fe" {
  response_policy_name = "gha-test-fe-dbx"
  description          = "Users' view of the Databricks workspaces for ${local.fe_vpc_name}: each workspace name to the front-end endpoint; every other name resolves publicly."

  networks {
    network_url = google_compute_network.fe.id
  }

  depends_on = [google_project_service.this]
}

resource "google_dns_response_policy_rule" "fe" {
  for_each = local.fe_dns_records

  response_policy = google_dns_response_policy.fe.response_policy_name
  # Rule names start with a letter; workspace names start with digits.
  rule_name = "dbx-${replace(trimsuffix(each.key, ".gcp.databricks.com"), ".", "-")}"
  dns_name  = "${each.key}."

  local_data {
    local_datas {
      name    = "${each.key}."
      type    = "A"
      ttl     = 300
      rrdatas = [each.value]
    }
  }
}

output "frontend" {
  description = "The front-end endpoint, for the databricks stack."
  value = {
    network          = google_compute_network.fe.name
    endpoint_name    = google_compute_forwarding_rule.fe.name
    endpoint_state   = google_compute_forwarding_rule.fe.psc_connection_status
    endpoint_address = google_compute_address.fe.address
  }
}
