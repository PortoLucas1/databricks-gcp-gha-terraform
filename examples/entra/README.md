# Entra examples

Terraform for the Entra side of the use case ([USE_CASE.md](../../docs/USE_CASE.md), results in [USE_CASE_RESULTS.md](../../docs/USE_CASE_RESULTS.md)). In the lab these objects were made with `az` and the Databricks CLI; this is the same configuration as code. It passes `terraform validate` in CI but wasn't applied in the lab. One difference: the lab's U7 app also had a GitHub federated credential, which this example creates only for option B. The Databricks side of group access is in the stacks themselves: [`databricks/groups.tf`](../../databricks/groups.tf) (assignment) and [`workspace/entitlements.tf`](../../workspace/entitlements.tf) (entitlement). The guide is [E6](../../docs/deliverables/E6_CONFIGURATION_GUIDE.md) §6 and §7.

Applied locally, like `bootstrap/`, by an Entra administrator (`az login` to the tenant behind the account's SSO and AIM) and a Databricks account admin (a CLI profile on the account console). Prerequisites: Entra SSO and AIM on the account, same tenant.

| File | What | Tested in the lab |
|---|---|---|
| `groups.tf` | Security groups for workspace access, existing users as members, groups nested inside them | The same shape, made with `az` (U3, U4) |
| `pipeline_principal.tf` | Option C: an Entra app registration and service principal as the pipeline's Databricks identity; its account admin role and GitHub federation policy | The same objects, made with `az` and the CLI (U7) |
| `pipeline_principal.tf`, `entra_token_exchange` | Option B: an Entra federated credential for GitHub and an account federation policy trusting Entra-issued tokens | **Not tested**; off by default |

## Order

AIM provisions objects from Entra, and Terraform can't see them until it has, so there are steps between the applies.

1. **Entra objects:** `groups` and `pipeline_principal_name` set, `pipeline_principal_provisioned = false`. Apply.
2. **Add from Entra** in the Databricks account console: each group in the `groups_to_add_from_entra` output, and the pipeline principal (its Databricks application ID is the Entra client ID).
3. **Pipeline principal's role and policy:** `pipeline_principal_provisioned = true`. Apply.
4. **Group access in the stacks:** `workspace_groups` in `databricks/envs/<env>.tfvars` (assignment), `group_entitlements` in `workspace/envs/<env>.tfvars` (entitlement). Plan and apply through the pipeline.
5. To run the pipeline as the Entra-owned principal: set `DATABRICKS_CLIENT_ID` to `pipeline_principal_client_id`; check with `auth-check`.

```bash
terraform -chdir=examples/entra init -backend-config="bucket=<admin-bucket>" -backend-config="prefix=<path>/entra"
terraform -chdir=examples/entra apply "-var-file=example.tfvars"
```

Example values (`example.tfvars`, placeholders):

```hcl
entra_tenant_id       = "<tenant-id>"
databricks_account_id = "<account-id>"
databricks_profile    = "<profile>"

github = {
  owner         = "<owner>"
  owner_id      = "<owner-id>"
  repository    = "<repo>"
  repository_id = "<repo-id>"
}

groups = {
  "<access-group>" = {
    members       = ["<user>@<domain>"]
    nested_groups = ["<nested-group>"]
  }
  "<nested-group>" = {
    members = ["<other-user>@<domain>"]
  }
}

pipeline_principal_name        = "<pipeline-app-name>"
pipeline_principal_provisioned = false
```

## Notes from the lab

- **Assign and entitle together** (R18); a group nested inside an assigned group works for membership but can't be read or managed through the Databricks API or Terraform unless it is added to the account from Entra itself (R17).
- **Leavers:** disabling a user in Entra blocks new sign-ins through Entra, but the Databricks user still read `active` minutes later; revoke their personal access tokens in Databricks (R19).
- **Tenant policies apply to Databricks sign-in:** new or test users may need MFA registration, or an exclusion, before they can sign in. Not configured here.
- **The pipeline principal's federation policy and the Entra federated credential both match the subject exactly:** use the form the repository's tokens carry. Repositories created, renamed or transferred on or after 2026-07-15, or opted in, get the immutable-ID form this example builds (R1); others get `repo:<owner>/<repo>:ref:<ref>` ([GitHub Actions federation](https://docs.databricks.com/gcp/en/dev-tools/auth/provider-github#create-a-federation-policy)).
- On Windows PowerShell 5.1, the Databricks CLI needs JSON bodies as `--json @file` if you make any of this by hand.
