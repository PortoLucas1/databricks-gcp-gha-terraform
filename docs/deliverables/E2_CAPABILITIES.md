# E2. Capability table

**2026-11-14, after the end-to-end rebuild and the Entra SSO and AIM tests.** What a GitHub Actions pipeline can do with Terraform on a Databricks on GCP account whose SSO uses its own identity provider, authenticating by workload identity federation only (no keys). Evidence is in [E1](E1_RESULTS.md).

**Legend.** ✅ works through the Databricks provider on `github-oidc`. 🔑 needs the `X-Databricks-GCP-SA-Access-Token` header, so the Databricks provider can't do it; done with a generic REST provider (`magodo/restful`) sending both tokens, also in Terraform. ⬜ not tested. — not applicable.

## Account level (`accounts.gcp.databricks.com`, reachable from GitHub-hosted runners)

| Object | Read / import | Create | Update | Delete | Notes |
|---|---|---|---|---|---|
| Network configuration | ✅ | 🔑 ✅ | — | ✅ | No in-place updates. Delete works through the Databricks provider without the header (and through the REST provider). A configuration stays bound to a deleted workspace (R5) |
| VPC endpoint registration (PSC) | 🔑 ✅ | 🔑 ✅ | — | 🔑 ✅ | Registration is what moves the GCP endpoint from `PENDING` to `ACCEPTED`. Deleted through the REST provider in the teardown |
| Private access settings | ✅ | ✅ | ✅ | ✅ | No header. Public access on/off, level `ACCOUNT` |
| Workspace (classic, customer-managed VPC) | ✅ | 🔑 ✅ | 🔑 ✅ | 🔑 ✅ | Update needs `update_mask` (R4). Create, update and delete are asynchronous: poll `workspace_status` to `RUNNING`, and a delete until 404. A delete leaves Databricks-created objects in the project (R10) |
| Workspace permission assignment | ✅ | ✅ | ⬜ | ✅ | For a service principal (`ADMIN`) and for an Entra group provisioned by AIM (`USER`, U3); both deleted by the teardowns' destroy runs. An assignment alone gives the group's members **no entitlement** (R18): pair it with the workspace-level entitlement below |
| Network connectivity configuration | — | — | — | — | Not enabled on the account; serverless only, out of scope |
| Metastore, metastore assignment | ⬜ | ⬜ | ⬜ | ⬜ | New workspaces were assigned the regional metastore automatically |
| Service principal, account role, federation policy | ✅ | ✅ | ⬜ | ✅ | The automation principal itself, created by Terraform (`bootstrap/`) run locally by an account admin: the pipeline can't create the identity it signs in as. Deleting the principal deletes its policy; set `disable_as_user_deletion = false`, or a destroy only deactivates it (R14) |
| Service principal synced by AIM from Entra (option C) | ✅ | — | ✅ | — | Added from Entra in the account console (or on first use); Terraform can't create it, and can manage it only once provisioned, by application ID, which is the Entra client ID. Account admin and its own federation policy were accepted (set with the CLI, U7; [`examples/entra`](../../examples/entra/) does the same with Terraform's role and federation policy resources, untested). Once its Entra app registration was deleted, it was gone from the account, with its federation policy, without being deleted there |
| Account groups, with AIM | ✅ | — | — | — | Come from Entra: added in the account console (and removed there or with the CLI; after the Entra group was deleted, it was still in the account), then visible to `data "databricks_group"` by display name with their external ID. A group nested inside one that was added is **not** visible (R17). Member lists stay empty in the API; AIM resolves membership from Entra |
| Users, with AIM | ✅ | — | — | — | Created at first sign-in and linked to Entra (external ID) a few minutes later. Disabled in Entra: refused at Entra's sign-in, but still `active` in Databricks minutes later (R19). They stay in the account after the Entra user is deleted; remove them there |

## Workspace level (the workspace URL; with public access off, only through the front-end endpoint, so from a runner inside the network)

| Object | Read / import | Create | Update | Delete | Notes |
|---|---|---|---|---|---|
| Cluster policy | ✅ | ✅ | ⬜ | ⬜ | Deleted with the workspace in the teardowns, not by Terraform |
| Entitlements on a group (`databricks_entitlements`) | ✅ | ✅ | ⬜ | ⬜ | Workspace access on an Entra group assigned from the account stack (U4); what makes the assignment usable (R18). Pass each entitlement only when true: the provider refuses `workspace_consume` next to `workspace_access` even as `false` |
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
| Entra SSO and AIM on the Databricks account (SSO app, AIM app registration on the same tenant) | Databricks account admin, Entra administrator | Once |
| Adding each Entra group (and an Entra-owned pipeline principal, if used) to the account from Entra | Databricks account admin, in the account console | Once per group; then Terraform assigns and entitles it. The Entra groups and app registration themselves can be Terraform: [`examples/entra`](../../examples/entra/) |
| Leavers: revoking personal access tokens in Databricks | Workspace admins | Per leaver; minutes after the disable in Entra, the Databricks user still read `active` (R19) |
