#!/usr/bin/env bash
# DESCRIPTION: Restart MicroK8s service on specified nodes (requires confirmation)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl

nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    # shellcheck disable=SC2207
    readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
fi
echo "The Microk8s service will be restarted on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -r -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" << EOF
sudo microk8s stop && sudo microk8s start && sudo microk8s status --wait
EOF
done
