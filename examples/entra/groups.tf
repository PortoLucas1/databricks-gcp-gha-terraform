# Entra groups for workspace access (use case tests U3 and U4).
#
# After applying: add each outer group to the Databricks account from Entra
# (account console), then assign it with workspace_groups (databricks/) and
# entitle it with group_entitlements (workspace/). An assignment without the
# entitlement lets members in and then refuses them (R18). Members of a
# nested group get the outer group's access, though the nested group itself
# never appears in Databricks (R17).

locals {
  nested = toset(flatten([for g in values(var.groups) : g.nested_groups]))
  memberships = merge([
    for name, g in var.groups : { for upn in g.members : "${name}|${upn}" => { group = name, upn = upn } }
  ]...)
  nestings = merge([
    for name, g in var.groups : { for n in g.nested_groups : "${name}|${n}" => { group = name, nested = n } }
  ]...)
}

resource "azuread_group" "access" {
  for_each = setunion(toset(keys(var.groups)), local.nested)

  display_name     = each.key
  security_enabled = true
  description      = "Databricks workspace access (assigned and entitled by Terraform in the gha-databricks-test stacks)."
}

# Members are existing users. Creating users here would put their passwords
# in state; people come from the directory as they already are.
data "azuread_user" "member" {
  for_each            = toset([for m in values(local.memberships) : m.upn])
  user_principal_name = each.key
}

resource "azuread_group_member" "user" {
  for_each = local.memberships

  group_object_id  = azuread_group.access[each.value.group].object_id
  member_object_id = data.azuread_user.member[each.value.upn].object_id
}

resource "azuread_group_member" "nested" {
  for_each = local.nestings

  group_object_id  = azuread_group.access[each.value.group].object_id
  member_object_id = azuread_group.access[each.value.nested].object_id
}

output "groups_to_add_from_entra" {
  description = "Outer groups to add to the Databricks account from Entra before the stacks assign them."
  value       = sort(keys(var.groups))
}
