#!/bin/bash
# Determine kubectl invocation (prefer non-sudo)
if microk8s kubectl version --client >/dev/null 2>&1; then
    KUBECTL="microk8s kubectl"
elif sudo microk8s kubectl version --client >/dev/null 2>&1; then
    KUBECTL="sudo microk8s kubectl"
else
    echo "Error: microk8s kubectl not available (tried with and without sudo)" >&2
    exit 1
fi

# Ensure jq is installed. This script runs on Ubuntu, so try apt-only.
ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    echo "jq not found — attempting to install jq with apt..."
    # Attempt non-interactive apt install; if sudo isn't available or install fails
    # we return non-zero and the caller will fall back to text-based checks.
    sudo apt-get update && sudo apt-get install -y jq && return 0
    echo "Failed to install jq via apt. Please install jq manually if you want precise JSON handling." >&2
    return 1
}

# Try to ensure jq is present, but continue on failure (we have a grep fallback)
ensure_jq >/dev/null 2>&1 || echo "Continuing without jq (will use conservative JSON string checks)."
function pause(){
    if [ -t 0 ]; then
        read -p 'Press [Enter] key to continue...'
    else
        sleep 10
    fi
}
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    nodeArray=( $(${KUBECTL} get nodes | awk 'NR > 1 {print $1}') )
fi
echo "The Microk8s addons will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
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
echo 'WARNING: This WILL result is downtime for all services and ingress.'
read -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] && {
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
nodeArray=( $(${KUBECTL} get nodes | awk 'NR > 1 {print $1}') )
for nodeFQDN in "${nodeArray[@]}"; do
    sshDest="root@$nodeFQDN"
    ${KUBECTL} get node "$nodeFQDN"
    sudo ssh "$sshDest" 'sudo sed -i "s|^\(--resolv-conf=\).*$|\1/run/systemd/resolve/resolv.conf|" /var/snap/microk8s/current/args/kubelet'
done
export KUBECTL="${KUBECTL:-microk8s kubectl}"
"$(dirname "$0")/patch-cert-manager.sh"
${KUBECTL} -n kubernetes-dashboard patch svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
${KUBECTL} -n kube-system patch configmap/coredns --patch-file="$(dirname "$0")/coredns-patch.yaml"
# ${KUBECTL} -n kube-system edit configmap/coredns
${KUBECTL} -n kube-system patch svc kube-dns --patch='{"spec":{"loadBalancerIP":"10.64.140.10","type": "LoadBalancer"}}'
${KUBECTL} apply -f "$(dirname "$0")/ingress-service.yaml"

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
${KUBECTL} apply -f "$(dirname "$0")/../manifest/cluster-issuer.yaml"
${KUBECTL} apply -f "$(dirname "$0")/../manifest/origin-issuer.yaml"
echo
echo 'Done'
