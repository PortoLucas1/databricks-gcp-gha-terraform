#!/usr/bin/env bash
# End-to-end check: own-IdP (Entra-style) dual-token auth + LPM workspace create.
# Does NOT use Google ID tokens. Does NOT grant firewall permissions to the creator SA.
#
# Usage:
#   ACCOUNT_ID=f187f55a-9d3d-463b-aa1a-d55818b704c9 \
#   PROJECT=gcp-sandbox-field-eng \
#   DBX_PROFILE=gcp-lpw-test \
#   ./scripts/validate-lpm-entra.sh
set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
export CLOUDSDK_CORE_YES=1

ACCOUNT_ID=${ACCOUNT_ID:?set ACCOUNT_ID}
PROJECT=${PROJECT:?set PROJECT}
REGION=${REGION:-us-central1}
DBX_PROFILE=${DBX_PROFILE:?set DBX_PROFILE}
PREFIX=${PREFIX:-lpmval}
API="https://accounts.gcp.databricks.com/api/2.0/accounts/${ACCOUNT_ID}"
CREATOR="${PREFIX}-creator@${PROJECT}.iam.gserviceaccount.com"
WORKDIR=$(mktemp -d)
trap 'echo "workdir $WORKDIR"' EXIT

dbt() { databricks auth token --profile "$DBX_PROFILE" | jq -r .access_token; }
gat() { gcloud auth print-access-token --impersonate-service-account="$CREATOR" 2>/dev/null; }

log() { printf '%s\n' "$*"; }

# --- roles (idempotent create) ---
create_role() {
  local id=$1 title=$2 file=$3
  if gcloud iam roles describe "projects/${PROJECT}/roles/${id}" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud iam roles update "$id" --project="$PROJECT" --file="$file" --quiet >/dev/null || true
    log "role $id exists"
  elif gcloud iam roles create "$id" --project="$PROJECT" --file="$file" --quiet >/dev/null 2>"$WORKDIR/${id}.err"; then
    log "role $id created"
  elif grep -q "already exists" "$WORKDIR/${id}.err"; then
    log "role $id already exists"
  else
    cat "$WORKDIR/${id}.err" >&2
    return 1
  fi
}

cat >"$WORKDIR/creator.yaml" <<'EOF'
title: "LPM validate creator"
description: "Read-only LPM creator for validate-lpm-entra.sh"
stage: GA
includedPermissions:
- compute.networks.get
- compute.projects.get
- compute.subnetworks.get
- compute.subnetworks.getIamPolicy
- iam.roles.get
- iam.serviceAccounts.get
- iam.serviceAccounts.getIamPolicy
- resourcemanager.projects.get
- resourcemanager.projects.getIamPolicy
- serviceusage.services.get
- serviceusage.services.list
EOF
cat >"$WORKDIR/op-project.yaml" <<'EOF'
title: "LPM validate operator project"
stage: GA
includedPermissions:
- compute.disks.list
- compute.globalOperations.list
- compute.instances.list
- compute.regionOperations.list
- compute.regions.get
- compute.reservations.get
- compute.reservations.list
- compute.spotAssistants.get
- compute.zoneOperations.list
- compute.zones.get
- compute.zones.list
- iam.serviceAccounts.actAs
- resourcemanager.projects.get
- serviceusage.quotas.get
- serviceusage.services.list
- storage.buckets.list
EOF
cat >"$WORKDIR/op-resource.yaml" <<'EOF'
title: "LPM validate operator resource"
stage: GA
includedPermissions:
- compute.disks.create
- compute.disks.delete
- compute.disks.get
- compute.disks.resize
- compute.disks.setLabels
- compute.disks.update
- compute.disks.use
- compute.disks.useReadOnly
- compute.instances.attachDisk
- compute.instances.create
- compute.instances.delete
- compute.instances.detachDisk
- compute.instances.get
- compute.instances.getGuestAttributes
- compute.instances.getSerialPortOutput
- compute.instances.setLabels
- compute.instances.setMetadata
- compute.instances.setServiceAccount
- compute.instances.setTags
- compute.instances.update
- storage.buckets.create
- storage.buckets.delete
- storage.buckets.get
- storage.buckets.getIamPolicy
- storage.buckets.setIamPolicy
- storage.buckets.update
- storage.multipartUploads.abort
- storage.multipartUploads.create
- storage.multipartUploads.list
- storage.multipartUploads.listParts
- storage.objects.create
- storage.objects.delete
- storage.objects.get
- storage.objects.list
- storage.objects.update
EOF
cat >"$WORKDIR/op-network.yaml" <<'EOF'
title: "LPM validate operator network"
stage: GA
includedPermissions:
- compute.subnetworks.get
- compute.subnetworks.use
EOF

create_role "${PREFIX}_creator" "LPM validate creator" "$WORKDIR/creator.yaml"
create_role "${PREFIX}_op_project" "LPM validate op project" "$WORKDIR/op-project.yaml"
create_role "${PREFIX}_op_resource" "LPM validate op resource" "$WORKDIR/op-resource.yaml"
create_role "${PREFIX}_op_network" "LPM validate op network" "$WORKDIR/op-network.yaml"

