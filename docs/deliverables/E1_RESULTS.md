# E1. Results matrix

**2026-11-13, after the end-to-end rebuild.** Each hypothesis from the test requirements (H1–H12), its result, and the evidence. Identifiers are placeholders. Evidence references (workflow runs, apply runs, PRs) are to the lab repository; the full record is in [`../TEST_PLAN.md`](../TEST_PLAN.md) §6. Versions throughout: Terraform 1.15.9, Databricks provider 1.142.0, `magodo/restful` 0.25.2, Google provider 8.11.0.

The lab ran with the Databricks account's own-IdP SSO **on** for every test (an OIDC IdP; Entra ID before and after). Phases A and B, which need SSO off, did not run (decision D1).

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | The provider with `google_service_account` fails against the account API with SSO on | **Prior evidence only, not rerun** | Earlier on the same account (another CI system): `401 Invalid Request` on every account call after SSO was turned on, twice. Consistent with the Databricks documentation (F2) |
| H2 | A service principal on `github-oidc` reads account APIs with SSO on | **Confirmed** | A plan of `databricks_mws_workspaces` on `github-oidc`: every workspace visible. First attempt failed only on the federation policy's subject format (finding R1). Re-confirmed after the principal and its policy were recreated by Terraform (`bootstrap/`): `auth-check` exchanged the token (200) and the principal read its own record |
| H3 | `databricks_mws_networks` and `databricks_mws_workspaces` fail through the provider on `github-oidc` | **Confirmed**, for create and update | Network configuration create: "cannot create mws networks: Failed to get GCP OAuth access token … provide a GCP service account access token in the X-Databricks-GCP-SA-Access-Token header". Workspace update: "cannot update mws workspaces: BAD_REQUEST: Failed to get GCP OAuth access token …". Workspace create (direct API, no header): `400` with the same message. Reads and imports work |
| H4 | Direct Accounts API calls with the principal's token plus the header succeed | **Confirmed** | Network configuration `POST`: 201. Workspace `POST`: 201, then `RUNNING`. Workspace `PATCH` (with `update_mask`): 200, then `RUNNING`. VPC endpoint registration `POST`: created, endpoints moved to `ACCEPTED`. The Google token came from the pipeline's own workload identity login |
| H5 | The Google identity behind the header needs project permissions but no Databricks identity | **Confirmed** | The header's identity (the pipeline's apply identity) never had a Databricks user or service principal. It held project permissions only |
| H6 | API-created objects can be imported with a clean plan; updates and deletes need the header | **Confirmed**, with the REST provider closing the gap | Import of a network configuration and workspace: "2 imported, 0 changed", then "No changes". Workspace update through the Databricks provider: refused for the header. Through the REST provider with the header: create, update (and back), and delete of a network configuration all worked; plans clean afterwards. Workspace delete through the REST provider, polled until 404: worked in the teardown (E7). Network configuration delete through the Databricks provider: worked **without** the header. One-pass rebuild: every object created by Terraform with no imports, and the next plan showed no changes |
| H7 | Account objects that don't touch a GCP project work through the provider on `github-oidc` | **Confirmed** for private access settings (create, update, delete, public access off) and workspace permission assignment. **Not available:** network connectivity configurations ("Feature not enabled for account"; out of scope, the client uses classic compute only). **Not tested:** metastore, metastore assignment, groups, ingress policies | |
| H8 | Workspace-level resources work through the provider on `github-oidc` | **Confirmed** for a cluster policy and a cluster, through Private Service Connect with the workspace's public access off, from a self-hosted runner. **Not tested:** Unity Catalog storage credentials, external locations, catalogs, grants | The provider exchanged the GitHub token at the workspace's own token endpoint through the front-end endpoint. Cluster creation needed a dedicated access mode: no isolation is refused in a Unity Catalog workspace. Re-confirmed in the rebuild: the cluster started in 4m 51s through the back-end endpoints |
| H9 | Console creation with matching and non-matching Google accounts | **Not tested** (needs test accounts, decision D2) | |
| H10 | With SSO off, both paths create a workspace | **Prior evidence only, not rerun** (Phase A) | A classic workspace and network configuration were created through the provider with Google ID tokens before SSO was turned on |
| H11 | AIM with Entra on default Google sign-in | **Not tested** (optional) | |
| H12 | Private access settings and VPC endpoint registration also need the header | **Split** | Private access settings: **no header needed** (created, updated and deleted through the Databricks provider on `github-oidc`). VPC endpoint registration: **needs the header** (registered through the REST provider with it; prior evidence of the provider failing without it) |

