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
    # read -p "Enter the hostname of the node you want to upgrade: " nodeName
    # nodeArray+=( $nodeName )
    nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s version will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do
    echo "$nodeName = $nodeFQDN"
done
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
echo 'Would you like to reinstall the core addons (forced upgrade)?'
echo 'WARNING: This WILL result is downtime for all services and ingress.'
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
addonList=(
  'cert-manager'
  'dashboard'
  'dns'
  # 'ha-cluster'
  # 'helm'
  # 'helm3'
  'ingress'
  'metallb'
  'metrics-server'
  'observability'
  'rbac'
)
sudo microk8s kubectl apply -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
for addonName in "${addonList[@]}"; do
    echo '#--------------------------------'
    echo "Disabling $addonName... "
    sudo microk8s disable "$addonName"
done
sudo microk8s kubectl delete -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
sudo microk8s disable hostpath-storage:destroy-storage
for addonName in "${addonList[@]}"; do
    echo '#--------------------------------'
    echo "Enabling $addonName... "
    case "$addonName" in
        "dns")
            sudo microk8s enable dns:1.1.1.1
            ;;
        *"metallb"*)
            sudo microk8s enable "$addonName" '10.64.140.0/24'
            ;;
        *)
            sudo microk8s enable "$addonName"
            ;;
    esac
done
sudo microk8s disable hostpath-storage:destroy-storage
nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    microk8s kubectl get node "$nodeFQDN"
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
done
sudo microk8s kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
sudo microk8s kubectl -n kube-system patch configmap/coredns --patch-file="$(dirname "$0")/coredns-patch.yaml"
# sudo microk8s kubectl -n kube-system edit configmap/coredns
sudo microk8s kubectl -n kube-system patch svc kube-dns --patch='{"spec":{"loadBalancerIP":"10.64.140.10","type": "LoadBalancer"}}'
sudo microk8s kubectl apply -f "$(dirname "$0")/ingress-service.yaml"
