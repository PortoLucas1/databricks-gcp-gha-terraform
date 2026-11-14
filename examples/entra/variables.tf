variable "entra_tenant_id" {
  description = "The Entra tenant behind the Databricks account's SSO and AIM."
  type        = string
}

variable "databricks_account_id" {
  type = string
}

variable "databricks_profile" {
  description = "Databricks CLI profile on the account console, as an account admin."
  type        = string
}

variable "github" {
  description = "The repository whose main branch the pipeline principal trusts. IDs are numeric (R1)."
  type = object({
    owner         = string
    owner_id      = string
    repository    = string
    repository_id = string
  })
}

# Groups people get workspace access from: name => existing members (user
# principal names) and groups nested inside it. Only the outer group is added
# to the Databricks account from Entra; the nested ones work through it (R17).
variable "groups" {
  description = "Entra group display name => members (UPNs) and nested group names."
  type = map(object({
    members       = optional(list(string), [])
    nested_groups = optional(list(string), [])
  }))
  default = {}
}

# Option C: create the Entra app registration for the pipeline principal.
variable "pipeline_principal_name" {
  description = "Display name of the Entra app registration that becomes the pipeline's Databricks principal. Null skips option C."
  type        = string
  default     = null
}

# Second step of option C, after the principal has been added to the
# Databricks account from Entra (AIM): its account role and federation policy.
variable "pipeline_principal_provisioned" {
  description = "Set true once the Entra principal has been added to the Databricks account from Entra."
  type        = bool
  default     = false
}

# Option B, untested in the lab: let Databricks accept Entra-issued tokens
# through an account-wide federation policy. Needs an audience used for
# nothing else (an application ID URI on a dedicated app).
variable "entra_token_exchange" {
  description = "Option B (untested): account federation policy trusting the Entra issuer. Null keeps it off."
  type = object({
    audience      = string
    subject_claim = optional(string, "azp")
  })
  default = null
}
