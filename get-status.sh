#!/bin/bash
nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    echo "$sshDest"
    # microk8s kubectl get node "$nodeFQDN"
    # ssh "$sshDest" microk8s status | head -n 4
done
