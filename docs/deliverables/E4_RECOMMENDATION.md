# E4. Recommendation

**2026-11-14, after the end-to-end rebuild and the Entra SSO and AIM tests.**

## Recommendation: Terraform for everything, with a REST provider for the objects that need the Google token header

Manage the whole Databricks on GCP deployment from GitHub Actions with Terraform and keyless federation, SSO left on:

- **The Databricks provider** (`databricks/databricks`, auth `github-oidc`) for every object it can manage on federation: private access settings, permission assignments, and everything inside workspaces.
- **A generic REST provider** (`magodo/restful`) for the three objects the Databricks provider can't create or update with own-IdP SSO: **network configurations, VPC endpoint registrations, and workspaces**. It calls the same Accounts API with the automation principal's Databricks token and the apply identity's Google access token in `X-Databricks-GCP-SA-Access-Token` (H3, H4).
- **Both tokens as Terraform ephemeral variables**, minted in the job step that runs Terraform: never in a plan file, state, or log.
- **Private Service Connect with the back end from creation** (scenario B in the PSC design) and the front end added once users' DNS is ready.
- **Two runner tiers**: GitHub-hosted runners for GCP and account-level stacks (the account API is public); a self-hosted runner inside the network for workspace-level stacks once the workspace's public access is off.

**With Entra ID for people** (the customer's target; tested, [USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md)):

- **Turn on Entra SSO and AIM.** The pipeline above is unaffected by either (U1) and builds the whole private deployment with both on (U2).
- **Workspace access by Entra group, in Terraform:** add each group to the account from Entra, then assign it to workspaces (account stack) **and** give it an entitlement in each workspace (workspace stack). Without the entitlement, members are refused (R18). Nested groups work for membership but can't be managed by Terraform (R17).
- **People reach private workspaces only through the front end;** a group member signing in from the internet was refused by the workspace after Entra and the account had accepted the sign-in (U4).
- **Leavers:** disable in Entra and revoke their personal access tokens and sessions in Databricks; the Databricks user isn't deactivated straight away (R19).
- **The pipeline's Databricks identity:** keep the Databricks-native principal (proven end to end, outside the directory), or, if identities must be owned in Entra, an Entra service principal synced by AIM with the same GitHub federation policy (option C, proven at account level; run one full build with it before adopting). The original design, the provider signing in as a Google service account, is refused under Entra SSO (U0).

None of the requirements' options O1–O4 as written. This is O2 (Accounts API calls with both tokens) carried inside Terraform, so nothing is imported by hand and plans stay authoritative.

## Why not the others

| Option | Verdict |
|---|---|
| O1: console for workspaces and endpoints | Unnecessary: every console step was done by the pipeline. It also needs a person with matching Google and IdP identities (F8, H9 untested) |
| O2: scripted API calls, then `terraform import` | Works (C4, C6), but splits each change across a script and an import and leaves drift windows. The REST provider does the same calls inside the plan |
| O3: create objects before turning SSO on | Only helps once; every later workspace needs another path |
| O4: Google sign-in federated to Entra | Changes how every user signs in to solve a CI problem the REST provider solves |
| O5: SSO off per run | Not considered: it locks out every other user for the window (F1, F12) |
| The original design: a Google service account as Databricks account admin, the provider on `google_service_account` (the Platform Deployment Kit's pattern) | Refused under own-IdP SSO, also for an account admin (U0, H1) |

## Steps outside Terraform, and how often

| Step | Owner | Frequency |
|---|---|---|
| Domain restricted sharing exception and narrowed profile for each workspace project (R2, R3) | Organization policy administrators | Once per workspace project |
| The pipeline's authentication: workload identity pool, apply and plan identities, state bucket, automation principal, account admin, federation policy (R1) | GCP and Databricks administrators | Once per repository; Terraform (`bootstrap/`) applied locally |
| Self-hosted runner registration | Repository admin | Once per runner, or automated with a GitHub App |
| Entra SSO and AIM on the account | Databricks account admin, Entra administrator | Once |
| Adding each Entra group to the account from Entra | Databricks account admin (account console) | Once per group, before Terraform can assign it |
| Revoking a leaver's tokens and sessions in Databricks | Workspace admins | Per leaver (R19) |

Per workspace, nothing is manual: network configuration, endpoints and their registration, private access settings, the workspace, its DNS, group assignments and entitlements, and workspace-level objects are all in Terraform.

## Risks and how to carry them

| Risk | Mitigation |
|---|---|
| `magodo/restful` is a community provider (0.x), signed by its author's key | Pin the exact version with checksums in the lock file; read its changelog before upgrading; keep its use to three resource types |
| The REST provider's model is the raw API: async status, `update_mask`, one network configuration per workspace | Encoded once in the module (polling on `workspace_status`, a static `update_mask` naming the fields a change touches) |
| Terraform ordering when detaching and deleting in one apply (R6) | Detach in one apply, delete in the next; or `create_before_destroy` on objects a workspace references |
| The Databricks provider gains header support (issue #5999) | Move the three resources back with `removed` and `import` blocks; no rebuild |
| Self-hosted runners widen what the network trusts | Ephemeral runners, a dedicated unprivileged user, a label only the workspace workflow uses, no inbound route, egress through NAT only |
| A group assigned without an entitlement: members reach the workspace and are refused (R18) | Assign and entitle in the same change; one module or one variable per group covering both stacks |
| A person disabled in Entra keeps working tokens for a while (R19) | Leaver procedure includes revoking tokens and sessions in Databricks; prefer short-lived OAuth over personal access tokens |
| AIM provisions lazily: users at first sign-in, groups and principals only when added from Entra | Add groups from Entra before the Terraform change that assigns them; refer to principals by application ID |
| The account's daily workspace creation limit (R15) | Spread large rollouts and rebuilds across days; state stays consistent, so a refused apply resumes with a fresh plan |
| Tenant policies (MFA registration, Conditional Access) apply to Databricks sign-in | Plan exclusions or registration for test identities; the pipeline's principals don't sign in through Entra and aren't affected |

## Verified

Everything in [E2](E2_CAPABILITIES.md) marked ✅, from a pipeline on federation with SSO on, and then the whole design end to end ([E1](E1_RESULTS.md), *End-to-end rebuild*):

- the pipeline's authentication recreated from `bootstrap/` and checked hop by hop;
- the lab torn down through the pipeline (workspace delete through the REST provider) and rebuilt in one pass from empty state, with no imports and no hand-copied identifiers; the next plans showed no changes;
- clusters on back-end PSC only, workspace-level Terraform through the front end, and the workspace refused from the internet to one of its own admins.

Then on Entra SSO with AIM ([E1](E1_RESULTS.md), *Entra SSO and AIM*): the pipeline unaffected and the whole private deployment rebuilt with both on; people signing in privately through Entra with access from Entra groups, nested groups included, and others refused; a disabled person blocked without touching the pipeline; an Entra service principal synced by AIM signing in as the pipeline's identity.

Not verified: adding back-end PSC to an existing workspace, Unity Catalog objects at workspace level, the Entra-owned pipeline principal through a full build, and Entra-issued tokens for the pipeline (option B).
