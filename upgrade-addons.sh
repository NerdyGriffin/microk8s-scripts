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
    nodeArray=( $(microk8s kubectl get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s version will be upgraded on the following nodes:"
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    echo "$nodeName = $nodeFQDN"
done
echo 'Would you like to reinstall the core addons (forced upgrade)?'
echo 'WARNING: This WILL result is downtime for all services and ingress.'
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sudo microk8s kubectl get node "$nodeFQDN"
    sudo microk8s disable hostpath-storage:destroy-storage
    sudo ssh "root@$nodeFQDN" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "root@$nodeFQDN" sudo microk8s addons repo update core
    sudo ssh "root@$nodeFQDN" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
    sudo microk8s kubectl get node "$nodeFQDN"
done
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
for addonName in ${addonList[*]}; do
    echo '----------------'
    echo "Disabling $addonName... "
    sudo microk8s disable "$addonName"
done
sudo microk8s disable hostpath-storage:destroy-storage
for addonName in ${addonList[*]}; do
    echo '----------------'
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
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sudo microk8s kubectl get node "$nodeFQDN"
    sudo ssh "root@$nodeFQDN" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
done
sudo microk8s kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
sudo microk8s kubectl -n kube-system patch configmap/coredns --patch-file="$(dirname "$0")/coredns-patch.yaml"
# sudo microk8s kubectl -n kube-system edit configmap/coredns
sudo microk8s kubectl -n kube-system patch svc kube-dns --patch='{"spec":{"loadBalancerIP":"10.64.140.10","type": "LoadBalancer"}}'
sudo microk8s kubectl apply -f "$(dirname "$0")/ingress-service.yaml"
