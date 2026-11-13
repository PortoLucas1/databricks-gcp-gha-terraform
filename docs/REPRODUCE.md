# Reproduce the lab end to end

The lab ran from 2026-11-12 to 2026-11-13 and was then deleted: its project, the pipeline's identities, and the Databricks principal. This repository keeps the reference implementation (deliverable E5). This runbook rebuilds the lab in a new project, in order. Results to compare against are in [deliverables/E1_RESULTS.md](deliverables/E1_RESULTS.md) (*End-to-end rebuild*).

Placeholders: `<project-id>` (the workspace project, which here also holds the pipeline's identities), `<admin-bucket>` (a state bucket the administrators already have), `<owner>`, `<owner-id>`, `<repo>`, `<repo-id>` (GitHub; the IDs are numeric), `<account-id>` (Databricks), `<profile>` (a Databricks CLI profile on the account console, as an account admin).

Find the GitHub numeric IDs with `curl -s https://api.github.com/repos/<owner>/<repo>` (`owner.id` and `id`; a private repository needs a token).

## 0. Prerequisites outside this repository

| What | Who | Notes |
|---|---|---|
| A GCP project for the lab, with billing | GCP administrator | The pipeline's apply identity becomes its owner |
| Domain restricted sharing exception for Databricks' Google customer ID, narrowed to the four provisioning grants | Organization policy administrator | Only if the organization restricts `iam.allowedPolicyMemberDomains` (R2, R3; the configuration guide, §1.3) |
| A Databricks account on GCP; an account admin to run the bootstrap | Databricks account admin | SSO on the account can stay on |
| A GitHub repository with this code, Actions enabled | Repository admin | On the free plan, `main` is the only gate (see the README) |

## 1. The pipeline's authentication (`bootstrap/`, once, locally)

1. Fill in `bootstrap/envs/test.tfvars`.
2. Sign in: `gcloud auth application-default login`, and `databricks auth login --host https://accounts.gcp.databricks.com --account-id <account-id>` saved as `<profile>`.
3. Apply:
   ```bash
   terraform -chdir=bootstrap init -backend-config="bucket=<admin-bucket>" -backend-config="prefix=<path>/gha-bootstrap"
   ```
   ```bash
   terraform -chdir=bootstrap apply "-var-file=envs/test.tfvars"
   ```
   (In PowerShell, keep the quotes around `-var-file=…`.) Expect 20 resources: the pool, provider, both identities and their grants, APIs, the state bucket, and the automation principal with `account_admin` and its federation policy.
4. Set the repository variables (Settings → Secrets and variables → Actions → **Variables**) from `terraform -chdir=bootstrap output repository_variables`: `GCP_WIF_PROVIDER`, `GCP_APPLY_SA`, `GCP_PLAN_SA`, `TF_STATE_BUCKET`, `DATABRICKS_ACCOUNT_ID`, `DATABRICKS_CLIENT_ID`. Also `GCP_PROJECT` = `<project-id>` if you'll use `databricks-probe`. Until these are set, every job that signs in skips itself.
5. Run **auth-check** on `main`. Its summary shows the GitHub token's claims, whose Google token came back, and the principal reading its own record.

How each hop works: [AUTH_BOOTSTRAP.md](AUTH_BOOTSTRAP.md).

## 2. Configure the stacks

| File | Set |
|---|---|
| `envs/test.tfvars` | `project_id`. Keep `fe_test_vm` and `fe_runner_nat` `false` until step 5 |
| `databricks/envs/test.tfvars` | `gcp_project_id`. The names and addresses match the GCP stack's defaults; change both together |
| `workspace/envs/test.tfvars` | `state_bucket` (the `TF_STATE_BUCKET` output) |

Merge to `main`. **The first plan has to run on `main`**: with an empty state bucket, `init` writes each stack's empty state, which the read-only pull-request identity can't (R11).

## 3. Build

Each apply is the `apply` workflow (Actions → apply → Run workflow), given the stack and the ID of the `terraform` run whose plan it replays. Check each plan's summary first.

1. **GCP stack** (create 24 with the runner off): three VPCs, the PSC endpoints, the private zone and the response policy.
2. **Account stack** (create 15): endpoint registrations, network configurations, private access settings, both workspaces through the REST provider (several minutes each), the principal's workspace assignment, and each workspace's DNS names.
3. Check: the three forwarding rules `ACCEPTED`; both workspaces `RUNNING`.

## 4. Workspace level, through the front end

1. Set `fe_test_vm` and `fe_runner_nat` to `true`, merge, apply the GCP stack.
2. Register the runner, as a person, over IAP:
   ```bash
   gcloud compute scp scripts/register-runner.sh fe-test-vm:register-runner.sh --zone us-central1-a --project <project-id> --tunnel-through-iap
   ```
   ```bash
   gcloud compute ssh fe-test-vm --zone us-central1-a --project <project-id> --tunnel-through-iap
   ```
   Then on the VM, `bash register-runner.sh <owner>/<repo>`, with a registration token from Settings → Actions → Runners → New self-hosted runner.
3. Run **workspace** with apply: a cluster policy and a dedicated cluster, which starts through the back-end endpoints only (about 5 minutes).

## 5. Verify

| Check | How | Expect |
|---|---|---|
| Re-plan | Any push to `main` | GCP and account stacks: no changes |
| Front end | **workspace**, apply off | The workspace URL resolves to the front-end endpoint, `accounts.gcp.databricks.com` publicly; `GET /` 303 |
| Refused from the internet | **psc-refusal** | `private`: 200 through the front end. `internet`: `403` "Unauthorized network access to workspace" (R12) |

## 6. Scale down and tear down

- **Scale down:** `fe_test_vm` and `fe_runner_nat` back to `false`. The three PSC endpoints are the remaining cost, about $0.01 an hour each.
- **Tear down** (deliverable E7): run **terraform** with **destroy**; apply the account stack; delete what Databricks left in the project (the `db-<vpc>-<region>-ingress` firewall rules, which block deleting the VPCs, and the `databricks-<workspace-id>` buckets, R10); apply the GCP stack from the same run. Then destroy `bootstrap/` locally, emptying its state bucket first, and delete the project.
