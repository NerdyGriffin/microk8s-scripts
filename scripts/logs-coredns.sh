#!/usr/bin/env bash
# DESCRIPTION: Collect and display CoreDNS pod logs from kube-system namespace
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl

# Collect coredns pod names robustly and print their logs one-by-one
pods=$(${KUBECTL} -n kube-system get pod -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
pods=$(echo "$pods" | tr ' ' '\n' | grep coredns || true)
if [ -z "$pods" ]; then
	echo "No coredns pods found in kube-system"
	exit 0
fi
for p in $pods; do
	${KUBECTL} -n kube-system logs "$p" || true
done