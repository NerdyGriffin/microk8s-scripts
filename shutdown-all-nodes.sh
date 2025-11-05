#!/bin/bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR
nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sleep 10
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" shutdown
done
