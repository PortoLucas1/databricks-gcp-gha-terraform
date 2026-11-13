# Databricks on GCP: Terraform workspace provisioning from GitHub Actions with your own IdP for SSO

**Test requirements, before testing.** Written 2026-11-12; results in [deliverables/E1_RESULTS.md](deliverables/E1_RESULTS.md). Where the results corrected this file (for example the federation subject in §4.2, finding R1), it is left as written and the correction is in the results. Every fact in §2 comes from public Databricks documentation, the public Terraform provider repository, or a public GitHub issue, checked on the dates shown. Everything else is a hypothesis to test (§3). Identifiers in this file are placeholders; keep it that way (§4.5).

## 1. Question under test

Can this repository's GitHub Actions pipeline create and manage Databricks on GCP workspaces (classic compute, customer-managed VPC, Private Service Connect) with Terraform when the Databricks account uses its own identity provider (Microsoft Entra ID) for single sign-on?

If not end to end, the test should show:
- which Databricks objects Terraform can create, update, and delete while SSO is on;
- which identities the pipeline needs, on the Google side and the Databricks side;
- what has to happen outside Terraform, and how often.

## 2. What the public sources already say

| # | Fact | Source (checked) |
|---|---|---|
| F1 | Bring-your-own-IdP SSO on GCP is in Public Preview. "When SSO is enabled in the account, all users, including admins, must sign in to the Databricks account and workspaces using single sign-on." | [Configure SSO](https://docs.databricks.com/gcp/en/security/auth/single-sign-on/) (page updated 2026-09-11; checked 2026-11-12) |
| F2 | "If you bring your own identity provider to configure single sign-on to Databricks, you can't authenticate with Google ID tokens." | [Authenticate with Google ID tokens](https://docs.databricks.com/gcp/en/dev-tools/auth/authentication-google-id) (checked 2026-11-12) |
| F3 | Some REST API methods need credentials passthrough: a Google OAuth access token with the `cloud-platform` scope, sent as well as the caller's credential. "These APIs require the X-Databricks-GCP-SA-Access-Token HTTP header in the request." "Databricks doesn't validate or preserve the access token." | [Credentials passthrough](https://docs.databricks.com/gcp/en/dev-tools/auth/authentication-google-id#credentials-passthrough) (checked 2026-11-12) |
| F4 | The provider's `google_service_account` argument (environment variable `DATABRICKS_GOOGLE_SERVICE_ACCOUNT`) impersonates a Google service account. That is the Google ID token path F2 rules out once SSO is on. | [Provider docs](https://registry.terraform.io/providers/databricks/databricks/latest/docs) (`docs/index.md`, checked 2026-11-12) |
| F5 | Workload identity federation for GitHub Actions: the Databricks SDKs and CLI "automatically fetch workload identity tokens from GitHub and exchange them for Databricks OAuth tokens". The federation policy uses issuer `https://token.actions.githubusercontent.com`; the audience defaults to the account ID; Databricks recommends the Environment entity type (the default is Branch). The provider's auth type for GitHub Actions is `github-oidc` (generic: `env-oidc`). | [GitHub Actions federation](https://docs.databricks.com/gcp/en/dev-tools/auth/provider-github) (page updated 2026-10-02); provider docs (checked 2026-11-12) |
| F6 | "To call account-level APIs, the service principal must be an account admin." | [OAuth M2M](https://docs.databricks.com/gcp/en/dev-tools/auth/oauth-m2m#call-a-databricks-rest-api) (checked 2026-11-12) |
| F7 | Provider issue #5999 (opened 2026-09-10, open on 2026-11-12): on an account with its own IdP, `databricks_mws_networks` with `env-oidc` fails with "Failed to get oauth access token. Please retry after logout and login again." The same service principal token plus the `X-Databricks-GCP-SA-Access-Token` header returns 201 Created. A 2026-10-13 comment reports the same with Entra ID SSO on provider v1.137.0. The changelog shows no fix through v1.142.0 (2026-11-09). | [Issue #5999](https://github.com/databricks/terraform-provider-databricks/issues/5999) (checked 2026-11-12) |
| F8 | Creating a workspace needs Google permissions on a Google Account or a service account. In the account console, a Google popup asks for consent to extra scopes: "Sign in with the same Google email as the one being used to sign into Databricks." | [Create a classic workspace](https://docs.databricks.com/gcp/en/admin/workspace/create-workspace#create-a-workspace) (checked 2026-11-12) |
| F9 | The Platform Deployment Kit's GCP template has the caller impersonate a Google service account that is "added to the Databricks account and assigned the Account Admin role", for both providers. It doesn't mention SSO. | [platform-deployment-kit](https://github.com/databricks-solutions/platform-deployment-kit) `deploy/templates/gcp/readme.md.template` (checked 2026-11-11) |
| F10 | Automatic identity management (AIM) with Entra ID syncs users, groups, service principals, and nested groups; JIT provisioning is always on with AIM. Nested groups and service principals that aren't directly provisioned "can't be retrieved or managed through the Databricks APIs or Terraform". | [Automatic identity management](https://docs.databricks.com/gcp/en/admin/users-groups/automatic-identity-management/#known-behaviors-and-limitations) (page updated 2026-10-15; checked 2026-11-12) |
| F11 | If Google Cloud Identity federates with an external IdP, "that IdP may have built-in SCIM integrations"; "if you use Google Cloud Identity as your only IdP (you do not configure it to federate with an external IdP), there is no built-in SCIM integration." | [SCIM](https://docs.databricks.com/gcp/en/admin/users-groups/scim/#sync-users-and-groups-to-your-databricks-account) (page updated 2026-11-03; checked 2026-11-12) |
| F12 | Emergency access (a sign-in path that bypasses SSO) is documented for AWS; no GCP page was found (checked 2026-11). With F1, a broken IdP or SSO app can lock out every admin. | [Emergency access (AWS)](https://docs.databricks.com/aws/en/security/auth/single-sign-on/emergency-access) |

## 3. Hypotheses

| # | Hypothesis | Based on |
|---|---|---|
| H1 | With SSO on, the provider configured with `google_service_account` fails against the account API (expect 401). | F2, F4 |
| H2 | With SSO on, a Databricks service principal on `github-oidc` can read account APIs (for example, list workspaces). | F5, F6 |
| H3 | With SSO on, `databricks_mws_networks` and `databricks_mws_workspaces` fail through the provider on `github-oidc`. | F7 |
| H4 | With SSO on, direct Accounts API calls with the service principal token plus `X-Databricks-GCP-SA-Access-Token` succeed for network configuration and workspace creation. The Google token comes from the job's existing Google workload identity login. | F3, F7 (only network configuration is reported) |
| H5 | In H4, the Google service account needs project permissions but no Databricks identity. | Unknown |
| H6 | Objects created in H4 can be imported into state, and `plan` is clean afterwards. Terraform updates and deletes of those objects need the header too and fail; find out which fields. | F3, F7; unknown per field |
| H7 | Account-level objects that don't touch the GCP project (metastore, metastore assignment, workspace assignment, account groups and permission assignments, network and ingress policies) work through the provider on `github-oidc` with SSO on. | Unknown; test each |
| H8 | Workspace-level resources (cluster policies, clusters, Unity Catalog storage credentials, external locations, catalogs, grants) work through the provider on `github-oidc` with SSO on. | F5, F6 |
| H9 | With SSO on, an admin signed in through Entra can create a workspace in the console when a Google account with the same email has project IAM, and can't when the emails differ. | F8 |
| H10 | With SSO off (default Google sign-in), both `google_service_account` and the H4 pattern create a workspace. This is the baseline. | F4, F9 |
| H11 | Optional: AIM with Entra on an account that keeps default Google sign-in. Can it be turned on, and are users who sign in with Google matched to their Entra identities? | Unknown; F10, F11 |
| H12 | Do the private access settings and VPC endpoint registration calls also need the header? | F3; unknown per call |

## 4. Lab requirements

### 4.1 Accounts and tenants
- **GCP:** the test project and bootstrap identities this repository already uses (see README), or a separate workspace project. The identity that creates the workspace needs the [permissions for workspace creation](https://docs.databricks.com/gcp/en/admin/workspace/create-workspace) on the workspace project.
- **Databricks:** a Databricks on GCP account used only for this test, with at least two account admins. Enterprise tier if Private Service Connect is in scope; Premium covers the rest of the test.
- **Entra ID:** a test tenant with an app registration for Databricks OIDC SSO, at least two test admins, one test user, and one test group. For H11, the app permissions the AIM setup page asks for.
- **Google identity for H9:** a Google account whose email matches one Entra test admin, with IAM on the workspace project, plus a second Google account with a different email for the negative case.
- **GitHub:** this repository; `permissions: id-token: write` on every job that authenticates.

### 4.2 Identities and trust

| Identity | Kind | Trusts | Used for | Tests |
|---|---|---|---|---|
| Apply identity (existing) | Google service account | GitHub OIDC through the existing workload identity pool, `main` only | GCP resources; the Google access token for the header; the `google_service_account` baseline | H1, H4, H5, H10 |
| Plan identity (existing) | Google service account | GitHub OIDC, any ref | Read-only plans | All plan steps |
| Databricks automation principal (new) | Databricks service principal, account admin (F6) | GitHub OIDC through a Databricks federation policy (F5) | Account and workspace APIs | H2-H8, H12 |
| Entra test admins | People | Entra SSO | Console tests; turning SSO on and off | H9, Phase B and D |
| Google test accounts | People | Google sign-in | The console consent popup | H9 |

Federation policy for the Databricks principal (F5): issuer `https://token.actions.githubusercontent.com`; subject for this repository's main branch, `repo:<owner>/<repo>:ref:refs/heads/main` (the repository uses no environments; see README on the free plan); audience left at the default (the account ID).

### 4.3 Network for the workspace
- Customer-managed VPC and subnet for the workspace, created by this repository's Terraform (google provider).
- Cloud NAT for outbound traffic, or back-end Private Service Connect if PSC is in scope; front-end PSC is optional.
- One region (the one in the repository's environment file).

### 4.4 Tooling
- Terraform and the google provider at the repository's pins; the Databricks provider at the latest release (v1.142.0 when this was written).
- `curl` and `jq` (or a short script) for the H4 calls. Record exact versions in the results.

### 4.5 Secrets and data hygiene
- No service account keys and no OAuth secrets: workload identity federation only, as in the rest of the repository.
- Never print tokens. If `TF_LOG` is needed, keep the log out of uploaded artifacts and scrub the `Authorization` and `X-Databricks-GCP-SA-Access-Token` headers.
- Results committed here use placeholders: no account IDs, workspace IDs, tenant IDs, project numbers, emails, or tokens.
- Terraform state stays in the existing GCS backend.

## 5. Test plan

Record for every step: the workflow run, the auth type, the HTTP status and error text, the time, and the provider version. Where possible, add the matching Databricks audit log event and the GCP Cloud Audit Logs entry for the service account.

**Phase A: SSO off (baseline)**

| Step | What | Tests |
|---|---|---|
| A1 | Provider with `google_service_account` creates a network configuration and a classic workspace | H10 |
| A2 | Databricks principal on `github-oidc` lists workspaces | H2 baseline |
| A3 | Databricks principal on `github-oidc` creates a network configuration through the provider. Does it fail even without SSO? | H3 baseline |
| A4 | Direct API calls with the principal's token plus the header create a network configuration and a workspace | H4 baseline, H5 |
| A5 | Optional: turn on AIM with Entra while sign-in stays on Google; sign in as a test user | H11 |

**Phase B: turn on Entra SSO (OIDC).** Follow the SSO docs: run Test SSO before enabling, keep a second admin session open, and confirm both admins can sign in through Entra afterward (F1, F12).

**Phase C: SSO on**

| Step | What | Tests |
|---|---|---|
| C1 | Provider with `google_service_account`, any account call | H1 |
| C2 | Databricks principal on `github-oidc` lists workspaces | H2 |
| C3 | Provider on `github-oidc` creates a network configuration and a workspace | H3 |
| C4 | Direct API calls with both tokens: network configuration, VPC endpoint registration, private access settings, workspace | H4, H12 |
| C5 | Repeat C4 with the Google service account removed from the Databricks account | H5 |
| C6 | Import the C4 objects; `plan`; then change one field of each through Terraform | H6 |
| C7 | Account-level objects through the provider on `github-oidc` | H7 |
| C8 | Workspace-level resources through the provider on `github-oidc` | H8 |
| C9 | Console creation by an Entra-signed-in admin, with a matching and a non-matching Google account | H9 |
| C10 | Delete a workspace through the API (with and without the header) and through Terraform | H6 |

**Phase D: teardown.** Delete the test workspaces and network configurations; delete the Databricks federation policy and principal; **turn SSO off before deleting the Entra app or tenant** (F12); remove the test users and groups.

## 6. What the results decide

| Option | Depends on |
|---|---|
| O1: Create workspaces and VPC endpoints in the console; Terraform for GCP networking and everything inside workspaces | H8, H9 |
| O2: Scripted Accounts API calls with both tokens in the pipeline, then `terraform import` | H4, H5, H6, H12 |
| O3: Create account-level objects with Terraform before turning on SSO; later workspaces by O1 or O2 | H10, C1 |
| O4: Keep default Google sign-in on Databricks, with Google Cloud Identity federated to Entra | H10, H11, F11 |
| O5: Turn SSO off for each run | Not planned (F1, F12) |

## 7. Open questions outside the lab
- The roadmap for SCIM-based provisioning on accounts that use Entra ID or Okta: confirm with Databricks how it applies to GCP accounts.
- Whether the provider will send the GCP access token header with OIDC auth (issue #5999).
- AIM with default Google sign-in, if H11 is inconclusive.

## 8. References
- [Configure SSO in Databricks (GCP)](https://docs.databricks.com/gcp/en/security/auth/single-sign-on/)
- [Authenticate with Google ID tokens, including credentials passthrough](https://docs.databricks.com/gcp/en/dev-tools/auth/authentication-google-id)
- [Enable workload identity federation for GitHub Actions (GCP)](https://docs.databricks.com/gcp/en/dev-tools/auth/provider-github)
- [Authorize service principal access with OAuth (GCP)](https://docs.databricks.com/gcp/en/dev-tools/auth/oauth-m2m)
- [Create a classic workspace (GCP)](https://docs.databricks.com/gcp/en/admin/workspace/create-workspace)
- [Automatic identity management (GCP)](https://docs.databricks.com/gcp/en/admin/users-groups/automatic-identity-management/)
- [SCIM provisioning (GCP)](https://docs.databricks.com/gcp/en/admin/users-groups/scim/)
- [Databricks Terraform provider docs](https://registry.terraform.io/providers/databricks/databricks/latest/docs)
- [terraform-provider-databricks issue #5999](https://github.com/databricks/terraform-provider-databricks/issues/5999)
- [platform-deployment-kit](https://github.com/databricks-solutions/platform-deployment-kit)
- [Emergency access (AWS docs)](https://docs.databricks.com/aws/en/security/auth/single-sign-on/emergency-access)
