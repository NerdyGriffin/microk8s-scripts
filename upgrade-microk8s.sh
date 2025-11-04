#!/bin/bash
function pause(){
    if [ -t 0 ]; then
        sleep 20
#        read -p 'Press [Enter] key to continue...'
    else
        sleep 10
    fi
}
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    read -p "Enter the hostname of the node you want to upgrade: " nodeName
    nodeArray+=( $nodeName )
fi
echo "The Microk8s version will be upgraded on the following nodes:"
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    echo "$nodeName = $nodeFQDN"
done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sudo microk8s disable hostpath-storage
    sudo microk8s kubectl drain "$nodeFQDN" --delete-emptydir-data --grace-period=600 --ignore-daemonsets --skip-wait-for-delete-timeout=3600
    echo 'Waiting for node to stop...'
    sleep 10
    sudo microk8s kubectl get node
    sudo microk8s kubectl get pod -o wide
    pause
    sudo ssh "root@$nodeFQDN" sudo snap refresh microk8s --channel=1.34/stable
    sudo ssh "root@$nodeFQDN" sudo snap refresh microk8s --hold
    sudo ssh "root@$nodeFQDN" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "root@$nodeFQDN" sudo microk8s addons repo update core
    sudo microk8s kubectl get node
    pause
    sudo microk8s kubectl uncordon "$nodeFQDN"
    echo 'Waiting for node to start...'
    sleep 10
    sudo microk8s kubectl get node
done
