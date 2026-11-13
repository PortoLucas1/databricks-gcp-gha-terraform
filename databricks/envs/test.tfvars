gcp_project_id = "<project-id>"
region         = "us-central1"
vpc_name       = "gha-test-vpc"
subnet_name    = "gha-test-vpc-us-central1"

# The GCP stack's private zone (back end) and response policy (front end),
# where databricks/dns.tf writes each workspace's names.
dns = {
  psc_zone            = "gha-test-psc-dbx"
  psc_rest_address    = "10.251.1.4"
  fe_response_policy  = "gha-test-fe-dbx"
  fe_endpoint_address = "10.252.1.4"
}

# Scenario B (back-end PSC): the VPC, compute subnet and endpoints the GCP
# stack's psc.tf builds.
psc = {
  vpc_name       = "gha-test-psc-vpc"
  subnet_name    = "gha-test-psc-vpc-us-central1"
  rest_endpoint  = "psc-be-plproxy-usc1"
  relay_endpoint = "psc-be-relay-usc1"

  # The front end (GCP stack's frontend.tf), and whether the workspaces still
  # answer on the internet. false: only through a registered endpoint.
  frontend_endpoint = "psc-fe-plproxy-usc1"
  public_access     = false
}
