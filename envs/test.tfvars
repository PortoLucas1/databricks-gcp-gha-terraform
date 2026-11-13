project_id = "<project-id>"
region     = "us-central1"

# The test VM in gha-test-fe-vpc (testvm.tf). false removes it. While it is
# the self-hosted runner: true, e2-small (the runner, Node actions and
# Terraform don't fit in 1 GB) and Cloud NAT for its outbound traffic.
# Off until the workspace stack is needed (docs/REPRODUCE.md, step 4). Turn
# both on to run the workspace stack or the private half of psc-refusal, then
# register the runner (scripts/register-runner.sh).
fe_test_vm      = false
fe_test_vm_type = "e2-small"
fe_runner_nat   = false
