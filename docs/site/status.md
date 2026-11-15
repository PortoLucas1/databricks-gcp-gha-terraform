# Entra ID with GitHub Actions on Databricks on GCP: test status

**Status, 2026-11-14: testing complete.** Tested on a Databricks on GCP account with **Microsoft Entra ID single sign-on and automatic identity management (AIM) turned on**, with the lab's GitHub Actions and Terraform pipeline. Two questions: can people use Entra while the pipeline keeps working, and can the pipeline's own identity come from Entra?

## Where it stands

| Question | Answer |
|---|---|
| People sign in through Entra and come from Entra through AIM, while GitHub Actions builds workspaces with Terraform | **Viable, proven end to end.** The pipeline is unaffected by Entra SSO and AIM and built the whole private deployment with both on. People sign in through Entra over Private Service Connect and get workspace access from their Entra groups, nested groups included; others are refused |
| The pipeline's own Databricks identity comes from Entra (an Entra service principal synced by AIM) | **Viable.** Proven at account level: a GitHub Actions job signs in as the Entra principal, as account admin, without a secret. Not run through a full build |
| The original design: the Databricks provider signing in as a Google service account | **Doesn't work with Entra SSO.** The account refuses it, even for an account admin |

## Tested

| Test | Result |
|---|---|
| Original design with Entra SSO on: the provider's `google_service_account` sign-in | **Refused** ("Invalid Request") for a Google service account that is an account admin. Own-IdP SSO turns off Google ID token sign-in for the whole account |
| The pipeline's sign-in after switching SSO to Entra, and again after turning on AIM | **Unaffected**: GitHub token exchanged for the pipeline's Databricks service principal, account admin |
| The full private build with Entra SSO and AIM on: both workspaces, back-end and front-end Private Service Connect, a cluster, workspace-level Terraform | **Works**, with the same results as the earlier lab. The cluster started through the back-end endpoints only; the workspace refused the pipeline's own principal from the internet and served it through the front end |
| An Entra group, provisioned by AIM, given workspace access by Terraform | **Works** once Terraform both assigns the group and gives it an entitlement in the workspace (Workspace access); assignment alone isn't enough |
| People signing in through Entra, privately | A direct group member and a member of a **nested** group both reached the workspace; a user in neither was refused. A member signing in from the internet was refused by the workspace |
| Disabling a person in Entra | **Blocked at Entra's sign-in; the pipeline unaffected.** The Databricks user record still read active minutes later |
| An Entra service principal synced by AIM as the pipeline's identity | Its Databricks application ID **is** its Entra client ID; it **can** hold account admin; it **can** carry its own federation policy, and a GitHub Actions job **signed in as it** with no secret |

## Not run

| Test | Why |
|---|---|
| The Entra principal through a full build | The account-level result answers the question; a build with it is the step before adopting it |
| Entra-issued tokens exchanged by Databricks (instead of GitHub tokens) | Only needed if Entra Conditional Access must apply to the pipeline |
| The SSO-off baseline | Needs SSO off on an account shared with other work |

## What to plan around

- **Keep Google workload identity federation.** Creating workspaces, network configurations and endpoint registrations needs a Google access token in the `X-Databricks-GCP-SA-Access-Token` header, whichever identity signs in to Databricks. Entra replaces the Databricks half only.
- **Assign workspaces to groups added directly from Entra, and give each an entitlement inside the workspace.** Without the entitlement, members reach the workspace and are refused. Nested groups work for membership, but Terraform can't see or manage them.
- **Revoke access in Databricks too when someone leaves.** Disabling the person in Entra stops their sign-in at once, but the Databricks user isn't deactivated straight away, so personal access tokens and open sessions need revoking separately.
- **AIM provisions lazily.** Users appear at first sign-in, service principals when added from Entra or first used; Terraform can't manage a principal until then.
- **Workspace creation has a daily limit per account.** A teardown and rebuild on one day, or many workspaces at once, can reach it; the API answers `429 RESOURCE_EXHAUSTED`. Plan large rollouts across days.
- **Two ways to give the pipeline an Entra identity.** With the GitHub token exchanged directly (tested), the identity is owned and disabled in Entra and the trust stays narrow. With Entra tokens exchanged by Databricks (not tested), Entra's Conditional Access also applies, at the cost of a second exchange and an account-wide trust of the Entra tenant.
