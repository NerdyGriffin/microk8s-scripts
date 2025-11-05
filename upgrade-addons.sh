#!/bin/bash
sudo echo "Starting MicroK8s addons upgrade process..."
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
echo "The Microk8s addons will be upgraded on the following nodes:"
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    echo "$nodeName = $nodeFQDN"
done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sshDest="root@$nodeFQDN"
    microk8s kubectl get node "$nodeFQDN"
    sudo microk8s disable hostpath-storage:destroy-storage
    sudo ssh "$sshDest" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "$sshDest" sudo microk8s addons repo update core
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
    microk8s kubectl get node "$nodeFQDN"
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
microk8s kubectl apply -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
for addonName in "${addonList[@]}"; do
    echo '#--------------------------------'
    echo "Disabling $addonName... "
    sudo microk8s disable "$addonName"
done
microk8s kubectl delete -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
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
for nodeName in "${nodeArray[@]}"; do
    nodeFQDN=$(sudo ssh "root@$nodeName" hostname)
    sshDest="root@$nodeFQDN"
    microk8s kubectl get node "$nodeFQDN"
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
done
cert_manager_json=$(microk8s kubectl get -o json deployment cert-manager -n cert-manager 2>/dev/null)
if [ -n "$cert_manager_json" ]; then
    if ! echo "$cert_manager_json" | jq -e '.spec.template.spec.containers[0].args // [] | index("--dns01-recursive-nameservers-only")' >/dev/null; then
        microk8s kubectl patch deployment cert-manager -n cert-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--dns01-recursive-nameservers-only"}]'
    fi
    if ! echo "$cert_manager_json" | jq -e '.spec.template.spec.containers[0].args // [] | index("--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53")' >/dev/null; then
        microk8s kubectl patch deployment cert-manager -n cert-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53"}]'
    fi
else
    echo "Warning: cert-manager deployment not found in namespace cert-manager. Skipping DNS patch."
fi
microk8s kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
microk8s kubectl -n kube-system patch configmap/coredns --patch-file="$(dirname "$0")/coredns-patch.yaml"
# microk8s kubectl -n kube-system edit configmap/coredns
microk8s kubectl -n kube-system patch svc kube-dns --patch='{"spec":{"loadBalancerIP":"10.64.140.10","type": "LoadBalancer"}}'
microk8s kubectl apply -f "$(dirname "$0")/ingress-service.yaml"

# Reinstall origin-ca-issuer from https://github.com/cloudflare/origin-ca-issuer
initialWorkDir="$(pwd)"
origin_ca_issuer_dir="$(dirname "$0")/../origin-ca-issuer"
echo '#--------------------------------'
echo -n "Change directory to $origin_ca_issuer_dir...  "
cd "$origin_ca_issuer_dir" && echo 'Done' || echo
echo -n 'Fetching remote changes...  '
git fetch && echo 'Done' || echo
echo -n 'Attempting to pull latest origin-ca-issuer...  '
{ # try
    git pull
} || { # catch
    echo 'Git pull failed. Performing hard reset...  ' && git fetch origin && git reset --hard origin/trunk
}
echo '#--------------------------------'
echo 'Installing Origin CA Issuer... '
microk8s kubectl apply -f deploy/crds
microk8s kubectl apply -f deploy/rbac
microk8s kubectl apply -f deploy/manifests
microk8s kubectl get -n origin-ca-issuer pod
echo '#--------------------------------'
echo -n "Change directory to $initialWorkDir...  "
cd "$initialWorkDir" && echo 'Done' || echo
echo 'Applying custom ClusterIssuer and OriginIssuer from manifest... '
microk8s kubectl apply -f "$(dirname "$0")/../manifest/cluster-issuer.yaml"
microk8s kubectl apply -f "$(dirname "$0")/../manifest/origin-issuer.yaml"
echo
echo 'Done'
