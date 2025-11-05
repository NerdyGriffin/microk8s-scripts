#!/bin/bash
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    # read -p "Enter the hostname of the node you want to restart: " nodeName
    # nodeArray+=( $nodeName )
    nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s service will be restarted on the following nodes:"
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    echo "$nodeName = $nodeFQDN"
done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sshDest="root@$nodeFQDN"
    sudo ssh "$sshDest" << EOF
sudo microk8s stop && sudo microk8s start && sudo microk8s status --wait
EOF
done
