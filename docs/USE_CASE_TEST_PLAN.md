# Use case test plan: Entra SSO and AIM for people, the lab's pipeline unchanged

**Plan, 2026-11-13; revised the same day for the account switch. Run 2026-11-13 and 14; results in [USE_CASE_RESULTS.md](USE_CASE_RESULTS.md).** How to run §6 of the [use case](USE_CASE.md): U1–U6 there, plus U0 (why the first design breaks, with Entra) and U7 (the open points of the [AIM assessment](AIM_ENTRA_ASSESSMENT.md)), which the same account answers at no extra cost. Identifiers are placeholders; record results as [TEST_PLAN.md](TEST_PLAN.md) §6 does.

## 1. Where it runs

| Need | Plan | Why |
|---|---|---|
| A Databricks account with **Entra SSO and Entra AIM** on, Enterprise tier (PSC) | **The existing shared account, switched from its previous identity provider to Entra SSO and Entra AIM for the test window, then back** (decided 2026-11-13) | A dedicated account isn't practical: GCP allows one Databricks account per billing account, and a trial's tier may not include PSC (Enterprise only). The account has run Entra SSO and AIM before, so the switch is a known procedure |
| An Entra tenant | The tenant behind the account's SSO and AIM, with test-only users and groups (§2) | AIM serves one tenant (A2) |
| A GCP project | A **new** project in the existing organization, created by the organization's infrastructure Terraform with its DRS exception and single-project profile, as for the lab | The lab's project is deleted and its ID can't be reused |
| The pipeline | This repository, built by [REPRODUCE.md](REPRODUCE.md), unchanged except §4 | The point of the test is the lab's design on an Entra account |

Consequences of using the shared account:
- **Every workspace in the account signs in through Entra during the window,** and through its previous identity provider again afterwards. Do both switches with a second admin session open, and run the identity provider's sign-in test before enabling it (F1, F12).
- **Phase A (SSO off) still can't run.** U0 shows only the refusal with Entra on; the SSO-off baseline stays prior evidence (H10).
- **Identities Entra AIM creates stay in the account after the switch back.** The test users, groups and the U7 principal are deleted before the previous identity provider goes back on (§5), so they don't affect other work on the account.
- Test users, groups and the U7 app registration live in the real tenant. Name them `dbx-uc-test-*` and delete them at the end.
- Other work on the account pauses for the window: record the account's identity configuration before the switch, and restore it from that record. (Done: the account went back to its previous identity provider, with AIM re-enabled, after the teardown.)

## 2. Prerequisites

| # | What | Who | Cost |
|---|---|---|---|
| P1 | Record the account's identity configuration; switch the account to **Entra SSO** (the existing Entra app) and turn on **Entra AIM**; confirm both admins sign in through Entra | Account admin | $0 |
| P2 | Entra: users `dbx-uc-test-member`, `dbx-uc-test-nested-member`, `dbx-uc-test-outsider`; group `dbx-uc-test-group` holding the member and group `dbx-uc-test-nested`, which holds the nested member. The outsider is in neither | Entra admin | $0 |
| P3 | New GCP project, DRS exception, single-project profile (the infrastructure Terraform; the retirement MRs show what to add back) | Infrastructure repository, pipeline apply | $0 |
| P4 | `bootstrap/` applied, repository variables set, **auth-check** passes ([REPRODUCE.md](REPRODUCE.md) §1) | Administrator | $0 |
| P5 | The §4 changes merged | Pull request | $0 |

## 3. Tests, in order

