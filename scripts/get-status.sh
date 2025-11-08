#!/usr/bin/env bash
# DESCRIPTION: Display basic status of all MicroK8s cluster nodes (read-only)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl

readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ${KUBECTL} get node "$nodeFQDN"
    ssh "$sshDest" microk8s status | head -n 4
done
