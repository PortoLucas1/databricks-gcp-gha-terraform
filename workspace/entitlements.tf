# Entitlements for groups in the workspace (use case test U4, finding R18).
#
# Assigning a group to the workspace at account level (databricks/groups.tf)
# lets its members in, but gives the group no entitlement, and in this
# workspace the built-in users group carries none either: members are then
# refused with "not assigned or no Workspace access entitlement". The
# entitlement is set on the group inside the workspace. Empty by default.
variable "group_entitlements" {
  description = "Group display name => entitlements in the workspace. The group must already be in the workspace (assigned from the account stack)."
  type = map(object({
    workspace_access      = optional(bool, false)
    databricks_sql_access = optional(bool, false)
    workspace_consume     = optional(bool, false)
  }))
  default = {}
}

data "databricks_group" "entitled" {
  for_each     = var.group_entitlements
  display_name = each.key
}

resource "databricks_entitlements" "group" {
  for_each = var.group_entitlements

  # Unset rather than false: the provider refuses workspace_consume next to
  # workspace_access or databricks_sql_access even when one of them is false.
  group_id              = data.databricks_group.entitled[each.key].id
  workspace_access      = each.value.workspace_access ? true : null
  databricks_sql_access = each.value.databricks_sql_access ? true : null
  workspace_consume     = each.value.workspace_consume ? true : null
}
