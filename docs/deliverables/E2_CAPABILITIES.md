# E2. Capability table

**2026-11-13, after the end-to-end rebuild.** What a GitHub Actions pipeline can do with Terraform on a Databricks on GCP account whose SSO uses its own identity provider, authenticating by workload identity federation only (no keys). Evidence is in [E1](E1_RESULTS.md).

**Legend.** ✅ works through the Databricks provider on `github-oidc`. 🔑 needs the `X-Databricks-GCP-SA-Access-Token` header, so the Databricks provider can't do it; done with a generic REST provider (`magodo/restful`) sending both tokens, also in Terraform. ⬜ not tested. — not applicable.

## Account level (`accounts.gcp.databricks.com`, reachable from GitHub-hosted runners)

| Object | Read / import | Create | Update | Delete | Notes |
|---|---|---|---|---|---|
| Network configuration | ✅ | 🔑 ✅ | — | ✅ | No in-place updates. Delete works through the Databricks provider without the header (and through the REST provider). A configuration stays bound to a deleted workspace (R5) |
| VPC endpoint registration (PSC) | 🔑 ✅ | 🔑 ✅ | — | 🔑 ✅ | Registration is what moves the GCP endpoint from `PENDING` to `ACCEPTED`. Deleted through the REST provider in the teardown |
| Private access settings | ✅ | ✅ | ✅ | ✅ | No header. Public access on/off, level `ACCOUNT` |
| Workspace (classic, customer-managed VPC) | ✅ | 🔑 ✅ | 🔑 ✅ | 🔑 ✅ | Update needs `update_mask` (R4). Create, update and delete are asynchronous: poll `workspace_status` to `RUNNING`, and a delete until 404. A delete leaves Databricks-created objects in the project (R10) |
| Workspace permission assignment | ✅ | ✅ | ⬜ | ⬜ | |
| Network connectivity configuration | — | — | — | — | Not enabled on the account; serverless only, out of scope |
| Metastore, metastore assignment | ⬜ | ⬜ | ⬜ | ⬜ | New workspaces were assigned the regional metastore automatically |
| Service principal, account role, federation policy | ✅ | ✅ | ⬜ | ✅ | The automation principal itself, created by Terraform (`bootstrap/`) run locally by an account admin: the pipeline can't create the identity it signs in as. Deleting the principal deletes its policy |
| Account groups | ⬜ | ⬜ | ⬜ | ⬜ | |

## Workspace level (the workspace URL; with public access off, only through the front-end endpoint, so from a runner inside the network)

| Object | Read / import | Create | Update | Delete | Notes |
|---|---|---|---|---|---|
| Cluster policy | ✅ | ✅ | ⬜ | ⬜ | |
| Cluster (classic) | ✅ | ✅ | ⬜ | ⬜ | Needs an access mode, e.g. dedicated (R9). Started with back-end PSC only, no internet route |
| Unity Catalog: storage credentials, external locations, catalogs, grants | ⬜ | ⬜ | ⬜ | ⬜ | Expected to work like other workspace objects; not tested |

## GCP (Google provider, the pipeline's apply identity)

| Object | Works | Notes |
|---|---|---|
| VPCs, subnets, firewall rules, Cloud NAT | ✅ | |
| PSC consumer endpoints (forwarding rules) | ✅ | `load_balancing_scheme = ""` |
| Private DNS zone (compute plane), response policy (users and CI) | ✅ | R7 |
| Domain restricted sharing exception and profile | ❌ for the pipeline | Needs Organization Policy Administrator at the organization (R2). A prerequisite set once per workspace project by its administrators |

## What stays outside Terraform

| Step | Who | How often |
|---|---|---|
| Domain restricted sharing exception for Databricks' customer ID, narrowed by a profile admitting the four provisioning grants (R2, R3) | Organization policy administrator | Once per workspace project |
| The pipeline's authentication: Google workload identity pool, provider, apply and plan identities, state bucket; the Databricks automation principal, account admin, federation policy | GCP and Databricks administrators, with their own sign-ins | Once per repository. **In Terraform** (`bootstrap/`), but applied locally, not by the pipeline |
| Self-hosted runner registration | Repository admin | Once per runner (or automated with a GitHub App for ephemeral runners) |
