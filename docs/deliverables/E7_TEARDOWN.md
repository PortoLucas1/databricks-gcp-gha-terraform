# E7. Teardown record

**2026-11-13.** Three teardowns: the first before the end-to-end rebuild, the second after it, and the use case's after the Entra SSO and AIM tests (2026-11-14). Every Terraform destroy was a reviewed plan from the pipeline, applied by hand.

## Use case teardown, after the Entra SSO and AIM tests (2026-11-14)

The second build, in a new project, with Entra SSO and AIM on the account ([USE_CASE_RESULTS.md](../USE_CASE_RESULTS.md)). Same order as the final teardown below, plus the identities AIM brought in.

| # | Step | Result |
|---|---|---|
| 1 | `terraform` run with **destroy**; `apply`, account stack | **16 destroyed**: the 15 of the build plus the Entra group's workspace assignment. Both workspaces gone |
| 2 | By hand (R10) | The two `db-<vpc>-<region>-ingress` firewall rules and the six workspace buckets |
| 3 | `apply`, GCP stack, same destroy run | Everything destroyed; the project held only the state bucket |
| 4 | Entra test objects (with `az`) | Three users, two groups, the Entra app registration of the U7 pipeline principal. The tenant's MFA exclusion group lost its test members with them. **The synced principal was gone from the Databricks account**, with its federation policy, right after its Entra app was deleted, without being deleted there. The users and the group were still in the account |
| 5 | Databricks test identities (CLI) | The three users AIM created at first sign-in and the Entra group added to the account: deleted. They stay in the account after a workspace and the Entra objects are gone, so they need removing |
| 6 | `bootstrap/` destroyed (after emptying the state bucket) | 20 destroyed; **the automation principal deleted outright**, not deactivated (R14's fix) |
| 7 | The project retired by the organization's infrastructure Terraform (two changes, as for the first project) | DRS policies and the plan identity's reads off, the project set to `DELETE`, then the project deleted and the single-project DRS constraint removed. Recoverable for 30 days |
| 8 | The account's SSO back to the identity provider it had before the test | Done by the account admins: the previous identity provider, with AIM re-enabled, as before the test |

## Final teardown, after the rebuild

With R10 known, the leftovers were removed between the two stacks, and the whole teardown took one destroy run.

| # | Step | Result |
|---|---|---|
| 1 | `terraform` run with **destroy** | Account stack: 15 to destroy. GCP stack: 24 to destroy (the runner VM and NAT were already off) |
| 2 | `apply`, account stack | **15 destroyed** in 1 minute: both workspaces through the REST provider (polled until 404), both network configurations, three endpoint registrations, private access settings, the principal's workspace assignment, and the six workspace DNS names the account stack had created |
| 3 | By hand, outside Terraform (R10) | The two `db-<vpc>-<region>-ingress` firewall rules and the six workspace buckets (`databricks-<id>`, `-system`, `-unitycatalog` for each workspace) |
| 4 | `apply`, GCP stack, **from the same destroy run** | **24 destroyed**, VPCs included. The two stacks keep separate states, so applying one didn't make the other's plan stale |
| 5 | Check | Project: no networks, firewall rules, endpoints, addresses, VMs, routers, DNS zones or response policies; one bucket, the state bucket. Account: no `gha-test` workspaces, network configurations, endpoint registrations or private access settings |

The workspace stack wasn't destroyed: its cluster policy and cluster went with the workspace, so its state names two objects that no longer exist. Left in the project besides `bootstrap/`'s objects: Databricks' three custom roles and the `databricks-compute` service account that provisioning created for cluster nodes.

### Deleting what held the lab up

After the final teardown, everything else the lab used was deleted; the repository stays as the reference implementation, with placeholders and a runbook (`docs/REPRODUCE.md`).

| Step | Result |
|---|---|
| The stacks' state files, then `bootstrap/` destroyed locally | 20 destroyed: the workload identity pool and provider, both identities and their grants, the state bucket, the automation principal's role and federation policy. **The principal itself was only deactivated** (R14); deleted afterwards by an account admin |
| Repository variables and the runner registration | Deleted; every job that signs in now skips itself until the variables are set again |
| The project's DRS exception and pattern policy, the plan identity's reads | Removed through the organization's infrastructure Terraform |
| The project | Deleted through the organization's infrastructure Terraform (`deletion_policy` set to `DELETE` in one apply, the project removed in the next). Recoverable for 30 days; Databricks' custom roles and service account went with it |
| The org-level DRS constraint used only by this project | Deleted |

SSO on the Databricks account was left on throughout: the account is shared, and no test IdP app or tenant was created (decision D2), so the requirements' step of turning SSO off before deleting the IdP app didn't apply.

## First teardown, before the rebuild

### Order and results

| # | Step | Result |
|---|---|---|
| 1 | `terraform` run with **destroy** (both stacks planned `-destroy`) | Account stack: 9 to destroy. GCP stack: 30 to destroy |
| — | A first destroy apply was refused: **"Saved plan is stale"**. Another run's plan had been applied to the account stack after the destroy was planned | Nothing deleted. Lesson: during a teardown, apply only the newest destroy run, and nothing else in between |
| 2 | New destroy run; `apply`, account stack | **0 added, 0 changed, 9 destroyed**: both workspaces (REST provider `DELETE`, polled until 404), both network configurations (one through the REST provider, one through the Databricks provider, **without the header**), three VPC endpoint registrations, private access settings, the principal's workspace assignment |
| 3 | `apply`, GCP stack | Failed on two VPCs: "The network resource … is already being used by … `db-<vpc>-<region>-ingress`". Everything else destroyed |
| 4 | By hand (outside Terraform): the two `db-…-ingress` firewall rules; nine workspace buckets (`databricks-<id>`, `-system`, `-unitycatalog` for three workspaces, one from a failed attempt) | Deleted |
| 5 | New destroy run; `apply`, GCP stack | The two VPCs destroyed |
| 6 | Check | No VPCs, firewall rules, endpoints, VMs, DNS zones or response policies in the project; only the state bucket. Account: no `gha-test` workspaces, network configurations, endpoint registrations or private access settings |

The workspace stack (a cluster policy, a terminated cluster) wasn't destroyed: its objects went with the workspace. Its state still names them; the next refresh drops them.

### Left in place

| Object | Why |
|---|---|
| Three Databricks custom roles in the project, and grants to the deleted workspaces' service accounts | Created by Databricks; new workspaces reuse the roles, and grants to deleted accounts are inert |
| The CI project, its workload identity pool and identities, the state bucket | Bootstrap; the rebuild uses them (or recreates them: see the rebuild plan) |
| The domain restricted sharing exception and profile on the project | Organization prerequisite |
| The automation service principal and its federation policy | Account prerequisite |

## Finding

**R10.** Deleting a classic workspace leaves Databricks-created objects in the workspace project: an ingress firewall rule on the workspace's VPC (`db-<vpc>-<region>-ingress`), the workspace's three buckets, three custom roles and their grants. The firewall rule **blocks deleting the VPC**. A teardown needs a cleanup step between the account stack's destroy and the GCP stack's: delete the firewall rule (and, by decision, the buckets, which hold the workspace's system data and default catalog storage). Provisioning also creates a `databricks-compute` service account in the project for cluster nodes, which stays after the workspaces are gone.
