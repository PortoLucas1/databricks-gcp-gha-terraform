# What the pipeline builds. Deliberately free: a network with no VMs and an
# empty bucket. The point is the pipeline, not the resources.

resource "google_project_service" "this" {
  for_each = toset(["compute.googleapis.com", "dns.googleapis.com", "iap.googleapis.com"])

  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_network" "this" {
  name                    = var.network.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.this]
}

# Pre-provisioned by the network team (see docs/LPM_ENTRA.md). The apply
# identity cannot create subnets: that needs compute.networks.updatePolicy,
# which the network team denies. The data source fails the plan if the subnet
# is missing or its range is not the one this stack expects.
data "google_compute_subnetwork" "this" {
  name    = "${var.network.name}-${var.region}"
  region  = var.region
  project = var.project_id

  lifecycle {
    postcondition {
      condition     = self.ip_cidr_range == var.network.subnet_cidr
      error_message = "Subnet ${var.network.name}-${var.region} must use ${var.network.subnet_cidr}."
    }
  }
}

resource "google_storage_bucket" "artifacts" {
  name     = "${var.project_id}-artifacts"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}
