#!/bin/bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR

# Determine kubectl invocation (prefer non-sudo)
if microk8s kubectl version --client >/dev/null 2>&1; then
	KUBECTL="microk8s kubectl"
elif sudo microk8s kubectl version --client >/dev/null 2>&1; then
	KUBECTL="sudo microk8s kubectl"
else
	echo "Error: microk8s kubectl not available (tried with and without sudo)" >&2
	exit 1
fi

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