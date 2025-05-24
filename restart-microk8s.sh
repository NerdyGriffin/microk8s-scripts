#!/bin/bash
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    read -p "Enter the hostname of the node you want to restart: " nodeName
    nodeArray+=( $nodeName )
fi
echo "The Microk8s service will be restarted on the following nodes:"
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    echo "$nodeName = $nodeFQDN"
done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    # sudo ssh "root@$nodeFQDN" sudo microk8s stop
    # sudo ssh "root@$nodeFQDN" sudo microk8s start
    # sudo ssh "root@$nodeFQDN" sudo microk8s status --wait
    sudo ssh "root@$nodeFQDN" << EOF
sudo microk8s stop && sudo microk8s start && sudo microk8s status --wait
EOF
done
