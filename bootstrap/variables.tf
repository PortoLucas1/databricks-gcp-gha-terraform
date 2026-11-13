variable "project_id" {
  description = "The project the pipeline manages. It holds the workload identity pool, both identities and the state bucket here; a separate CI project works the same way."
  type        = string
}

variable "region" {
  description = "Region of the state bucket."
  type        = string
  default     = "us-central1"
}

variable "github" {
  description = "The one repository allowed to authenticate. Owner and repository IDs are GitHub's numeric IDs (https://api.github.com/repos/<owner>/<repo>: owner.id and id): names can be re-registered after deletion, IDs can't."
  type = object({
    owner         = string
    owner_id      = string
    repository    = string
    repository_id = string
  })

  validation {
    condition     = can(regex("^[0-9]+$", var.github.owner_id)) && can(regex("^[0-9]+$", var.github.repository_id))
    error_message = "owner_id and repository_id must be GitHub's numeric IDs, not names."
  }
}

variable "pool_id" {
  description = "Workload identity pool ID. A deleted pool's ID can't be reused for 30 days."
  type        = string
  default     = "github-actions"
}

variable "databricks_account_id" {
  description = "Databricks account ID."
  type        = string
}

variable "databricks_profile" {
  description = "Databricks CLI profile on the account console, for the person running this."
  type        = string
}
