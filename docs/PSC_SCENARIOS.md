# Private Service Connect scenarios

In the target scenario, workspaces are reached privately over Private Service Connect (PSC). Two designs fit that, and the lab builds both, because it wasn't settled which one the scenario needs. Either way the GitHub Actions flow is the same: workspace creation is an account API call, made by GitHub-hosted runners with the federated Databricks token and the Google token header, through the REST provider (see [TEST_PLAN.md](TEST_PLAN.md)). PSC changes what exists around the workspace, not how Terraform authenticates.

## The two PSC paths

| Path | Traffic | Endpoints | Needed to create the workspace? |
|---|---|---|---|
| **Front end** | Users and workspace-level automation to the workspace URL | One endpoint on the workspace attachment (`plproxy`), in the users' VPC, plus private access settings with public access off | No |
| **Back end** | The classic compute plane to the control plane | Two endpoints in the workspace's VPC: the workspace REST API (`plproxy`) and the secure cluster connectivity relay (`ngrok`), listed in the workspace's network configuration | No, but it's part of the network configuration the workspace is created with |

The account API (`accounts.gcp.databricks.com`) is public in both: PSC and private access settings govern a workspace's URL, not the account. That's why both scenarios can be built from GitHub-hosted runners.

## Scenario A: front end only

Users reach the workspace privately; clusters reach the control plane over the internet, through Cloud NAT.

1. **GCP stack:** the workspace VPC and subnet. Cloud NAT before any cluster runs.
2. **Account stack (REST provider):** network configuration, without endpoints. Workspace.
3. **Private access settings**, attached at creation or later. The lab attached them to an existing workspace (C6, attempt 3), so this can come after creation. Public access stays on until step 4.
4. **Front end, when ready:** a front-end endpoint in the users' VPC; its registration (REST provider); private DNS there for the workspace URL, `dp-` name and `psc-auth`; private access settings switched to public access off, with the endpoint allowed.

**Risk:** adding back-end PSC later means moving the workspace to a new network configuration that lists the endpoints. The account API reference allows a network change on customer-managed VPCs, but its wording is AWS's. Not verified on GCP. If GCP refuses, back-end PSC needs a new workspace.

In the lab: `gha-test-classic` in `gha-test-vpc`. Private access settings attached and reverted through the REST provider. No front-end endpoint yet.

## Scenario B: back end from creation, front end added the same way as A

Clusters reach the control plane only through the back-end endpoints; nothing in the compute plane needs an internet route to Databricks.

1. **GCP stack:** the workspace VPC with a compute subnet and an endpoint subnet; the two back-end endpoints; a private `gcp.databricks.com` zone bound to that VPC with:
   - `<region>.psc.gcp.databricks.com` and the workspace's URL and `dp-` name to the REST endpoint,
   - `tunnel.<region>.gcp.databricks.com` to the relay endpoint.

   The workspace names can only be added once the workspace exists. The zone answers every Databricks name in that VPC, so a workspace without back-end PSC can't share the VPC.
2. **Account stack (REST provider):** register both endpoints (registration is what moves them from `PENDING` to `ACCEPTED`, and they bill from creation); a network configuration listing them as `rest_api` and `dataplane_relay`; the workspace on that network configuration.
3. **GCP stack again:** the workspace's two DNS records.
4. **Front end:** as scenario A, step 4.

**Cost:** each endpoint is about $0.01 an hour ($7.30 a month). The back end is two per VPC, shared by every workspace in it.

In the lab: `gha-test-psc` in `gha-test-psc-vpc` (`psc.tf` in both stacks).

## The front end in the lab

`gha-test-fe-vpc` stands in for the users' network (`frontend.tf`): one endpoint on the workspace attachment, and DNS overrides for each workspace's URL and `dp-` name and the region's `psc-auth` name.

**Users' DNS: override names, don't take over the domain.** A Cloud DNS private zone for `gcp.databricks.com` is the only authority for that whole domain in the VPC it's bound to: any name it doesn't list is NXDOMAIN. That includes `accounts.gcp.databricks.com`, where the workspace's login redirects users, and which CI needs for the token exchange and the account API. The lab first built the users' side as such a zone, then replaced it with a **response policy**: one rule per workspace name, every other name resolved publicly. On-premises resolvers get the same effect with conditional forwarding of the listed names only. The compute plane's side can be a whole-domain zone (back end, `psc.tf`): it needs no other Databricks name. The endpoint is registered like the back-end ones, and the private access settings shared by both workspaces turn public access off once it is. Level `ACCOUNT`: any endpoint registered in the account is let in. `ENDPOINT`, with only the listed front ends allowed, is tighter; how it treats the back-end REST endpoint on GCP isn't verified.

With public access off, workspace-level Terraform can't run on GitHub-hosted runners: it needs a runner in a network that reaches the front-end endpoint and resolves through its zone, `gha-test-fe-vpc`'s client subnet here.

## Choosing

| | A: front end only | B: back end from creation |
|---|---|---|
| User access | Private | Private |
| Cluster traffic to Databricks | Internet, through Cloud NAT | Private |
| Endpoints | 1 (front end) | 3 (2 back end, 1 front end) |
| Workspace VPC | Can be shared with other workspaces without back-end PSC | One private DNS view: only back-end PSC workspaces |
| Adding the other path later | Back end: unverified on GCP, may need a new workspace | Nothing to add |

Recommendation, unless the organization needs otherwise: B. It costs two endpoints, and A's only way to B may be rebuilding the workspace.
