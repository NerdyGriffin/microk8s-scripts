#!/bin/bash
# Safety: fail fast and print diagnostics on errors
set -euo pipefail
source "$(dirname "$0")/lib.sh"
set_common_trap
detect_kubectl
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    # shellcheck disable=SC2207
    readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
fi
echo "The Microk8s version will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -r -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ${KUBECTL} get node "$nodeFQDN"
    sudo microk8s disable hostpath-storage:destroy-storage
    ${KUBECTL} drain "$nodeFQDN" --delete-emptydir-data --grace-period=600 --ignore-daemonsets --skip-wait-for-delete-timeout=3600
    echo 'Waiting for node to stop...'
    sleep 10
    ${KUBECTL} get node
    ${KUBECTL} get pod -o wide
    pause
    sudo ssh "$sshDest" sudo snap refresh microk8s --channel=1.34/stable
    sudo ssh "$sshDest" sudo snap refresh microk8s --hold
    sudo ssh "$sshDest" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "$sshDest" sudo microk8s addons repo update core
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
    ${KUBECTL} get node "$nodeFQDN"
    pause
    ${KUBECTL} uncordon "$nodeFQDN"
    echo 'Waiting for node to start...'
    sleep 10
    ${KUBECTL} get node
done
bash "$(dirname "$0")/upgrade-addons.sh"
