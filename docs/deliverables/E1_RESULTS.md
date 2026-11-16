# E1. Results matrix

**2026-11-14, after the end-to-end rebuild and the Entra SSO and AIM tests.** Each hypothesis from the test requirements (H1–H12), its result, and the evidence. Identifiers are placeholders. Evidence references (workflow runs, apply runs, PRs) are to the lab repository; the full record is in [`../TEST_PLAN.md`](../TEST_PLAN.md) §6. Versions throughout: Terraform 1.15.9, Databricks provider 1.142.0, `magodo/restful` 0.25.2, Google provider 8.11.0.

The lab ran with the Databricks account's own-IdP SSO **on** for every test: an OIDC identity provider for the build and the rebuild, then **Microsoft Entra ID SSO with automatic identity management (AIM)** for the use case tests (U0–U7, *Entra SSO and AIM* below). Phases A and B, which need SSO off, did not run (decision D1).

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | The provider with `google_service_account` fails against the account API with SSO on | **Confirmed with Entra SSO** (use case test U0, 2026-11-13) | `first-design` run: the provider with `google_service_account`, for a Google service account that was an active account admin: "cannot read mws workspaces: … Invalid Request" from Databricks after Google minted the ID token. Earlier, on the same account (another CI system): `401 Invalid Request` on every account call after SSO was turned on. Consistent with the Databricks documentation (F2) |
| H2 | A service principal on `github-oidc` reads account APIs with SSO on | **Confirmed** | A plan of `databricks_mws_workspaces` on `github-oidc`: every workspace visible. First attempt failed only on the federation policy's subject format (finding R1). Re-confirmed after the principal and its policy were recreated by Terraform (`bootstrap/`): `auth-check` exchanged the token (200) and the principal read its own record |
| H3 | `databricks_mws_networks` and `databricks_mws_workspaces` fail through the provider on `github-oidc` | **Confirmed**, for create and update | Network configuration create: "cannot create mws networks: Failed to get GCP OAuth access token … provide a GCP service account access token in the X-Databricks-GCP-SA-Access-Token header". Workspace update: "cannot update mws workspaces: BAD_REQUEST: Failed to get GCP OAuth access token …". Workspace create (direct API, no header): `400` with the same message. Reads and imports work |
| H4 | Direct Accounts API calls with the principal's token plus the header succeed | **Confirmed** | Network configuration `POST`: 201. Workspace `POST`: 201, then `RUNNING`. Workspace `PATCH` (with `update_mask`): 200, then `RUNNING`. VPC endpoint registration `POST`: created, endpoints moved to `ACCEPTED`. The Google token came from the pipeline's own workload identity login |
| H5 | The Google identity behind the header needs project permissions but no Databricks identity | **Confirmed** | The header's identity (the pipeline's apply identity) never had a Databricks user or service principal. It held project permissions only |
| H6 | API-created objects can be imported with a clean plan; updates and deletes need the header | **Confirmed**, with the REST provider closing the gap | Import of a network configuration and workspace: "2 imported, 0 changed", then "No changes". Workspace update through the Databricks provider: refused for the header. Through the REST provider with the header: create, update (and back), and delete of a network configuration all worked; plans clean afterwards. Workspace delete through the REST provider, polled until 404: worked in the teardown (E7). Network configuration delete through the Databricks provider: worked **without** the header. One-pass rebuild: every object created by Terraform with no imports, and the next plan showed no changes |
| H7 | Account objects that don't touch a GCP project work through the provider on `github-oidc` | **Confirmed** for private access settings (create, update, delete, public access off), workspace permission assignment of a service principal and of an **Entra group provisioned by AIM** (U3), and lookup of that group by display name. **Not available:** network connectivity configurations ("Feature not enabled for account"; out of scope, the target scenario uses classic compute only). **Not tested:** metastore, metastore assignment, creating account groups (with AIM they come from Entra), ingress policies | U3: `data "databricks_group"` found the group added from Entra; `databricks_mws_permission_assignment` gave it `USER` on the PSC workspace (1 added). A group nested inside it is not visible to the API (R17) |
| H8 | Workspace-level resources work through the provider on `github-oidc` | **Confirmed** for a cluster policy, a cluster, and **entitlements on an Entra group** (`databricks_entitlements`, U4), through Private Service Connect with the workspace's public access off, from a self-hosted runner; also with Entra SSO and AIM on (U2). **Not tested:** Unity Catalog storage credentials, external locations, catalogs, grants | The provider exchanged the GitHub token at the workspace's own token endpoint through the front-end endpoint. Cluster creation needed a dedicated access mode: no isolation is refused in a Unity Catalog workspace. Re-confirmed in the rebuild: the cluster started in 4m 51s through the back-end endpoints |
| H9 | Console creation with matching and non-matching Google accounts | **Not tested** (needs test accounts, decision D2) | |
| H10 | With SSO off, both paths create a workspace | **Prior evidence only, not rerun** (Phase A) | A classic workspace and network configuration were created through the provider with Google ID tokens before SSO was turned on |
| H11 | AIM with Entra on default Google sign-in | **Not tested** (optional). AIM with Entra **SSO** was tested instead, as the use case needs it (U1–U7) | AIM requires Entra SSO on the same tenant (A2 in the AIM assessment) |
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
| R15 | A Databricks account has a **daily limit on workspace creation**. Past it, `POST /workspaces` returns `429` with `RESOURCE_EXHAUSTED: Limit reached for workspace creation. You've hit your daily limit for workspace creation. Please try again in 24 hours.` A teardown and rebuild on the same day, on an account where other work also creates workspaces, can use it up; the error doesn't say the number. Terraform state stays consistent: the next plan holds only what wasn't created. The pipeline's summaries now show the API's message, not just the first line of the error |
| R16 | An Entra service principal synced by AIM keeps its Entra client ID as its Databricks application ID, can hold account admin, and can carry its own service principal federation policy; a GitHub token exchanged against that policy signs in as it. See [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md), U7 |
| R17 | With AIM, a group added to the account from Entra is visible to the account API (with its external ID); a group nested inside it is not; users and member counts appear only once people sign in. Terraform can assign workspaces only to directly added groups. See [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md), U3 |
| R18 | Assigning a group to a workspace at account level (permission assignment, `USER`) lets its members in but gives the group **no entitlement**; in a new workspace the built-in `users` group carries none either. Members then reach the workspace and are refused: "not assigned to the workspace or no Workspace access, Databricks SQL access or Consumer access entitlement". The group needs an entitlement set inside the workspace (`databricks_entitlements`, workspace stack). AIM's membership does reach the workspace: the member's workspace record lists the group. See [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md), U4 |
| R19 | Disabling a person in Entra stops them at Entra's sign-in ("Your account has been locked"), but minutes later the Databricks account record still read `active`. Whether an open session or a personal access token kept working during that window wasn't tested; the AIM page recommends revoking personal access tokens for deactivated users. See [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md), U5 |

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

