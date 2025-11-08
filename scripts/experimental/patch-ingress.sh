#!/usr/bin/env bash
# DESCRIPTION: Patch ingress nginx ConfigMaps to enable forwarded-for headers (experimental)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

${KUBECTL} patch -n ingress ConfigMap nginx-ingress-tcp-microk8s-conf --patch='{"data":{"compute-full-forwarded-for":"true","enable-real-ip":"true"}}'
${KUBECTL} patch -n ingress ConfigMap nginx-ingress-udp-microk8s-conf --patch='{"data":{"compute-full-forwarded-for":"true","enable-real-ip":"true"}}'