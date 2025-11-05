#!/bin/bash
# Safety: fail fast and print diagnostics on errors
set -euo pipefail
source "$(dirname "$0")/lib.sh"
set_common_trap
detect_kubectl
ensure_jq >/dev/null 2>&1 || echo "Continuing without jq (will use conservative JSON string checks)."
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    # shellcheck disable=SC2207
    readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
fi
echo "The Microk8s addons will be upgraded on the following nodes:"
for nodeFQDN in "${nodeArray[@]}"; do echo "$nodeFQDN"; done
read -r -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
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
read -r -p "Continue? (y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] && {
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
"$(dirname "$0")/patch-cert-manager.sh"
echo '#--------------------------------'
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
