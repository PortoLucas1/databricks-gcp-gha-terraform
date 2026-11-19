# ---------------------------------------------------------------------------
# A test VM in the users' VPC (gha-test-fe-vpc), to reach the workspaces
# through the front-end endpoint from inside: DNS from the private zone, HTTPS
# through 10.252.1.4. The same place a self-hosted runner for workspace-level
# Terraform would go.
#
# Reached only by IAP TCP forwarding (gcloud compute ssh --tunnel-through-iap),
# with OS Login. No external IP. Without Cloud NAT (var.fe_runner_nat) it can
# reach Databricks through the endpoint and Google APIs through Private Google
# Access, and nothing else. No service account: as a runner, its jobs get
# Google credentials from GitHub's OIDC token, like the hosted runners.
#
# e2-micro and a 10 GB standard disk are inside the free tier in us-central1
# if nothing else uses it. var.fe_test_vm = false removes it.
# ---------------------------------------------------------------------------

variable "fe_test_vm" {
  description = "Whether the test VM in gha-test-fe-vpc exists."
  type        = bool
  default     = false
}

variable "fe_test_vm_type" {
  description = "Machine type of the test VM. e2-micro (free tier) for tests by hand; e2-small while it is a GitHub runner, which needs more than 1 GB."
  type        = string
  default     = "e2-micro"
}

# Outbound internet for the VM, which a self-hosted runner needs: GitHub
# (jobs, OIDC tokens, action downloads), HashiCorp's releases and the
# Terraform registry, Google's STS, and the Databricks account API. The
# workspace itself is reached through the front-end endpoint, not NAT.
variable "fe_runner_nat" {
  description = "Whether gha-test-fe-vpc has Cloud NAT."
  type        = bool
  default     = false
}

resource "google_compute_router" "fe" {
  count = var.fe_runner_nat ? 1 : 0

  name    = "${local.fe_vpc_name}-router"
  region  = var.region
  network = google_compute_network.fe.id
}

resource "google_compute_router_nat" "fe" {
  count = var.fe_runner_nat ? 1 : 0

  name                               = "${local.fe_vpc_name}-nat"
  router                             = google_compute_router.fe[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # The client subnet only; the endpoint subnet never needs it.
  subnetwork {
    name                    = data.google_compute_subnetwork.fe_clients.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_instance" "fe_test" {
  count = var.fe_test_vm ? 1 : 0

  name         = "fe-test-vm"
  zone         = "${var.region}-a"
  machine_type = var.fe_test_vm_type
  tags         = ["iap-ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  # No access_config block: no external IP (compute.vmExternalIpAccess).
  network_interface {
    subnetwork = data.google_compute_subnetwork.fe_clients.id
  }

  # compute.requireShieldedVm.
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  labels = {
    purpose   = "psc-front-end-test"
    ephemeral = "true"
  }

  allow_stopping_for_update = true

  depends_on = [google_project_service.this]
}

# No firewall rules here. Some organizations deny the apply identity
# compute.firewalls.create / compute.firewalls.update /
# compute.networks.updatePolicy. The network team must pre-create:
#   - intra-subnet ingress (all protocols) on each Databricks subnet
#   - optional IAP SSH (tcp/22 from 35.235.240.0/20, target tag iap-ssh)
# See docs/LPM_ENTRA.md.
