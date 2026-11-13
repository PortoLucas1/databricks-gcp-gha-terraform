# ---------------------------------------------------------------------------
# Scenario B: back-end Private Service Connect (docs/PSC_SCENARIOS.md)
#
# A VPC of its own, apart from gha-test-vpc (scenario A, no back-end PSC). The
# private gcp.databricks.com zone below answers every Databricks name in the
# VPC it is bound to, so a workspace without back-end PSC can't share it.
#
# Two consumer endpoints onto Databricks' us-central1 service attachments: the
# workspace REST API (plproxy), which the compute plane calls, and the secure cluster connectivity relay (ngrok).
# They are constants per region, shared by every workspace in the VPC.
#
# A new endpoint sits in PENDING, and bills, until Databricks accepts it, which
# happens when the databricks stack registers it (databricks/psc.tf). Apply
# this stack, then that one.
# ---------------------------------------------------------------------------

locals {
  psc_vpc_name = "gha-test-psc-vpc"

  psc_endpoints = {
    psc-be-plproxy-usc1 = {
      address     = "10.251.1.4"
      target      = "projects/gcp-prod-general/regions/us-central1/serviceAttachments/plproxy-psc-endpoint-all-ports"
      description = "Databricks workspace REST API, classic compute plane to control plane."
    }
    psc-be-relay-usc1 = {
      address     = "10.251.1.5"
      target      = "projects/prod-gcp-us-central1/regions/us-central1/serviceAttachments/ngrok-psc-endpoint"
      description = "Databricks secure cluster connectivity relay."
    }
  }

  # The compute plane's names that don't depend on a workspace. Each PSC
  # workspace's URL and dp- name go in this zone too, but from the account
  # stack (databricks/dns.tf), which is where the workspace's deployment name
  # becomes known: one pass builds everything.
  psc_dns_records = {
    "us-central1.psc.gcp.databricks.com"    = local.psc_endpoints.psc-be-plproxy-usc1.address
    "tunnel.us-central1.gcp.databricks.com" = local.psc_endpoints.psc-be-relay-usc1.address
  }
}

resource "google_compute_network" "psc" {
  name                    = local.psc_vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.this]
}

# The workspace's classic compute.
resource "google_compute_subnetwork" "psc_compute" {
  name                     = "${local.psc_vpc_name}-${var.region}"
  region                   = var.region
  network                  = google_compute_network.psc.id
  ip_cidr_range            = "10.251.0.0/24"
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# The endpoints only.
resource "google_compute_subnetwork" "psc_endpoints" {
  name          = "${local.psc_vpc_name}-psc-${var.region}"
  region        = var.region
  network       = google_compute_network.psc.id
  ip_cidr_range = "10.251.1.0/28"

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# GCE_ENDPOINT: PRIVATE_SERVICE_CONNECT is for global addresses onto Google
# API bundles and is refused for a regional consumer endpoint.
resource "google_compute_address" "psc" {
  for_each = local.psc_endpoints

  name         = each.key
  region       = var.region
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  subnetwork   = google_compute_subnetwork.psc_endpoints.id
  address      = each.value.address
  description  = each.value.description
}

resource "google_compute_forwarding_rule" "psc" {
  for_each = local.psc_endpoints

  name   = each.key
  region = var.region

  # Empty is what makes this a PSC consumer endpoint, not a load balancer.
  load_balancing_scheme = ""
  target                = each.value.target
  network               = google_compute_network.psc.id
  ip_address            = google_compute_address.psc[each.key].id

  # The private zone below is the only DNS for these; GCP would otherwise add
  # a Service Directory zone of its own.
  no_automate_dns_zone = true

  # A connection the producer closes leaves the rule inert; recreating it is
  # the only remedy.
  recreate_closed_psc = true

  description = each.value.description
}

resource "google_dns_managed_zone" "psc" {
  name        = "gha-test-psc-dbx"
  dns_name    = "gcp.databricks.com."
  description = "Compute plane view of gcp.databricks.com for ${local.psc_vpc_name}: Databricks names resolve to the back-end endpoints."
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.psc.id
    }
  }

  depends_on = [google_project_service.this]
}

resource "google_dns_record_set" "psc" {
  for_each = local.psc_dns_records

  managed_zone = google_dns_managed_zone.psc.name
  name         = "${each.key}."
  type         = "A"
  ttl          = 300
  rrdatas      = [each.value]
}
