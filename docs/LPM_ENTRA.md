# Entra ID SSO + least-privilege workspace (LPM)

This repository combines two requirements for Databricks on GCP:

1. **Entra ID (own IdP) SSO** — Google ID token auth is refused. The pipeline uses GitHub OIDC for Databricks and sends the apply identity’s Google access token in `X-Databricks-GCP-SA-Access-Token` via the community `magodo/restful` provider for network configs, VPC endpoint registrations, and workspaces.
2. **Least-privilege workspace create (LPM)** — the apply identity must not hold `compute.firewalls.create`, `compute.firewalls.update`, or `compute.networks.updatePolicy`. LPM creates the workspace in `PROVISIONING`, grants operator roles to the returned workspace service account, then PATCHes the network on.

## Private Preview

`expected_workspace_status = "PROVISIONING"` is **required** for LPM. Without it, Databricks uses the normal create path and needs the firewall permissions above. On GCP this field is **Private Preview** (API and Terraform provider). There is no GA alternative that avoids those firewall permissions.

## What the network team must pre-create

This template creates **no** VPC firewall rules. Before apply:

| Rule | Purpose |
|---|---|
| Intra-subnet ingress (all protocols) on each Databricks subnet | Required by LPM docs; default GCP `default-allow-internal` equivalent |
| Optional: IAP SSH (`tcp/22` from `35.235.240.0/20`, tag `iap-ssh`) | Only if you use the front-end test VM / runner |

## Bootstrap

`bootstrap/lpm.tf` creates:

- LPM creator role → bound to `gha-apply`
- Three operator roles (project, resource, network)
- Optional `databricks-compute` service account (`create_databricks_compute_sa`)

`bootstrap/gcp.tf` with `least_privilege_apply = true` (default) grants `gha-apply` the `gha_apply_no_firewall` custom role instead of `roles/owner`.

## Databricks stack flow

1. `restful_resource.workspace` / `workspace_psc` — POST with `expected_workspace_status=PROVISIONING`
2. `google_project_iam_member` / `google_compute_subnetwork_iam_member` — operator grants
3. `restful_operation.workspace_*_attach` — PATCH `network_id` + `private_access_settings_id`, poll to `RUNNING`

## Known limits

- **Subnets are pre-created, not by this stack.** Creating a subnet needs `compute.networks.updatePolicy`, which the network team denies. The GCP stack reads the subnets as data sources and fails the plan if one is missing or has the wrong range: `gha-test-vpc-us-central1` (`10.250.0.0/24`), `gha-test-psc-vpc-us-central1` (`10.251.0.0/24`), `gha-test-psc-vpc-psc-us-central1` (`10.251.1.0/28`), `gha-test-fe-vpc-us-central1` (`10.252.0.0/24`), `gha-test-fe-vpc-psc-us-central1` (`10.252.1.0/28`). Private Google access on.
- **VPC endpoint quota.** GCP and Databricks cap Databricks VPC endpoints per region per service attachment per host project. The error is `You can create at most 10 Databricks VPC endpoints in us-central1 against service attachment ngrok-psc-endpoint per host GCP project`. A shared project can hit it, and the relay endpoint then fails with HTTP 429. Ask the account team for a quota increase, or use a region with headroom.
- **Workspace service account.** The create response carries `gcp_workspace_service_account`, but the GET that refresh reads does not, so the stack derives it as `db-<workspace_id>@prod-gcp-<region>.iam.gserviceaccount.com`. The grant fails if the account doesn't exist.
- **Project IAM policy size.** LPM binds the workspace operator roles at project level, with one IAM condition per workspace. GCP caps the size of a project IAM policy, so a shared project with many Databricks workspaces can reach the limit. Adding the `gha-apply` bindings then fails with `The size of the policy is too large`. Use a project with headroom, or split workspaces across projects. In the sandbox this was fixed by removing the test team's own stale LPM bindings, not other teams' bindings.
- **Private Preview.** See above. This template does not work without `expected_workspace_status`.

## Validation

- `scripts/validate-lpm-entra.sh` runs an API-level check of the combined path (dual token + LPM) against a sandbox project.
- **End-to-end run (sandbox `gcp-sandbox-field-eng`, 2026-11-18):** the `bootstrap/` apply, the GCP stack, and the `databricks/` stack all ran as `gha-apply`, with no firewall permissions. Both test workspaces (`gha-test-classic`, `gha-test-psc`) were created in `PROVISIONING`, the operator grants applied, and both were attached and reached `RUNNING`. Firewall create as `gha-apply` is denied, as expected.
- The dev project (`gcp-dev-field-eng`) was not tested; the test user lacks IAM-admin rights there.