# --- creator SA: ONLY the creator role (proves no firewall perms needed) ---
if ! gcloud iam service-accounts describe "$CREATOR" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${PREFIX}-creator" --project="$PROJECT" --display-name="LPM validate creator" >/dev/null
fi
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${CREATOR}" \
  --role="projects/${PROJECT}/roles/${PREFIX}_creator" \
  --condition=None --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$CREATOR" --project="$PROJECT" \
  --member="user:$(gcloud config get-value account 2>/dev/null)" \
  --role="roles/iam.serviceAccountTokenCreator" --quiet >/dev/null

# --- network (admin creates VPC; creator SA never touches firewalls) ---
VPC="${PREFIX}-vpc"
SUBNET="${PREFIX}-subnet"
if ! gcloud compute networks describe "$VPC" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute networks create "$VPC" --project="$PROJECT" --subnet-mode=custom --bgp-routing-mode=regional >/dev/null
  gcloud compute networks subnets create "$SUBNET" --project="$PROJECT" --network="$VPC" --region="$REGION" \
    --range=10.91.0.0/20 --enable-private-ip-google-access >/dev/null
  # Pre-created by "network team" (this script's admin identity, not the creator SA)
  gcloud compute firewall-rules create "${PREFIX}-allow-internal" --project="$PROJECT" --network="$VPC" \
    --direction=INGRESS --priority=65534 --source-ranges=10.91.0.0/20 --action=ALLOW --rules=all >/dev/null
  gcloud compute routers create "${PREFIX}-router" --project="$PROJECT" --network="$VPC" --region="$REGION" >/dev/null
  gcloud compute routers nats create "${PREFIX}-nat" --project="$PROJECT" --router="${PREFIX}-router" --region="$REGION" \
    --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges >/dev/null
fi
log "network ready"

# Prove Google ID token auth fails on this account (SSO on)
IDT=$(gcloud auth print-identity-token --audiences=https://accounts.gcp.databricks.com 2>/dev/null || echo "")
if [[ -z "$IDT" ]]; then
  log "OK: could not mint Google ID token (treated as refused)"
else
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 -H "Authorization: Bearer ${IDT}" "$API/workspaces" || true)
  [[ "$CODE" != "200" ]] || { log "FAIL: Google ID token unexpectedly worked (http $CODE)"; exit 1; }
  log "OK: Google ID token refused (http $CODE) — own-IdP path required"
fi

DT=$(dbt)
AT=$(gat)
[[ -n "$AT" ]] || { log "FAIL: could not mint creator access token"; exit 1; }

# --- dual-token network config ---
NET=$(curl -s -X POST "$API/networks" \
  -H "Authorization: Bearer $DT" -H "X-Databricks-GCP-SA-Access-Token: $AT" -H "Content-Type: application/json" \
  -d "{\"network_name\":\"${PREFIX}-net\",\"gcp_network_info\":{\"network_project_id\":\"$PROJECT\",\"vpc_id\":\"$VPC\",\"subnet_id\":\"$SUBNET\",\"subnet_region\":\"$REGION\"}}")
echo "$NET" | jq -e .network_id >/dev/null || { log "FAIL network: $NET"; exit 1; }
NET_ID=$(echo "$NET" | jq -r .network_id)
log "OK: network $NET_ID (dual token)"

PAS=$(curl -s -X POST "$API/private-access-settings" \
  -H "Authorization: Bearer $DT" -H "Content-Type: application/json" \
  -d "{\"private_access_settings_name\":\"${PREFIX}-pas\",\"region\":\"$REGION\",\"public_access_enabled\":true,\"private_access_level\":\"ACCOUNT\"}")
PAS_ID=$(echo "$PAS" | jq -r .private_access_settings_id)
log "OK: PAS $PAS_ID"

# --- LPM phase 1 ---
WS=$(curl -s -X POST "$API/workspaces" \
  -H "Authorization: Bearer $DT" -H "X-Databricks-GCP-SA-Access-Token: $AT" -H "Content-Type: application/json" \
  -d "{\"workspace_name\":\"${PREFIX}-ws\",\"cloud\":\"gcp\",\"cloud_resource_container\":{\"gcp\":{\"project_id\":\"$PROJECT\"}},\"location\":\"$REGION\",\"pricing_tier\":\"ENTERPRISE\",\"expected_workspace_status\":\"PROVISIONING\"}")
echo "$WS" | jq -e .workspace_id >/dev/null || { log "FAIL workspace create: $WS"; exit 1; }
WSID=$(echo "$WS" | jq -r .workspace_id)
WSSA=$(echo "$WS" | jq -r .gcp_workspace_service_account)
[[ "$(echo "$WS" | jq -r .workspace_status)" == "PROVISIONING" ]] || { log "FAIL: expected PROVISIONING"; exit 1; }
log "OK: workspace $WSID PROVISIONING sa=$WSSA"

# --- LPM phase 2: operator grants ---
gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$WSSA" \
  --role="projects/${PROJECT}/roles/${PREFIX}_op_project" --condition=None --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$WSSA" \
  --role="projects/${PROJECT}/roles/${PREFIX}_op_resource" \
  --condition="title=${PREFIX}-scope,expression=resource.name.extract(\"{x}databricks\") != \"\" && resource.name.extract(\"{x}${WSID}\") != \"\"" \
  --quiet >/dev/null
