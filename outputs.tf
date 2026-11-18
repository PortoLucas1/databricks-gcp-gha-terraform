output "network" {
  description = "The test VPC's self link."
  value       = google_compute_network.this.self_link
}

output "artifacts_bucket" {
  description = "The test bucket."
  value       = google_storage_bucket.artifacts.name
}

output "psc" {
  description = "Scenario B's network and back-end endpoints, for the databricks stack."
  value = {
    network          = google_compute_network.psc.name
    compute_subnet   = data.google_compute_subnetwork.psc_compute.name
    endpoint_names   = keys(google_compute_forwarding_rule.psc)
    endpoint_states  = { for k, r in google_compute_forwarding_rule.psc : k => r.psc_connection_status }
    endpoint_address = { for k, a in google_compute_address.psc : k => a.address }
  }
}
