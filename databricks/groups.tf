# Workspace access for account groups, by display name (use case test U3).
#
# With Entra AIM, a group is visible here only once it has been added to the
# account from Entra (account console). Groups nested inside it can't be read
# or managed through the API or Terraform, though their members get access.
# Empty by default: the reference build assigns no groups.
variable "workspace_groups" {
  description = "Account group display name => permissions on the scenario B workspace (USER or ADMIN)."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for p in flatten(values(var.workspace_groups)) : contains(["USER", "ADMIN"], p)])
    error_message = "Permissions are USER or ADMIN."
  }
}

data "databricks_group" "workspace" {
  for_each     = var.workspace_groups
  display_name = each.key
}

resource "databricks_mws_permission_assignment" "group_psc" {
  for_each = var.workspace_groups

  workspace_id = restful_resource.workspace_psc.output.workspace_id
  principal_id = tonumber(data.databricks_group.workspace[each.key].id)
  permissions  = each.value
}
