#!/usr/bin/env bash
# DESCRIPTION: Shutdown all MicroK8s cluster nodes via SSH (destructive operation)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl

readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    sleep 10
    echo '----'
    echo "$nodeFQDN"
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" shutdown
done
