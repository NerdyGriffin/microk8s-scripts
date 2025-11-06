#!/bin/bash
# DESCRIPTION: Upgrade MicroK8s addons and apply configuration patches
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl
ensure_jq
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    # shellcheck disable=SC2207
    readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
fi
echo "The Microk8s addons will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -r -p "Continue? (Y/n): " confirm && [[ $confirm == [nN] || $confirm == [nN][oO] ]] && exit 1
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ${KUBECTL} get node "$nodeFQDN"
    sudo ssh "$sshDest" sudo snap alias microk8s.kubectl kubectl
    sudo ssh "$sshDest" sudo microk8s addons repo update core
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
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
  # 'observability'
  'rbac'
)
${KUBECTL} apply -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
echo 'Would you like to reinstall the core addons (forced upgrade)?'
read -r -p "WARNING: This WILL result is downtime for all services and ingress. (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] && {
    for addonName in "${addonList[@]}"; do
        echo '#--------------------------------'
        echo "Disabling $addonName... "
        sudo microk8s disable "$addonName"
    done
    ${KUBECTL} delete -f /var/snap/microk8s/common/addons/core/addons/metallb/crd.yaml
}
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
# shellcheck disable=SC2207
readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ${KUBECTL} get node "$nodeFQDN"
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
done
export KUBECTL="${KUBECTL:-microk8s kubectl}"

# Patch cert-manager deployment with custom DNS resolvers (see patch-cert-manager.sh)
"$(dirname "$0")/patch-cert-manager.sh"

echo '#--------------------------------'
# Assign static LoadBalancer IP to Kubernetes Dashboard (10.64.140.8)
${KUBECTL} -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'

# Apply CoreDNS custom configuration (adds custom upstream DNS servers and rewrites)
${KUBECTL} -n kube-system patch configmap/coredns --patch-file="$(dirname "$0")/manifests/coredns-patch.yaml"

# Assign static LoadBalancer IP to kube-dns service for external DNS queries (10.64.140.10)
${KUBECTL} -n kube-system patch svc kube-dns --patch='{"spec":{"loadBalancerIP":"10.64.140.10","type": "LoadBalancer"}}'

# Apply ingress LoadBalancer service with static IP (10.64.140.1) and TURN/STUN ports
${KUBECTL} apply -f "$(dirname "$0")/manifests/ingress-service.yaml"

# Ingress controller tweaks: disable server tokens and configure TURN for Nextcloud Talk
# Hide NGINX server tokens (equivalent to `server_tokens off;`)
${KUBECTL} -n ingress patch configmap nginx-load-balancer-microk8s-conf --type merge -p '{"data":{"server-tokens":"false"}}' || true

# Route TURN/STUN traffic (UDP/TCP 3478) to the nextcloud-talk service via ingress UDP/TCP configmaps
# These configmaps are watched by the controller; it will reload automatically
${KUBECTL} -n ingress patch configmap nginx-ingress-udp-microk8s-conf --type merge -p '{"data":{"3478":"default/nextcloud-talk:3478"}}' || true
${KUBECTL} -n ingress patch configmap nginx-ingress-tcp-microk8s-conf --type merge -p '{"data":{"3478":"default/nextcloud-talk:3478"}}' || true

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
${KUBECTL} apply -f deploy/crds
${KUBECTL} apply -f deploy/rbac
${KUBECTL} apply -f deploy/manifests
${KUBECTL} get -n origin-ca-issuer pod
echo '#--------------------------------'
echo -n "Change directory to $initialWorkDir...  "
cd "$initialWorkDir" && echo 'Done' || echo
echo 'Applying custom ClusterIssuer and OriginIssuer from manifest... '
${KUBECTL} apply -f "$(dirname "$0")/../manifests/cluster-issuer.yaml"
${KUBECTL} apply -f "$(dirname "$0")/../manifests/origin-issuer.yaml"
echo
echo 'Done'
