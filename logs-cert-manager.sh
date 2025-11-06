#!/usr/bin/env bash
set -euo pipefail
trap 'rc=$?; echo "ERROR: line $LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR

# Use KUBECTL wrapper if set, else default to microk8s kubectl
KUBECTL="${KUBECTL:-microk8s kubectl}"

# Get the cert-manager pod name
POD_NAME=$($KUBECTL get pods -n cert-manager -l app.kubernetes.io/name=cert-manager -o jsonpath='{.items[0].metadata.name}')

if [[ -z "$POD_NAME" ]]; then
  echo "No cert-manager pod found in namespace cert-manager." >&2
  exit 1
fi

# Get the container name from the deployment (default: cert-manager-controller)
CONTAINER_NAME=$($KUBECTL get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].name}')

if [[ -z "$CONTAINER_NAME" ]]; then
  echo "No container found in deployment/cert-manager." >&2
  exit 1
fi

# Output logs for the container
$KUBECTL logs "$POD_NAME" -c "$CONTAINER_NAME" -n cert-manager
