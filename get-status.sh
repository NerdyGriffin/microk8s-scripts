#!/bin/bash
set -euo pipefail

# Shared helpers
source "$(dirname "$0")/lib.sh"
set_common_trap
detect_kubectl

readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    echo "$sshDest"
    # ${KUBECTL} get node "$nodeFQDN"
    # ssh "$sshDest" microk8s status | head -n 4
done
