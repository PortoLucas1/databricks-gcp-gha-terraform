# Use case results: Entra SSO and AIM for people, the lab's pipeline unchanged

**Status, 2026-11-14: tests complete (U6 skipped); torn down ([E7](deliverables/E7_TEARDOWN.md)).** Results of the [use case](USE_CASE.md) tests U0–U7, run as the [test plan](USE_CASE_TEST_PLAN.md) describes. The step-by-step record, with run numbers, is in [TEST_PLAN.md](TEST_PLAN.md) §6 (*Use case tests*). Identifiers are placeholders; run and pull request numbers refer to this repository. Findings R1–R15 are in [E1](deliverables/E1_RESULTS.md); R16–R19 come from these tests.

## Where it stands

| Question | Answer so far |
|---|---|
| People sign in through Entra and come from Entra through AIM, while GitHub Actions builds workspaces with Terraform (needs N1–N6) | **Viable, proven.** The pipeline is unaffected by Entra SSO and by AIM and built the whole private lab with both on (U2). People sign in through Entra over the front end and get workspace access from Entra groups, nested groups included, once Terraform assigns the group and gives it an entitlement (U3, U4, R18); others are refused. Disabling a person stops them at Entra and leaves the pipeline alone (U5) |
| The pipeline's own Databricks identity comes from Entra (the [AIM assessment](AIM_ENTRA_ASSESSMENT.md), option C) | **Viable.** Proven at account level (U7): a GitHub Actions job signs in as an Entra service principal synced by AIM, as account admin, with no secret. Not yet run through a full build |
| The first design: the Databricks provider signing in as a Google service account ([use case](USE_CASE.md) §2) | **Doesn't work with Entra SSO** (U0): refused, even for an account admin |

## Environment

- **Databricks:** the existing shared account, Enterprise tier, switched from its previous identity provider to **Entra SSO** for the test (P1), with **Entra AIM** turned on after U0, and switched back at the end.
- **GCP:** a new project in the existing organization, created by the infrastructure Terraform with its DRS exception and single-project profile (P3).
- **Entra:** the tenant behind the account's SSO and AIM, with test users `dbx-uc-test-member`, `dbx-uc-test-nested-member`, `dbx-uc-test-outsider` and groups `dbx-uc-test-group` ⊃ `dbx-uc-test-nested` (P2).
- **Pipeline:** this repository, unchanged except the test additions of PR #30 (`first-design/`, `workspace_groups`, `aim-check`, auth-check's `client_id` input), with its identities recreated by `bootstrap/` in the new project (P4). Terraform 1.15.9, Databricks provider 1.142.0, `magodo/restful` 0.25.2.

## Results