## Entra SSO and AIM (use case tests, 2026-11-13 and 14)

The target scenario: people sign in through Entra and come from Entra through AIM, while the pipeline keeps a keyless identity of its own. Run on an Enterprise account with Entra SSO, then AIM, turned on; the full record is in [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md).

| Test | Result |
|---|---|
| U0 The original design (the provider signing in as a Google service account), Entra SSO on | **Refused** ("Invalid Request") for a Google service account that was an active account admin (H1) |
| U1 The pipeline's sign-in after the switch to Entra SSO, and with AIM on | **Unaffected**: exchange 200, the native principal still account admin |
| U2 The whole private lab built with Entra SSO and AIM on | **Same results as the rebuild**: GCP 27, account 15, cluster `RUNNING` through the back-end endpoints, `psc-refusal` 200 through the front end and 403 from the internet; the next plans clean. The back-end PSC workspace was held a day by the daily workspace creation limit (R15) |
| U3 An Entra group from AIM, assigned by Terraform | The group added from Entra is visible and assignable by display name; the nested group inside it is not (R17) |
| U4 People sign in through Entra, privately | After the group got the Workspace access entitlement (R18): a direct member and a **nested** member reached the workspace through the front end; a user in neither group was refused. A member signing in from the internet was refused by the workspace after Entra and the account accepted the sign-in |
| U5 A person disabled in Entra | Refused at Entra's sign-in; the pipeline unaffected; the Databricks user still `active` minutes later (R19) |
| U7 An Entra service principal synced by AIM as the pipeline's identity | Application ID = Entra client ID; account admin accepted; its own federation policy accepted; a GitHub Actions job signed in as it (R16). Option B (Entra tokens exchanged by Databricks) not run |

## Still open

- The Entra-owned pipeline principal (option C) through a full build; Entra-issued tokens exchanged by Databricks (option B). See the [AIM assessment](../AIM_ENTRA_ASSESSMENT.md).
- Adding back-end PSC to a workspace created without it (scenario A in the PSC design): unverified on GCP.
- Unity Catalog objects at workspace level (storage credentials, external locations, catalogs, grants), H9, H11: not tested.
- ~~Refusal from the internet as a member~~: settled in the rebuild (R12).
- ~~Workspace delete through the REST provider~~: done in the teardown ([E7](E7_TEARDOWN.md)): `DELETE`, polled until 404, then the network configurations.
