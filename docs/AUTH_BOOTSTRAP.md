# How GitHub Actions authenticates to GCP and Databricks

No keys, no client secrets, no stored tokens. Every job proves who it is with a short-lived OIDC token that GitHub signs, and exchanges it for short-lived Google and Databricks credentials. What the job may do is decided by trust configured once, by administrators, in [`bootstrap/`](../bootstrap/).

## The chain

| # | Hop | Who checks what | Configured in |
|---|---|---|---|
| 1 | The job asks GitHub for an OIDC token (`permissions: id-token: write`) | GitHub signs claims about the job: issuer `https://token.actions.githubusercontent.com`, `sub` `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:<ref>`, `repository`, `repository_owner_id`, `ref`, `runner_environment`, and the audience the job asked for | The workflow |
| 2 | `google-github-actions/auth` sends a token (audience: the pool provider's resource name) to Google's Security Token Service | The pool's **provider**: right issuer, and the **attribute condition** `repository_owner_id == <owner-id> && repository == <owner>/<repo>`. Without a condition any GitHub repository could use the pool | `bootstrap/gcp.tf`: pool `github-actions`, provider `github-oidc` |
| 3 | The federated token impersonates a service account | `roles/iam.workloadIdentityUser` on the account, granted to a **principal set** of the pool: the apply identity to `attribute.ref/refs/heads/main`, the plan identity to `attribute.repository/<owner>/<repo>` | `bootstrap/gcp.tf`: `gha-apply`, `gha-plan` |
| 4 | The job asks GitHub for another token, audience the Databricks account ID, and sends it to `https://accounts.gcp.databricks.com/oidc/accounts/<account-id>/v1/token` (grant type token-exchange, `client_id` = the principal's application ID) | The principal's **federation policy**: issuer, the exact `sub`, the audience (default: the account ID) | `bootstrap/databricks.tf`: `github-terraform-ci`, account admin |
| 5 | Calls that create or change a workspace, a network configuration or an endpoint registration also send the apply identity's Google access token in `X-Databricks-GCP-SA-Access-Token` | Databricks uses it to act in the GCP project; it needs project permissions, not a Databricks identity | The REST provider (`databricks/rest.tf`) |

The Terraform provider and Databricks SDKs do hop 4 themselves with `auth_type = "github-oidc"`; the workflows here also do it explicitly (`.github/scripts/databricks-token.sh`) where a REST call needs the token.

The `auth-check` workflow runs hops 1–4 and shows the result of each: the token's claims (decoded, never the token), whose Google access token came back, and the Databricks principal reading its own record.

## Decisions in the trust configuration

- **Numeric IDs, not just names.** The Google condition matches the owner's numeric ID; the Databricks subject carries both IDs. A deleted account's or repository's name can be registered again by someone else; its IDs can't.
- **Take the subject from a real token.** GitHub issues the immutable-ID form shown above; older documentation shows `repo:<owner>/<repo>:ref:<ref>`. Databricks matches exactly, and a mismatch fails with `TOKEN_SUBJECT_INVALID`, naming the subject the token carried.
- **`main` only for the identities that write.** The apply identity and the Databricks principal trust `refs/heads/main`. A free private repository has no branch protection or environment reviewers, so whoever can push to `main` can apply; on a paid plan, bind both to a GitHub **environment** with required reviewers instead (Databricks recommends the environment entity type).
- **A read-only identity for pull requests**, Google side only. Databricks has no read-only account role, so Databricks plans run on `main`.
- **Owner on the project** for the apply identity in the lab; narrow it where the project holds more.

## Bootstrap: who runs it, once

An administrator, locally, with their own sign-ins: `gcloud auth application-default login` (project IAM, service accounts, workload identity pools) and a Databricks CLI profile on the account console (`databricks auth login --host https://accounts.gcp.databricks.com --account-id <account-id>`), as an account admin. The bootstrap's own state goes in a bucket the administrators already have, not the one it creates.

```bash
terraform -chdir=bootstrap init -backend-config="bucket=<admin-bucket>" -backend-config="prefix=<path>/gha-bootstrap"
terraform -chdir=bootstrap apply -var-file=envs/<env>.tfvars
terraform -chdir=bootstrap output repository_variables
```

Then set the six outputs as repository variables (Settings → Secrets and variables → Actions → **Variables**; none is a secret): `GCP_WIF_PROVIDER`, `GCP_APPLY_SA`, `GCP_PLAN_SA`, `TF_STATE_BUCKET`, `DATABRICKS_ACCOUNT_ID`, `DATABRICKS_CLIENT_ID`. Run **auth-check**.

On Windows PowerShell, quote any argument that has a dot after `=`: `"-var-file=envs/test.tfvars"`. Unquoted, PowerShell splits it at the dot and Terraform tries to open `.tfvars` as a saved plan.

**The first plan has to run on `main`.** With an empty state bucket, `terraform init` writes each stack's empty default state and its lock file. The plan identity only reads the bucket, so a pull request's plan fails at `init` (`gha-plan … does not have storage.objects.create … default.tflock`) until a run on `main`, as the apply identity, has created the states. After that, pull request plans only read them.

## Recreating the lab's auth (2026-11)

The lab's first auth setup was split: the Google side in another repository's bootstrap, the Databricks principal and policy made by hand with the CLI. Recreated here, in order:

1. **Retire the old Google side**: empty the old state bucket (the stacks' states are empty after the teardown), then remove the pool, provider, identities and bucket from the other repository's bootstrap. The project stays, with its APIs and its domain restricted sharing exception.
2. **Delete the old Databricks principal** (`github-terraform-ci`), which also deletes its federation policy.
3. **Apply `bootstrap/`** as above. The pool gets a new ID: a deleted pool's ID can't be reused for 30 days.
4. **Set the repository variables** from the outputs; `DATABRICKS_CLIENT_ID` changes (a new principal has a new application ID).
5. **Run auth-check**, then the rebuild.
