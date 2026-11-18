# Databricks on GCP from GitHub Actions: keyless Terraform with own-IdP SSO and Private Service Connect

Reference implementation and test record for building **classic-compute Databricks workspaces on Google Cloud** from a **GitHub Actions** pipeline with **Terraform**, when:

- the Databricks account's single sign-on uses its **own identity provider** (so Google ID tokens no longer work against the account API);
- workspaces are created in **least-privilege mode (LPM)** so the apply identity does not need `compute.firewalls.create` / `update` or `compute.networks.updatePolicy` ([LPM + Entra](docs/LPM_ENTRA.md));
- workspaces are reached **privately**, with Private Service Connect front end and back end;
- the pipeline holds **no keys or stored secrets**: every job exchanges GitHub's OIDC token for short-lived Google and Databricks credentials.

The lab ran on 2026-11-12 and 2026-11-13, was rebuilt from empty state in one pass to validate the whole design, and was then deleted. It was built once more, in a new project, on 2026-11-13 and 14, on an account with Microsoft Entra ID SSO and automatic identity management, to test the target scenario ([use case results](docs/USE_CASE_RESULTS.md)), and deleted again. Everything needed to run it again is here: **[docs/REPRODUCE.md](docs/REPRODUCE.md)**. The `tfvars` files hold placeholders, and every workflow job that signs in skips itself until the repository variables from `bootstrap/` are set.

## What was found

The Databricks Terraform provider, authenticated by GitHub OIDC federation, can't create **network configurations or VPC endpoint registrations**, or create or update **workspaces**, on an account with its own IdP: those Accounts API calls need a Google access token in the `X-Databricks-GCP-SA-Access-Token` header, which the provider sends only with Google ID token authentication. [Provider issue #5999](https://github.com/databricks/terraform-provider-databricks/issues/5999) reports this for network configurations; the lab saw it for workspaces too, and endpoint registrations failed the same way in earlier tests on the same account. A generic REST provider ([`magodo/restful`](https://registry.terraform.io/providers/magodo/restful/latest)) sends both tokens, as ephemeral values that never reach a plan file or state, so those objects stay in Terraform too. The rest of what the lab built (private access settings, permission assignments, a cluster policy, a cluster and group entitlements) works through the Databricks provider.

**With Microsoft Entra ID SSO and automatic identity management** (the target scenario, [use case results](docs/USE_CASE_RESULTS.md); SSO with your own identity provider is in Public Preview on GCP): the pipeline is unaffected and built the whole private deployment; people sign in through Entra over Private Service Connect and get workspace access from Entra groups, nested groups included, once Terraform both assigns the group and gives it an entitlement (R18); a person disabled in Entra is blocked at sign-in, though their Databricks user still read active minutes later (R19). The pipeline's own identity can also be an Entra service principal synced by AIM (R16), shown at account level and not yet through a full build. The original design, the provider signing in as a Google service account, is refused under Entra SSO.

| Hypothesis (from the [test requirements](docs/DATABRICKS_SSO_TEST_REQUIREMENTS.md)) | Result |
|---|---|
| H1 Provider with `google_service_account` fails with SSO on | **Confirmed with Entra SSO** (use case test U0): refused for an account admin |
| H2 A principal on `github-oidc` reads account APIs with SSO on | **Confirmed** |
| H3 Network configurations and workspaces fail through the provider | **Confirmed** for create and update |
| H4 Accounts API with the principal's token plus the header succeeds | **Confirmed**: network configuration, workspace create and update, endpoint registration |
| H5 The header's Google identity needs no Databricks identity | **Confirmed** |
| H6 API-made objects import cleanly; updates and deletes need the header | **Confirmed**; the REST provider closes the gap (create, import, update, delete) |
| H7 Account objects that touch no GCP project work through the provider | **Confirmed** for private access settings and permission assignment; others not tested |
| H8 Workspace-level resources work through the provider | **Confirmed** for a cluster policy and a cluster, through PSC with public access off; Unity Catalog objects not tested |
| H9 Console creation with matching and non-matching Google accounts | Not tested |
| H10 With SSO off, both paths create a workspace | Prior evidence only, not rerun |
| H11 Automatic identity management with Entra on Google sign-in | Not tested (optional) |
| H12 Private access settings and endpoint registration need the header | **Split**: private access settings don't, endpoint registration does |

Beyond the hypotheses: nineteen findings (R1–R19), from GitHub's immutable-ID OIDC subject to the firewall rule a deleted workspace leaves behind, each with its effect on the configuration guide. The full matrix, evidence and findings: **[E1 results](docs/deliverables/E1_RESULTS.md)**.

## Documents

