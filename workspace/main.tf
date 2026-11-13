# ---------------------------------------------------------------------------
# Workspace-level Terraform for gha-test-psc, whose public access is off.
#
# Runs only on the self-hosted runner in gha-test-fe-vpc (workflow
# workspace.yml): the workspace URL answers only through the front-end
# endpoint there. The Databricks provider authenticates as the automation
# principal on github-oidc, so the token exchange itself, at the workspace's
# own /oidc/v1/token, also goes through PSC. The principal is workspace admin
# through the account stack (databricks/main.tf).
#
# C8 / H8: a workspace object through the provider on federation, SSO on.
# ---------------------------------------------------------------------------

terraform {
  required_version = "~> 1.15"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.142"
    }
  }

  # Same bucket as the other stacks, its own prefix (-backend-config).
  backend "gcs" {}
}

variable "state_bucket" {
  description = "The bucket that holds every stack's state."
  type        = string
}

# The workspace's URL, from the account stack that created it. It resolves to
# the front-end endpoint on the runner.
data "terraform_remote_state" "account" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "terraform/databricks"
  }
}

# No credentials: the workflow sets DATABRICKS_AUTH_TYPE=github-oidc and
# DATABRICKS_CLIENT_ID.
provider "databricks" {
  host = data.terraform_remote_state.account.outputs.workspace_psc.url
}

# Free: a policy is a rule set, nothing runs.
resource "databricks_cluster_policy" "small" {
  name = "gha-test-small"
  definition = jsonencode({
    autotermination_minutes = { type = "fixed", value = 20 }
    num_workers             = { type = "range", maxValue = 1 }
    node_type_id            = { type = "allowlist", values = ["e2-standard-4", "n2-standard-4"] }
  })
}

# The back-end test: a cluster can only start if its nodes reach the control
# plane through gha-test-psc-vpc's back-end endpoints (REST API and relay) and
# resolve through its private zone. That VPC has no other route out; images
# and the workspace's buckets come through Private Google Access.
#
# Single node, n2-standard-4 (e2-standard-4 needed persistent SSD quota the
# lab's project didn't have), under the policy above, so it stops itself 20 minutes
# after its last use. Terraform waits for RUNNING on create.
data "databricks_spark_version" "lts" {
  long_term_support = true
}

# The automation principal, whose dedicated cluster this is.
data "databricks_current_user" "me" {}

resource "databricks_cluster" "backend_test" {
  cluster_name                = "gha-test-backend-psc"
  spark_version               = data.databricks_spark_version.lts.id
  node_type_id                = "n2-standard-4"
  policy_id                   = databricks_cluster_policy.small.id
  apply_policy_default_values = true
  num_workers                 = 0
  autotermination_minutes     = 20

  # Dedicated (single user) access mode. The first apply left it unset, which
  # is no isolation, and a Unity Catalog workspace refuses that: "NO_ISOLATION
  # or custom access modes are not allowed in this workspace".
  data_security_mode = "SINGLE_USER"
  single_user_name   = data.databricks_current_user.me.user_name

  spark_conf = {
    "spark.databricks.cluster.profile" = "singleNode"
    "spark.master"                     = "local[*]"
  }

  custom_tags = {
    ResourceClass = "SingleNode"
  }
}

output "backend_test_cluster" {
  description = "The back-end test cluster's id and state after create."
  value = {
    id    = databricks_cluster.backend_test.id
    state = databricks_cluster.backend_test.state
  }
}

output "cluster_policy_id" {
  description = "The policy's id, from the workspace API through PSC."
  value       = databricks_cluster_policy.small.id
}
