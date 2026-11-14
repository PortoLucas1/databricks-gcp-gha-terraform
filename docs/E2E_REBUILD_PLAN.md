# End-to-end rebuild plan

**Done, 2026-11-13** (results in [E1](deliverables/E1_RESULTS.md), *End-to-end rebuild*, and [E7](deliverables/E7_TEARDOWN.md)). The plan as written before the run: Tear the lab down, then rebuild it from an empty state in one pass, to validate that what was built incrementally works as a whole and that the reference implementation (E5) needs no hand-copied identifiers. The teardown also produces E7 and tests the deletes not yet covered (workspace delete through the REST provider).

## 0. Order (revised)

1. **Destroy path** (PR #21): a `destroy` run of the plan workflow, delete polling for REST-provider workspaces, the finished `import` and `removed` blocks removed. Merged before the teardown.
2. **Teardown** (§2) with the configuration as it is.
3. **Auth recreation** (PR #23, [AUTH_BOOTSTRAP.md](AUTH_BOOTSTRAP.md)): retire the old pool, identities, state bucket and Databricks principal; apply `bootstrap/` locally; set the six repository variables; merge, which lets a run on `main` create the empty states; run **auth-check**. Done 2026-11-13: all three hops passed.
4. **One-pass build** (PR "one-pass build", §1), merged **after** the teardown and the auth recreation: changing the layout of a live lab would mean moving objects between providers (`removed` plus `import`) only to delete them.
5. **Rebuild** (§3).

## 1. What has to change for one pass

The lab was built step by step, and some values were copied from one run into the next. A clean build can't depend on them.

| Today | Change | Why |
|---|---|---|
| `gha-test-classic` was created by the probe and imported (`import` blocks, `network_id` / `workspace_id` in `databricks/envs/test.tfvars`) | Drop the imports; create scenario A's network configuration and workspace with the REST provider like scenario B's | The rebuild creates everything; no probe step |
| Workspace DNS records hard-code deployment names (`psc.tf`, `frontend.tf`) | Move the workspace-specific records into the account stack (the Google provider beside the REST provider, as the apply identity), keyed on each workspace's `deployment_name` output | The account stack is where the names become known, so one pass builds them |
| `workspace/envs/test.tfvars` hard-codes the workspace URL | Read it from the account stack's state (`terraform_remote_state`, same bucket) | Same |
| `automation_principal_id` hard-coded | `data "databricks_service_principal"` by application ID (`DATABRICKS_CLIENT_ID`) | No IDs in the repository |
| Project, project number, bucket and pool in workflow files and tfvars | Repository variables (decision D4) | Sanitized reference implementation |
| `restful_resource.workspace*` have no delete polling | `poll_delete` on `body.workspace_status` (or `code` 404) | A network configuration can't be deleted while its workspace is still deleting |
| No destroy path in the pipeline | A `destroy` choice on the plan workflow (`plan -destroy`, same artifact and manual apply) | Teardown through the pipeline, reviewed like any apply |
| Private access settings referenced by both workspaces | Keep; teardown detaches nothing (workspaces go first) | R6 |
| The self-hosted runner is registered by hand | Keep for the lab (`scripts/register-runner.sh`); document the GitHub App alternative | A runner registration token can't come from the pipeline without a stored credential |

These land as one pull request, merged after the teardown, when every stack's state is empty: its plans then show the whole lab to create. Status: the one-pass PR covers the first five rows (scenario A's network configuration and workspace on the REST provider, workspace DNS in the account stack, the workspace URL from remote state, the principal from a data source); delete polling and the destroy path are in PR #21. Repository variables for the GCP identifiers (sanitization) came with the auth recreation (PR #23).

## 2. Teardown (E7)

Every destroy is a reviewed plan applied by hand. Order:

1. **Workspace stack:** `plan -destroy`: the test cluster, the cluster policy. Runner needed: re-enable the VM and NAT for this step, or remove these from state if the workspace goes anyway (they die with it).
2. **Account stack:** `plan -destroy`: workspaces (REST provider `DELETE`, polled), then network configurations and endpoint registrations, permission assignment, private access settings. **Tests workspace delete through the REST provider.**
3. **GCP stack:** `plan -destroy`: endpoints, DNS, VPCs, VM, NAT, bucket. Leaves the project, its pool, identities and state bucket (bootstrap's).
4. **Leftovers outside Terraform**, by hand, recorded: buckets, custom roles and grants left by the failed first workspace attempt (`databricks-<id>`, `-system`, `-unitycatalog`); any buckets the deleted workspaces leave; the offline runner registration in GitHub.
5. **Check:** account lists show no `gha-test-*` workspaces, networks, endpoints or private access settings; the project has no compute, endpoints or DNS.

Not torn down: the CI project and its identities, the DRS exception and profile (the organization's), the automation principal and its federation policy. The rebuild uses them. (The identities, the state bucket and the principal were then recreated from `bootstrap/` on purpose, to test that path; see §0.) They go at the final teardown, in that order, with SSO left as it is (the account is shared).

## 3. Rebuild, one pass

| Step | Runs | Expect |
|---|---|---|
| 1 | Merge; plans for each stack on `main` | GCP and account stacks plan everything; no errors |
| 2 | `apply` GCP | VPCs (scenario A, scenario B, users'), endpoints `PENDING`, compute-plane zone, users' response policy, runner VM and NAT |
| 3 | `apply` account | Endpoints registered and `ACCEPTED`; network configurations; private access settings; both workspaces `RUNNING`; workspace DNS records; principal workspace admin |
| 4 | Register the runner (person) | Runner online, label `gha-test-fe` |
| 5 | `workspace` with apply | Cluster policy; cluster `RUNNING` in the back-end PSC VPC |
| 6 | Plans again for every stack | **No changes** |
| 7 | Checks | As E6 §8; the refusal from the internet, as the automation principal from a GitHub-hosted runner (a member of the workspace), settles the open item |
| 8 | Scale down | Runner VM and NAT off; the cluster auto-terminates |

## 4. Cost

| Item | Rate | Rebuild window (about 3 hours) |
|---|---|---|
| Three PSC endpoints | about $0.03/hour | about $0.10 |
| Runner VM (e2-small) and NAT | about $0.02/hour | under $0.10 |
| Test cluster (n2-standard-4, single node, 20-minute auto-termination) | about $0.50–1/hour | about $0.50 |
| **Total** | | **about $1** |

Between teardown and rebuild the lab costs nothing beyond the bootstrap's state bucket.
