#!/bin/bash
# Safety: fail fast and print diagnostics on errors
set -euo pipefail

# Shared helpers
source "$(dirname "$0")/lib.sh"
set_common_trap

# Shared helpers
source "$(dirname "$0")/lib.sh"
detect_kubectl

readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    sleep 10
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" shutdown
done