| Test | Result | Evidence |
|---|---|---|
| **P4** auth-check, baseline, on the previous identity provider's SSO | **Passed** | GitHub claims with the immutable-ID subject; the apply identity's Google token; Databricks exchange 200 for the native principal, account admin |
| **U0** first design, Entra SSO on | **Refused** | `first-design` run: "cannot read mws workspaces: … Invalid Request", with a Databricks request ID, for a Google service account that is an active account admin (`bootstrap/` `first_design_test = true`, removed again afterwards). Google minted the ID token; Databricks refused it. Confirms H1 with Entra; the SSO-off baseline (H10) can't run on this account |
| **U1a** auth-check, Entra SSO on, AIM off | **Passed** | Same as P4: the switch to Entra doesn't touch the pipeline's identity |
| **U1** auth-check, Entra SSO and AIM on | **Passed** | Same as P4: AIM leaves a principal it didn't sync alone (N3) |
| **U2** one-pass build | **Done** (the re-plan in the U3 merge run) | Everything built **with Entra SSO and AIM on**: GCP stack (27); account stack (15) over two days, the back-end PSC workspace held a day by the daily workspace creation limit (R15) and then created from the same plan; the workspace stack on the runner through the front end (cluster `RUNNING` after 4m 48s, back-end endpoints only); `psc-refusal` 200 through the front end, 403 from the internet. Same results as the lab's rebuild (E1) |
| **U3** groups from Entra, assigned by Terraform | **Done** | `dbx-uc-test-group` added to the account from Entra (console). `aim-check`: the group **found** through the account API, with an external ID (from the IdP) and 0 members; `dbx-uc-test-nested` **not found**; no test users yet (R17). Then `workspace_groups` (PR #34): the merge run planned only the assignment (also U2's re-plan); apply: `dbx-uc-test-group` assigned `USER` on `gha-test-psc`, listed by `aim-check` beside the principal (`ADMIN`) |
| **U4** people sign in through Entra, privately | **Done** | Test users needed adding to the tenant's MFA exclusion group first (the tenant requires MFA registration). **From the internet**, the member signed in to Entra and the account and was refused by the workspace (public access off). **Through the front end** (a browser on an SSH SOCKS proxy through the runner; egress checked as the runner's NAT address): the workspace answered "Unable to view page: not assigned or no Workspace access entitlement", twice. The member had been created at first sign-in and linked to Entra a few minutes later (external IDs match the Entra object IDs). `workspace-identity-check` (PR #35): the workspace lists `dbx-uc-test-group` on the member's record, but the group has **no entitlements**, and the built-in `users` group has none either (R18). With the Workspace access entitlement on the group (workspace stack, PRs #36 and #37), **the member signed in through the front end and used the workspace**: access from an Entra group, provisioned by AIM, assigned and entitled by Terraform. The **nested member** got in as well, through a group that neither the workspace nor Terraform can see (R17); the **outsider** was refused ("Unable to view page"). All three users created at first sign-in and linked to Entra |
| **U5** disabled person, pipeline unaffected | **Done** | `dbx-uc-test-member` disabled in Entra: refused at Entra's sign-in ("Your account has been locked"); `auth-check` passed. The Databricks user record still read `active` minutes later (R19) |
| **U6** console creation (H9) | Skipped | Only needed if the REST provider were rejected |
| **U7** an Entra principal synced by AIM as the pipeline's identity | **Done: all three open points yes; option C works** | `dbx-uc-test-pipeline`, an Entra app registration with no secrets and no API permissions, added to the account from Entra: its Databricks **application ID is the Entra client ID**; **account admin** accepted; its own **federation policy** (GitHub issuer, immutable-ID subject) accepted; auth-check with that client ID signed in as it (exchange 200, account admin) (R16). Option B, an Entra token exchanged by Databricks, not run |

## Findings from these tests

| # | Finding | Effect |
|---|---|---|
| R15 | A Databricks account has a daily limit on workspace creation (`429 RESOURCE_EXHAUSTED`). See [E1](deliverables/E1_RESULTS.md) | Plan rebuilds and rollouts across days. The pipeline's summaries now show the API's message |
| R16 | An Entra service principal synced by AIM keeps its Entra client ID as its Databricks application ID, can hold account admin, and can carry its own federation policy; a GitHub token exchanged against that policy signs in as it | The pipeline's Databricks identity can be owned in Entra without Entra tokens in the pipeline (the [AIM assessment](AIM_ENTRA_ASSESSMENT.md), option C). It can't be created by Terraform; it's added from Entra, then managed by application ID |
| R17 | With AIM, a group added to the account from Entra is visible to the account API with its external ID; a group nested inside it is not; users and member counts appear only once people sign in | Terraform can assign workspaces only to groups added directly from Entra. Whether nested members get access is U4 |
| R18 | A group assigned to a workspace at account level gets no entitlement, and a new workspace's built-in `users` group has none: members reach the workspace and are refused. AIM's membership does reach the workspace (the member's record lists the group) | Set an entitlement on the group inside the workspace (Terraform `databricks_entitlements`, workspace stack) as part of every group assignment |
| R19 | Disabling a person in Entra stops them at Entra's sign-in, but AIM doesn't deactivate the Databricks user straight away (still `active` minutes later) | Revoke a leaver's personal access tokens and sessions in Databricks too; don't rely on the Entra disable alone for non-interactive access |

Also confirmed: H1 with Entra SSO (U0). And for the record: Windows PowerShell 5.1 mangles inline JSON passed to the Databricks CLI; pass `--json @file`.

## To plan around

- **Keep Google workload identity federation.** Creating workspaces, network configurations and endpoint registrations needs a Google access token in `X-Databricks-GCP-SA-Access-Token`, whichever identity signs in to Databricks. Entra replaces the Databricks half only.
- **Assign workspaces to groups added directly from Entra** (R17), **and give each such group an entitlement inside the workspace** (R18).
- **Entra groups in workspaces:** members of nested groups get access through the parent group, though Terraform can't see the nested group (U4, R17).
- **AIM provisions lazily:** users at first sign-in, service principals when added from Entra or first used (A3).
- **Spread workspace creation across days** (R15).
- **Two ways to give the pipeline an Entra identity:** GitHub tokens exchanged directly (tested, R16), or Entra tokens exchanged by Databricks (untested; only needed for Entra Conditional Access on the pipeline, at the cost of an account-wide trust of the tenant).

## Teardown

Done 2026-11-14 ([E7](deliverables/E7_TEARDOWN.md)): the stacks destroyed, Databricks' leftovers in the project removed by hand (R10), the Entra test objects deleted (U7's synced principal was gone from the account right after its Entra app was deleted; the users and group stayed until deleted there), the users and group AIM brought into the account deleted, `bootstrap/` destroyed (principal deleted outright, R14), and the project retired. The Terraform for the Entra side is kept as an example: [`examples/entra/`](../examples/entra/).