## Findings beyond the hypotheses

| # | Finding |
|---|---|
| R1 | GitHub's OIDC subject for the repository was the immutable-ID form, `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:<ref>`. A federation policy with the name-only form fails with `TOKEN_SUBJECT_INVALID`, which names the subject the token carries |
| R2 | Domain restricted sharing refuses classic workspace provisioning's grants to Databricks-owned service accounts. A narrowed exception, set by an organization policy administrator, is a prerequisite per workspace project |
| R3 | Provisioning makes four kinds of grant to Databricks accounts (two project roles, a network role, and two storage roles on the workspace's default Unity Catalog bucket); a narrowed DRS profile must admit all four |
| R4 | A workspace update through the Accounts API needs an `update_mask` query parameter naming the changed fields; without it, `400 Update mask must be specified` |
| R5 | Deleting a failed workspace doesn't release its network configuration; a retry needs a new one |
| R6 | Removing an object and the workspace's reference to it in one apply can make Terraform delete the object first; Databricks refuses while it's attached. Detach in one apply, delete in the next |
| R7 | A private `gcp.databricks.com` zone in a users' or CI network makes `accounts.gcp.databricks.com` unresolvable there. Use a DNS response policy (or conditional forwarding) for the workspace names only |
| R8 | An unauthenticated request can't test private access: the network check comes after authentication (303 to login, 401 on the API, from the internet as from inside) |
| R9 | A Unity Catalog workspace refuses clusters without an access mode ("NO_ISOLATION … not allowed") |
| R10 | Deleting a classic workspace leaves an ingress firewall rule on its VPC (which blocks deleting the VPC), its three buckets, Databricks' custom roles and grants, and the `databricks-compute` service account in the project. See [E7](E7_TEARDOWN.md) |
| R11 | With an empty state bucket, a pull request's plan fails at `terraform init` as the read-only plan identity: init writes each stack's empty default state and its lock. The first plan of a new setup has to run on `main`, as the apply identity |
| R12 | With public access off, the workspace's own token endpoint still answers from the internet and issues a token; the refusal comes at the API: `403` "Unauthorized network access to workspace: <workspace-id>". The same principal, through the front-end endpoint, gets `200` |
| R13 | `terraform console` evaluates against state, so on a stack's first run a `terraform_remote_state` output reads as `(known after apply)`. Scripts that need it before the first apply should use `terraform console -plan` |
| R14 | At account level, destroying a `databricks_service_principal` only **deactivates** it unless `disable_as_user_deletion = false`; its role and federation policy are deleted. The reference `bootstrap/` now sets it, so a teardown leaves no principal behind |

## End-to-end rebuild (2026-11-13)

After the first teardown, the pipeline's own authentication and then the whole lab were rebuilt from empty state, to check that the reference implementation works in one pass with nothing copied by hand.

| Step | Result |
|---|---|
| Authentication, from `bootstrap/` (run once by administrators) | Pool, provider, apply and plan identities, state bucket, automation principal with account admin and its `main` federation policy: 20 resources. `auth-check`: all three hops passed |
| GCP stack | 27 created: three VPCs, five subnets, three PSC endpoints (all `ACCEPTED`), private zone and response policy, runner VM and NAT |
| Account stack | 15 created: two workspaces through the REST provider (`RUNNING` in 32 s and 62 s), three endpoint registrations, two network configurations (`VALID`), private access settings, the principal's workspace assignment (found by application ID), and six workspace DNS names derived from each workspace's `deployment_name` |
| Workspace stack (self-hosted runner, through the front end) | Cluster policy and a dedicated cluster, `RUNNING` after 4m 51s through the back-end endpoints only |
| Re-plan | GCP and account stacks: **no changes**. Workspace stack: no resource changes |
| Refusal from the internet, as a workspace member | **Refused** (R12). The automation principal, a workspace admin: `200` through the front end, `403` from a GitHub-hosted runner |

## Still open

- Adding back-end PSC to a workspace created without it (scenario A in the PSC design): unverified on GCP.
- Unity Catalog objects at workspace level (storage credentials, external locations, catalogs, grants), H9, H11: not tested.
- ~~Refusal from the internet as a member~~: settled in the rebuild (R12).
- ~~Workspace delete through the REST provider~~: done in the teardown ([E7](E7_TEARDOWN.md)): `DELETE`, polled until 404, then the network configurations.
