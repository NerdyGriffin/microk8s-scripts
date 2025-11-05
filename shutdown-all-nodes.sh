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

nodeArray=( $(${KUBECTL} get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sleep 10
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" shutdown
done
