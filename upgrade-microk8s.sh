#!/bin/bash
# Safety: fail fast and print diagnostics on errors
set -euo pipefail
set -o errtrace
trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR
function pause(){
    if [ -t 0 ]; then
        read -p 'Press [Enter] key to continue...'
    else
        sleep 10
    fi
}
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s version will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    microk8s kubectl get node "$nodeFQDN"
    sudo microk8s disable hostpath-storage:destroy-storage
    sudo microk8s kubectl drain "$nodeFQDN" --delete-emptydir-data --grace-period=600 --ignore-daemonsets --skip-wait-for-delete-timeout=3600
    echo 'Waiting for node to stop...'
    sleep 10
    microk8s kubectl get node
    microk8s kubectl get pod -o wide
    pause
    sudo ssh "$sshDest" sudo snap refresh microk8s --channel=1.34/stable
    sudo ssh "$sshDest" sudo snap refresh microk8s --hold
    sudo ssh "$sshDest" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "$sshDest" sudo microk8s addons repo update core
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
    microk8s kubectl get node "$nodeFQDN"
    pause
    sudo microk8s kubectl uncordon "$nodeFQDN"
    echo 'Waiting for node to start...'
    sleep 10
    microk8s kubectl get node
done
"$(dirname "$0")/upgrade-addons.sh"
