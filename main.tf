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

resource "google_compute_subnetwork" "this" {
  name                     = "${var.network.name}-${var.region}"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.network.subnet_cidr
  private_ip_google_access = true

  # Flow logs bill by volume; with nothing in the subnet there is none.
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
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
