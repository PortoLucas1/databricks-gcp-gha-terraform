#!/usr/bin/env bash
# Registers fe-test-vm as this repository's self-hosted GitHub Actions runner,
# label gha-test-fe, and runs it as a service under its own user, ghrunner,
# which has no sudo. Run by a person, on the VM, from their OS Login account:
#
#   gcloud compute scp scripts/register-runner.sh fe-test-vm:register-runner.sh --zone us-central1-a --project <project> --tunnel-through-iap
#     (a destination relative to the home directory: on Windows, gcloud copies
#     with PuTTY's pscp, which doesn't expand ~ and names the file "~")
#   gcloud compute ssh fe-test-vm --zone us-central1-a --project <project> --tunnel-through-iap
#   bash register-runner.sh <owner>/<repo>
#
# It asks for a registration token: GitHub, the repository's Settings ->
# Actions -> Runners -> New self-hosted runner, the --token value in the
# config command. Valid for an hour and used once here; this script never
# writes it to disk. The runner then keeps its own credential in its install
# directory, readable by ghrunner only.
#
# Needs outbound internet (var.fe_runner_nat). Remove the runner with:
#   cd /home/ghrunner/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh uninstall
#   sudo -u ghrunner ./config.sh remove --token <removal token from the same page>
set -euo pipefail

REPO="${1:?usage: register-runner.sh <owner>/<repo>}"
VERSION="2.338.2"
SHA256="baebf204307bac6193480852732f0aba2ae97b6c5597c244f4d5558390147c40"
RUNNER_USER="ghrunner"
DIR="/home/${RUNNER_USER}/actions-runner"
TARBALL="actions-runner-linux-x64-${VERSION}.tar.gz"

# Every step in the runner's directory runs as ghrunner or root: its home may
# be 0700, closed to the person running this.
as_runner() { sudo -u "$RUNNER_USER" env "$@"; }
in_dir() { sudo bash -c "cd '$DIR' && $1"; }

id "$RUNNER_USER" >/dev/null 2>&1 || sudo useradd --create-home --shell /bin/bash "$RUNNER_USER"
as_runner mkdir -p "$DIR"

as_runner bash -c "cd '$DIR' && curl -fsSLo '$TARBALL' 'https://github.com/actions/runner/releases/download/v${VERSION}/${TARBALL}' \
  && echo '${SHA256}  ${TARBALL}' | sha256sum -c - \
  && tar xzf '$TARBALL' && rm '$TARBALL'"

in_dir "./bin/installdependencies.sh"
# setup-terraform extracts with unzip; the workflow's summaries use jq.
sudo apt-get install -y --no-install-recommends unzip jq

read -rsp "Registration token: " TOKEN; echo
as_runner RUNNER_TOKEN="$TOKEN" bash -c "cd '$DIR' && ./config.sh --unattended \
  --url 'https://github.com/${REPO}' --token \"\$RUNNER_TOKEN\" \
  --name \"\$(hostname)\" --labels gha-test-fe --no-default-labels --replace"
unset TOKEN

in_dir "./svc.sh install '$RUNNER_USER' && ./svc.sh start && ./svc.sh status | head -5"
