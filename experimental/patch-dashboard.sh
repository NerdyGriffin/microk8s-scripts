#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

# Patch dashboard service to assign a fixed LoadBalancer IP (experimental)
${KUBECTL} patch -n kubernetes-dashboard svc kubernetes-dashboard-kong-proxy --patch='{"spec":{"loadBalancerIP":"10.64.140.8","type": "LoadBalancer"}}'
# ${KUBECTL} patch -n kube-system svc kubernetes-dashboard --patch='{"spec":{"loadBalancerIP":"10.64.140.9","type": "LoadBalancer"}}'