gcloud compute networks subnets add-iam-policy-binding "$SUBNET" --project="$PROJECT" --region="$REGION" \
  --member="serviceAccount:$WSSA" --role="projects/${PROJECT}/roles/${PREFIX}_op_network" --quiet >/dev/null
log "OK: operator roles granted"

# --- LPM phase 3: attach ---
AT=$(gat); DT=$(dbt)
curl -s -X PATCH "$API/workspaces/$WSID" \
  -H "Authorization: Bearer $DT" -H "X-Databricks-GCP-SA-Access-Token: $AT" -H "Content-Type: application/json" \
  -d "{\"network_id\":\"$NET_ID\",\"private_access_settings_id\":\"$PAS_ID\"}" >/dev/null

for i in $(seq 1 30); do
  DT=$(dbt)
  ST=$(curl -s "$API/workspaces/$WSID" -H "Authorization: Bearer $DT" | jq -r .workspace_status)
  log "poll $i: $ST"
  case "$ST" in RUNNING) break ;; FAILED|BANNED) log "FAIL: $ST"; exit 1 ;; esac
  sleep 20
done
[[ "$ST" == "RUNNING" ]] || { log "FAIL: not RUNNING"; exit 1; }
log "OK: workspace RUNNING"

FQDN=$(curl -s "$API/workspaces/$WSID" -H "Authorization: Bearer $DT" | jq -r .workspace_fqdn)
SV=$(curl -s -H "Authorization: Bearer $DT" "https://${FQDN}/api/2.1/clusters/spark-versions" \
  | jq -r '[.versions[] | select(.key|test("^[0-9]+\\.[0-9]+\\.x-scala2\\.1[23]$"))] | last | .key')
CID=$(curl -s -X POST -H "Authorization: Bearer $DT" -H "Content-Type: application/json" \
  "https://${FQDN}/api/2.1/clusters/create" \
  -d "{\"cluster_name\":\"${PREFIX}-node\",\"spark_version\":\"$SV\",\"node_type_id\":\"n2-standard-4\",\"num_workers\":0,\"autotermination_minutes\":10,\"data_security_mode\":\"SINGLE_USER\",\"spark_conf\":{\"spark.databricks.cluster.profile\":\"singleNode\",\"spark.master\":\"local[*]\"},\"custom_tags\":{\"ResourceClass\":\"SingleNode\"}}" \
  | jq -r .cluster_id)
[[ "$CID" != "null" && -n "$CID" ]] || { log "FAIL: cluster create"; exit 1; }
for i in $(seq 1 40); do
  DT=$(dbt)
  CST=$(curl -s -H "Authorization: Bearer $DT" "https://${FQDN}/api/2.1/clusters/get?cluster_id=$CID" | jq -r .state)
  log "cluster poll $i: $CST"
  case "$CST" in RUNNING) break ;; ERROR|TERMINATED) log "FAIL cluster $CST"; exit 1 ;; esac
  sleep 15
done
[[ "$CST" == "RUNNING" ]] || { log "FAIL: cluster not RUNNING"; exit 1; }
log "OK: cluster RUNNING"

# teardown
DT=$(dbt); AT=$(gat)
curl -s -X POST -H "Authorization: Bearer $DT" -H "Content-Type: application/json" \
  "https://${FQDN}/api/2.1/clusters/delete" -d "{\"cluster_id\":\"$CID\"}" >/dev/null || true
curl -s -X DELETE "$API/workspaces/$WSID" -H "Authorization: Bearer $DT" -H "X-Databricks-GCP-SA-Access-Token: $AT" >/dev/null
for i in $(seq 1 40); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API/workspaces/$WSID" -H "Authorization: Bearer $(dbt)")
  [[ "$CODE" == "404" ]] && break
  sleep 15
done
curl -s -X DELETE "$API/networks/$NET_ID" -H "Authorization: Bearer $(dbt)" -H "X-Databricks-GCP-SA-Access-Token: $(gat)" >/dev/null || true
curl -s -X DELETE "$API/private-access-settings/$PAS_ID" -H "Authorization: Bearer $(dbt)" >/dev/null || true
# leave VPC/roles for inspection unless CLEANUP_GCP=1
if [[ "${CLEANUP_GCP:-0}" == "1" ]]; then
  gcloud compute routers nats delete "${PREFIX}-nat" --router="${PREFIX}-router" --region="$REGION" --project="$PROJECT" --quiet || true
  gcloud compute routers delete "${PREFIX}-router" --region="$REGION" --project="$PROJECT" --quiet || true
  gcloud compute firewall-rules delete "${PREFIX}-allow-internal" --project="$PROJECT" --quiet || true
  gcloud compute networks subnets delete "$SUBNET" --region="$REGION" --project="$PROJECT" --quiet || true
  gcloud compute networks delete "$VPC" --project="$PROJECT" --quiet || true
fi

log "PASS: Entra-style dual-token + LPM workspace + cluster"
