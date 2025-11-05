#!/bin/bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR

# Determine kubectl invocation (prefer non-sudo)
if microk8s kubectl version --client >/dev/null 2>&1; then
    KUBECTL="microk8s kubectl"
elif sudo microk8s kubectl version --client >/dev/null 2>&1; then
    KUBECTL="sudo microk8s kubectl"
else
    echo "Error: microk8s kubectl not available (tried with and without sudo)" >&2
    exit 1
fi

nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    nodeArray=( $(${KUBECTL} get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s service will be restarted on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" << EOF
sudo microk8s stop && sudo microk8s start && sudo microk8s status --wait
EOF
done
