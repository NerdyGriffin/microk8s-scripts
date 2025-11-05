#!/bin/bash
function pause(){
  if [ -t 0 ]; then
    read -p 'Press [Enter] key to continue...'
  else
    sleep 10
  fi
}
#pause
nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
datestamp="_"$(date '+%Y_%m_%d_%b')
mkdir -p /shared/microk8s/backend.bak
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" microk8s stop
done
#pause
#for nodeName in "${nodeArray[@]}"; do
#    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
#    sshDest="root@$nodeFQDN"
#    ssh "$sshDest" "tar -cvf /shared/microk8s/backend.bak/backup_$nodeName$datestamp.tar /var/snap/microk8s/current/var/kubernetes/backend"
#done
#pause
cat /var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml
#pause
sudo /snap/microk8s/current/bin/dqlite \
  -s 127.0.0.1:19001 \
  -c /var/snap/microk8s/current/var/kubernetes/backend/cluster.crt \
  -k /var/snap/microk8s/current/var/kubernetes/backend/cluster.key \
  k8s ".reconfigure /var/snap/microk8s/current/var/kubernetes/backend/ /var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml"
#pause
clear_backend_snapshots() {
    if [[ "$(hostname)" != "kube-10"* ]]; then
        echo "Removing any leftover snapshot, segment, and metadata files '$(hostname)'... "
        find /var/snap/microk8s/current/var/kubernetes/backend/ \( -name "snapshot-*-*-*" -o -name "snapshot-*-*-*.meta" -o -name "00000??????????*-000000??????????*" -o -name "open-??*" -o -name "metadata1" -o -name "metadata2" \) -delete
    fi
}
echo "Declared function clear_backend_snapshots()"
#pause
for nodeFQDN in "${nodeArray[@]}"; do
    if [[ "$nodeFQDN" != "kube-10"* ]]; then
        sshDest="root@$nodeFQDN"
        ssh -q "$sshDest" <<- EOF
            $(declare -f clear_backend_snapshots)
            clear_backend_snapshots
EOF
        # This is where you copy the stuff to the new node
        rsync -e 'ssh -q' -amvz \
            --include='cluster.yaml' \
            --include='snapshot-??*-??*-??*' \
            --include='snapshot-??*-??*-??*.meta' \
            --include='00000??????????*-000000??????????*' \
            --include='*/' \
            --exclude='*' \
            '/var/snap/microk8s/current/var/kubernetes/backend/' \
            "$sshDest":'/var/snap/microk8s/current/var/kubernetes/backend/'
    fi
done
#pause
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ssh "$sshDest" microk8s start
done
#pause
microk8s kubectl get node
