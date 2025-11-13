#!/usr/bin/env bash
# DESCRIPTION: Validate the nfs-csi StorageClass on the cluster matches manifests/sc-nfs.yaml
# - Compares key fields via kubectl dry-run (client) vs live cluster
# - Fields checked: metadata.name, provisioner, parameters.server, parameters.share,
#   reclaimPolicy, allowVolumeExpansion, volumeBindingMode, mountOptions

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
source "$ROOT_DIR/lib.sh"
set_common_trap
detect_kubectl
ensure_jq || true

MANIFEST_FILE="${ROOT_DIR}/manifests/sc-nfs.yaml"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Manifest not found at $MANIFEST_FILE" >&2
    exit 2
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Render expected object JSON from manifest using client-side dry-run
expected_json="$(${KUBECTL} apply --dry-run=client -f "$MANIFEST_FILE" -o json)"
expected_name="$(echo "$expected_json" | jq -r '.metadata.name')"
expected_provisioner="$(echo "$expected_json" | jq -r '.provisioner')"
expected_server="$(echo "$expected_json" | jq -r '.parameters.server')"
expected_share="$(echo "$expected_json" | jq -r '.parameters.share')"
expected_reclaim="$(echo "$expected_json" | jq -r '.reclaimPolicy')"
expected_expand="$(echo "$expected_json" | jq -r '.allowVolumeExpansion')"
expected_binding="$(echo "$expected_json" | jq -r '.volumeBindingMode')"
expected_mounts="$(echo "$expected_json" | jq -c '.mountOptions // []')"

log "Checking StorageClass '${expected_name}' exists..."
if ! live_json="$(${KUBECTL} get storageclass "$expected_name" -o json 2>/dev/null)"; then
    echo "FAIL: StorageClass '$expected_name' not found in cluster" >&2
    exit 1
fi

failures=()

check_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" != "$actual" ]; then
        failures+=("$label: expected='$expected' actual='$actual'")
    fi
}

live_provisioner="$(echo "$live_json" | jq -r '.provisioner')"
live_server="$(echo "$live_json" | jq -r '.parameters.server')"
live_share="$(echo "$live_json" | jq -r '.parameters.share')"
live_reclaim="$(echo "$live_json" | jq -r '.reclaimPolicy')"
live_expand="$(echo "$live_json" | jq -r '.allowVolumeExpansion')"
live_binding="$(echo "$live_json" | jq -r '.volumeBindingMode')"
live_mounts="$(echo "$live_json" | jq -c '.mountOptions // []')"

check_eq provisioner "$expected_provisioner" "$live_provisioner"
check_eq parameters.server "$expected_server" "$live_server"
check_eq parameters.share "$expected_share" "$live_share"
check_eq reclaimPolicy "$expected_reclaim" "$live_reclaim"
check_eq allowVolumeExpansion "$expected_expand" "$live_expand"
check_eq volumeBindingMode "$expected_binding" "$live_binding"
check_eq mountOptions "$expected_mounts" "$live_mounts"

if [ ${#failures[@]} -eq 0 ]; then
    log "PASS  StorageClass '$expected_name' matches manifest ($MANIFEST_FILE)"
    exit 0
else
    log "FAIL  StorageClass '$expected_name' differs from manifest:"
    for f in "${failures[@]}"; do echo " - $f"; done
    exit 1
fi