| # | Test | How | Pass when | Shows | Cost |
|---|---|---|---|---|---|
| **U0** | The first design's provider sign-in, with Entra SSO on | Add the apply identity's Google service account to the account as a user with account admin (temporarily). Run the `first-design` job (§4): the Databricks provider with `google_service_account`, a plan of `databricks_mws_workspaces` | `401` (or `Invalid Request`) on the account call, as H1's prior evidence. Remove the user afterwards | Use case §4 with Entra, not just prior evidence | $0 |
| **U1** | AIM leaves the native principal alone | **auth-check**, unchanged | All three hops pass; the principal reads its own record | N3 | $0 |
| **U2** | One-pass build on the Entra account | [REPRODUCE.md](REPRODUCE.md) §2–§5: GCP stack, account stack, runner, workspace stack, re-plan, **psc-refusal** | As in E1: both workspaces `RUNNING`, cluster `RUNNING`, re-plans clean, `403` from the internet, `200` through the front end | N4, N6 with Entra SSO and AIM on | ~$2 a day while built |
| **U3** | Workspace access from Entra groups, by Terraform | Add `dbx-uc-test-group` to the account from Entra (account console). Then the `databricks/` stack assigns it to `gha-test-psc` (§4, `workspace_groups`). **aim-check** (§4) reads groups and assignments as the principal | The group is found by name and assigned (`USER`); `dbx-uc-test-nested` is **not** found through the API (the AIM page's limitation) | N2, and where Terraform stops | $0 |
| **U4** | People sign in through Entra, privately | From a browser, through an SSH SOCKS proxy on `fe-test-vm` (`gcloud compute ssh … -- -D 1080`, browser set to that proxy with remote DNS): the member, the nested member and the outsider sign in to `gha-test-psc` in turn | Member: created just-in-time, reaches the workspace through the group. Nested member: also reaches it (AIM syncs nested groups), although U3 found the nested group invisible to the API. Outsider: no workspace access. Without the proxy, from the internet: refused (public access off) | N1, N2, through the front-end endpoint; nested membership in practice | Included in U2's days |
| **U5** | Disabling a person doesn't touch the pipeline | Disable `dbx-uc-test-member` in Entra. After AIM syncs: try to sign in; run **auth-check** | The user can't sign in; auth-check passes | N3 | $0 |
| **U6** | Console creation with matching and non-matching Google accounts (H9) | **Skip** unless the REST provider is rejected; it needs two Google test accounts | — | Fallback only | — |
| **U7** | The AIM assessment's open points (A7) | Register `dbx-uc-test-pipeline` in Entra with a GitHub federated credential for this repository's `main`. Add its service principal to the account from Entra. Record its Databricks application ID; give it account admin; then (C) attach a service principal federation policy (GitHub issuer) and run **auth-check** with `DATABRICKS_CLIENT_ID` pointing at it; (B) optionally, an account federation policy for the Entra issuer and a dedicated audience, and a job that exchanges an Entra token (`env-oidc`) | Answers: is the application ID the Entra client ID; can it be account admin; does C work; does B work | Options B and C | $0 |

**The private browser for U4, as run.** On Windows, `gcloud compute ssh` through PowerShell needs the proxy flags as `--ssh-flag="-D 1080" --ssh-flag="-N"` (PowerShell consumes a bare `--`); the session then sits after authenticating, which is the tunnel working. A separate Edge or Chrome instance, with its own profile: `--user-data-dir=<temp dir> --proxy-server="socks5://127.0.0.1:1080" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE 127.0.0.1" --inprivate`. The resolver rule stops the browser resolving names locally, so the workspace name resolves on the runner's side; Edge shows an "unsupported command-line flag" banner for it, which is expected for this throwaway profile. Check `https://ifconfig.me` shows the runner's NAT address before signing in. Test users in a tenant that requires MFA registration must be in its MFA exclusion group first.

Order: U0, U1 and U7 first (account level, nothing built). Then U2, U3, U4 in one build window. U5 last, then teardown.

## 4. Changes made for the test (this pull request)

| Change | For | Notes |
|---|---|---|
| `first-design/` and the **first-design** workflow: the provider from [USE_CASE.md](USE_CASE.md) §2 and `data "databricks_mws_workspaces"`, planned as the apply identity; the job records accepted or refused and passes either way | U0 | `bootstrap/` `first_design_test = true` makes the apply identity an account admin and gives it token creator on itself (the provider mints a Google ID token as it). Set back to `false` after U0 |
| `databricks/groups.tf`: optional `workspace_groups` (group display name → permissions), looked up with `data "databricks_group"` and assigned with `databricks_mws_permission_assignment` | U3 | Empty by default, so the reference build is unchanged. For U3, set `workspace_groups = { "dbx-uc-test-group" = ["USER"] }` in `databricks/envs/test.tfvars` |
| **aim-check** workflow: as the automation principal, the test groups (found or not, members, from the IdP or not), the workspace's permission assignments, the test users' `active` state. Only names, counts and states in the summary | U3, U5 | Read only |
| **auth-check**: an optional `client_id` input | U7 (C) | Blank means `DATABRICKS_CLIENT_ID` |
| `terraform` workflow: `validate` also covers `bootstrap/` and `first-design/` | All | |
| `docs/TEST_PLAN.md`: a §6 block for U0–U7 | Recording | |

U7 (B), the Entra token exchanged through an account federation policy (`env-oidc`), needs no change here until C's result is in: it's optional, and its job is written then if it's wanted.

Not changed: `bootstrap/`'s principal, the REST provider, the PSC design.

## 5. Teardown

1. **Lab:** as [E7](deliverables/E7_TEARDOWN.md): destroy run, account stack, R10 leftovers by hand, GCP stack.
2. **U0 leftovers:** `bootstrap/` with `first_design_test = false` (removes the apply identity's account user and its token creator grant), if not done right after U0.
3. **Account identities from the test,** while Entra AIM is still on: U7's synced principal, the test users and groups. Then the Entra side: the `dbx-uc-test-*` users and groups and the `dbx-uc-test-pipeline` app registration.
4. **Switch the account back to its previous identity provider** (SSO, and its AIM if it had it on), Entra AIM off, both admins signing in. Compare with the record from P1.
5. `bootstrap/` destroyed (it deletes its principal, R14), then the project through the infrastructure Terraform.

## 6. Cost and timing

- Account-level tests (U0, U1, U3's lookup, U5, U7): $0.
- The build window (U2, U3's assignment, U4): about $2 a day for the endpoints, runner VM and NAT, plus a few cluster minutes. One to two days: **about $5**.
- Start when the account is switched to Entra (P1). Costs of other paused work keep running, so check the month's remaining headroom first.

## 7. What each outcome means

- **U0 refused, U1–U5 pass:** the organization can turn on Entra SSO and AIM and keep the lab's pipeline as it is (the use case's §7, first case).
- **U1 or U2 fails:** the native principal is affected by AIM or Entra SSO; U7's results decide between options B and C.
- **U3's nested group readable:** the documented limitation has changed; note it, it simplifies group design.
- **U7:** settles A7 in the AIM assessment whichever way it goes.
