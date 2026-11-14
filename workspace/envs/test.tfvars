state_bucket = "<project-id>-tfstate" # bootstrap output TF_STATE_BUCKET

# Entitlements for Entra groups assigned from the account stack
# (workspace_groups): without one, members reach the workspace and are refused
# (R18). Used in the use case test U4:
# group_entitlements = {
#   "<entra-group>" = { workspace_access = true }
# }
