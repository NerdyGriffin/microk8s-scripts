#!/bin/bash
nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sleep 10
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" shutdown
done