| Document | What it is |
|---|---|
| [Use case](docs/USE_CASE.md) | The scenario behind the test: Entra SSO and AIM for people, a pipeline identity outside Entra. The first design, why it breaks, what the lab proved for it, and the tests that answered it (U0–U7) |
| [Use case test plan](docs/USE_CASE_TEST_PLAN.md) | U0–U7: the use case on an account with Entra SSO and AIM, the lab's pipeline unchanged; prerequisites, changes, teardown, cost |
| [Use case results](docs/USE_CASE_RESULTS.md) | Status of U0–U7: what's proven on Entra SSO and AIM, findings R15–R19, what's left |
| [Published deliverables](docs/site/) | The deliverables as pages: [E1–E7](docs/site/index.html), the [Entra test status](docs/site/status.html), the [AIM assessment](docs/site/aim-assessment.html). Built from the markdown by `docs/site/build.py` |
| [Test requirements](docs/DATABRICKS_SSO_TEST_REQUIREMENTS.md) | The question, public facts F1–F12, hypotheses H1–H12, the planned phases. Written before testing |
| [Test plan and step log](docs/TEST_PLAN.md) | How each step ran and what it returned, step by step |
| [E1 Results](docs/deliverables/E1_RESULTS.md) | Each hypothesis, its result and evidence; findings R1–R19; the end-to-end rebuild |
| [E2 Capabilities](docs/deliverables/E2_CAPABILITIES.md) | What works through which provider, per object, and what stays outside Terraform |
| [E3 Identity design](docs/deliverables/E3_IDENTITY.md) | Every identity, what it trusts and holds; the authentication sequence diagram |
| [E4 Recommendation](docs/deliverables/E4_RECOMMENDATION.md) | The recommended approach, the alternatives, and the risks |
| E5 Reference implementation | This repository |
| [E6 Configuration guide](docs/deliverables/E6_CONFIGURATION_GUIDE.md) | End to end, in build order, with the architecture diagram |
| [E7 Teardown record](docs/deliverables/E7_TEARDOWN.md) | Both teardowns and the final deletion |
| [Entra identity for the pipeline, with AIM](docs/AIM_ENTRA_ASSESSMENT.md) | Desk assessment: an Entra service principal synced by AIM as the pipeline's Databricks identity (options A, B, C) |
| [Authentication bootstrap](docs/AUTH_BOOTSTRAP.md) | How GitHub Actions authenticates to Google and Databricks, hop by hop |
| [Private Service Connect scenarios](docs/PSC_SCENARIOS.md) | Front end only versus back end from creation |
| [End-to-end rebuild plan](docs/E2E_REBUILD_PLAN.md) | The teardown-and-rebuild that validated the design |
| [Reproduce](docs/REPRODUCE.md) | The runbook to build it again |

Run and pull request numbers in the documents refer to the original lab repository, which stays private.

## Repository layout

| Path | Terraform root | State prefix | Runs as |
|---|---|---|---|
| `bootstrap/` | The pipeline's authentication: Google workload identity pool and provider, apply and plan identities, state bucket; the Databricks automation principal and its federation policy | administrators' own bucket | Administrators, locally, once |
| repository root (`main.tf`, `psc.tf`, `frontend.tf`, `testvm.tf`) | GCP: VPCs, PSC endpoints, private DNS zone and response policy, the self-hosted runner VM and NAT | `terraform/test` | `gha-apply` on `main`; `gha-plan` (read-only) on pull requests |
| `databricks/` | Databricks account: endpoint registrations, network configurations, private access settings, workspaces (REST provider), permission assignment, workspace DNS names | `terraform/databricks` | The automation principal on `github-oidc`, `main` only, plus `gha-apply`'s Google token |
| `first-design/` | Use case test U0 only: the first design's provider sign-in, read only, no state | none | The apply identity, through the provider's `google_service_account` |
| `workspace/` | Inside a workspace: a cluster policy and a cluster; entitlements for Entra groups (`entitlements.tf`) | `terraform/workspace` | The automation principal, from the self-hosted runner, through the front-end endpoint |
| `examples/entra/` | Example, not a pipeline stack: Entra groups for workspace access, the Entra-owned pipeline principal (option C), option B (untested) | administrators' own bucket | An Entra administrator and a Databricks account admin, locally |

Workflows (`.github/workflows/`):

- **`terraform`**: on pull requests and pushes to `main`: `fmt`, `validate`, Trivy, then plans. Pull requests plan the GCP stack read-only; `main` plans both stacks and keeps each plan as an artifact. A manual run with **destroy** plans the teardown.
- **`apply`**: manual. Replays a reviewed plan from a given `terraform` run; refuses anything but a successful push-to-main run whose commit `main` has moved past only with documentation.
- **`workspace`**: manual, on the self-hosted runner: the workspace stack, plan or plan and apply.
- **`auth-check`**: manual. Shows each hop of the authentication chain without printing a credential.
- **`psc-refusal`**: manual. The same identity and steps from inside the network and from the internet: shows the workspace refusing internet access to its own admin.
- **`first-design`**: manual. The use case's first design (provider with `google_service_account`), to show it refused with own-IdP SSO on (U0).
- **`aim-check`**: manual, read only. What AIM put in the account as the pipeline sees it: groups, workspace assignments, test users (U3, U5).
- **`workspace-identity-check`**: manual, read only, on the self-hosted runner. How the workspace sees a user: its groups and the groups' entitlements (U4).
- **`databricks-probe`**: manual. The test steps that weren't Terraform (direct API calls with and without the header).

Every action is pinned to a commit SHA; provider versions are pinned in the lock files (Terraform 1.15.9, Databricks provider 1.142.0, `magodo/restful` 0.25.2, Google provider 8.11.0 when tested).

## Limits of a private repository on the free plan

GitHub doesn't offer branch protection or environment approvals for private repositories on the free plan, so in the lab whoever could push to `main` could use the apply identity, and the manual gate was a `workflow_dispatch`. In a public repository, or a private one on GitHub Enterprise, bind the apply identity and the Databricks federation policy to a GitHub environment with required reviewers instead of the branch. GitHub Pro and GitHub Team add branch protection and deployment branch rules to private repositories, but not required reviewers.

## Cost while built

The three PSC endpoints, about $0.01 an hour each; the runner VM (e2-small) and Cloud NAT, about $1.25 a day, only while the workspace stack is in use; clusters while they run (the policy terminates them after 20 idle minutes); a few small buckets Databricks creates per workspace. Actions minutes come from the repository's allowance.

## License

[MIT](LICENSE).
