# E4. Recommendation

**2026-11-13, after the end-to-end rebuild.**

## Recommendation: Terraform for everything, with a REST provider for the objects that need the Google token header

Manage the whole Databricks on GCP deployment from GitHub Actions with Terraform and keyless federation, SSO left on:

- **The Databricks provider** (`databricks/databricks`, auth `github-oidc`) for every object it can manage on federation: private access settings, permission assignments, and everything inside workspaces.
- **A generic REST provider** (`magodo/restful`) for the three objects the Databricks provider can't create or update with own-IdP SSO: **network configurations, VPC endpoint registrations, and workspaces**. It calls the same Accounts API with the automation principal's Databricks token and the apply identity's Google access token in `X-Databricks-GCP-SA-Access-Token` (H3, H4).
- **Both tokens as Terraform ephemeral variables**, minted in the job step that runs Terraform: never in a plan file, state, or log.
- **Private Service Connect with the back end from creation** (scenario B in the PSC design) and the front end added once users' DNS is ready.
- **Two runner tiers**: GitHub-hosted runners for GCP and account-level stacks (the account API is public); a self-hosted runner inside the network for workspace-level stacks once the workspace's public access is off.

None of the requirements' options O1–O4 as written. This is O2 (Accounts API calls with both tokens) carried inside Terraform, so nothing is imported by hand and plans stay authoritative.

## Why not the others

| Option | Verdict |
|---|---|
| O1: console for workspaces and endpoints | Unnecessary: every console step was done by the pipeline. It also needs a person with matching Google and IdP identities (F8, H9 untested) |
| O2: scripted API calls, then `terraform import` | Works (C4, C6), but splits each change across a script and an import and leaves drift windows. The REST provider does the same calls inside the plan |
| O3: create objects before turning SSO on | Only helps once; every later workspace needs another path |
| O4: Google sign-in federated to Entra | Changes how every user signs in to solve a CI problem the REST provider solves |
| O5: SSO off per run | Not considered: it locks out every other user for the window (F1, F12) |

## Steps outside Terraform, and how often

| Step | Owner | Frequency |
|---|---|---|
| Domain restricted sharing exception and narrowed profile for each workspace project (R2, R3) | Organization policy administrators | Once per workspace project |
| The pipeline's authentication: workload identity pool, apply and plan identities, state bucket, automation principal, account admin, federation policy (R1) | GCP and Databricks administrators | Once per repository; Terraform (`bootstrap/`) applied locally |
| Self-hosted runner registration | Repository admin | Once per runner, or automated with a GitHub App |

Per workspace, nothing is manual: network configuration, endpoints and their registration, private access settings, the workspace, its DNS, and workspace-level objects are all in Terraform.

## Risks and how to carry them

| Risk | Mitigation |
|---|---|
| `magodo/restful` is a community provider (0.x), signed by its author's key | Pin the exact version with checksums in the lock file; read its changelog before upgrading; keep its use to three resource types |
| The REST provider's model is the raw API: async status, `update_mask`, one network configuration per workspace | Encoded once in the module (polling on `workspace_status`, a static `update_mask` naming the fields a change touches) |
| Terraform ordering when detaching and deleting in one apply (R6) | Detach in one apply, delete in the next; or `create_before_destroy` on objects a workspace references |
| The Databricks provider gains header support (issue #5999) | Move the three resources back with `removed` and `import` blocks; no rebuild |
| Self-hosted runners widen what the network trusts | Ephemeral runners, a dedicated unprivileged user, a label only the workspace workflow uses, no inbound route, egress through NAT only |

## Verified

Everything in [E2](E2_CAPABILITIES.md) marked ✅, from a pipeline on federation with SSO on, and then the whole design end to end ([E1](E1_RESULTS.md), *End-to-end rebuild*):

- the pipeline's authentication recreated from `bootstrap/` and checked hop by hop;
- the lab torn down through the pipeline (workspace delete through the REST provider) and rebuilt in one pass from empty state, with no imports and no hand-copied identifiers; the next plans showed no changes;
- clusters on back-end PSC only, workspace-level Terraform through the front end, and the workspace refused from the internet to one of its own admins.

Not verified: adding back-end PSC to an existing workspace, and Unity Catalog objects at workspace level.
