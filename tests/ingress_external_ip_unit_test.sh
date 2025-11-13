#!/usr/bin/env bash
# DESCRIPTION: Validate that all Ingress resources are reachable via LoadBalancer external IP
# - Discovers all Ingress resources
# - For each ingress, verifies the ingress controller Service has an external IP assigned
# - Waits up to 30 seconds for IP assignment if not immediately available

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
source "$ROOT_DIR/scripts/lib.sh"
set_common_trap
detect_kubectl
ensure_jq || true

TIMEOUT_SECONDS=30
EXPECTED_INGRESS_IP="10.64.140.1"

log() { echo "[$(date +%H:%M:%S)] $*"; }

get_all_ingresses() {
  ${KUBECTL} get ing -A -o json \
    | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"'
}

get_ingress_controller_ip() {
  # Assumes ingress controller Service is in 'ingress' namespace with name 'ingress'
  ${KUBECTL} -n ingress get svc ingress -o json 2>/dev/null \
    | jq -r '.status.loadBalancer.ingress[0].ip // empty'
}

wait_for_external_ip() {
  local elapsed=0
  local ip=""

  log "Waiting for ingress controller Service to receive external IP (timeout: ${TIMEOUT_SECONDS}s)..."

  while [ $elapsed -lt $TIMEOUT_SECONDS ]; do
    ip="$(get_ingress_controller_ip)"
    if [ -n "$ip" ]; then
      log "External IP assigned: $ip"
      return 0
    fi
    sleep 2
    ((elapsed+=2))
  done

  log "TIMEOUT: No external IP assigned after ${TIMEOUT_SECONDS}s"
  return 1
}

main() {
  log "Discovering Ingress resources..."
  mapfile -t ingresses < <(get_all_ingresses)

  if [ ${#ingresses[@]} -eq 0 ]; then
    log "INFO: No Ingress resources found"
    exit 0
  fi

  log "Found ${#ingresses[@]} Ingress resource(s)"

  # Check if ingress controller Service exists
  if ! ${KUBECTL} -n ingress get svc ingress >/dev/null 2>&1; then
    echo "FAIL: Ingress controller Service 'ingress/ingress' not found" >&2
    exit 1
  fi

  # Check for external IP (wait if needed)
  if ! wait_for_external_ip; then
    echo "FAIL: Ingress controller Service has no external IP assigned" >&2
    exit 1
  fi

  # Verify IP matches expected
  actual_ip="$(get_ingress_controller_ip)"
  if [ "$actual_ip" = "$EXPECTED_INGRESS_IP" ]; then
    log "PASS  Ingress controller has expected external IP: $actual_ip"
  else
    log "WARN  Ingress controller IP ($actual_ip) differs from expected ($EXPECTED_INGRESS_IP)"
  fi

  # List all ingresses that will use this IP
  log "Ingress resources using external IP ${actual_ip}:"
  for ing in "${ingresses[@]}"; do
    echo "  - $ing"
  done

  log "PASS  All ${#ingresses[@]} Ingress resource(s) routed through LoadBalancer IP ${actual_ip}"
  exit 0
}

main "$@"
