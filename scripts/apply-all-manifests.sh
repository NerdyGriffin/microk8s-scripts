#!/usr/bin/env bash
# DESCRIPTION: Apply all Kubernetes manifests from manifests/ directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

MANIFESTS_DIR="$(dirname "$DIR")/manifests"

if [ ! -d "$MANIFESTS_DIR" ]; then
  echo "ERROR: Manifests directory not found: $MANIFESTS_DIR" >&2
  exit 1
fi

echo "Applying all manifests from $MANIFESTS_DIR..."
${KUBECTL} apply -f "$MANIFESTS_DIR/"
echo "Done"
