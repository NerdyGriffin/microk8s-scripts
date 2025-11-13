#!/usr/bin/env bash
# DESCRIPTION: Validate MetalLB setup and ingress Service IP
# - Confirms ingress Service spec.loadBalancerIP and assigned status IP
# - Optionally checks any MetalLB IPAddressPool contains the expected CIDR

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
source "$ROOT_DIR/lib.sh"
set_common_trap
detect_kubectl
ensure_jq || true

EXPECTED_INGRESS_IP="10.64.140.1"
INGRESS_SVC_MANIFEST="$ROOT_DIR/manifests/ingress-service.yaml"

log() { echo "[$(date +%H:%M:%S)] $*"; }

if [ -f "$INGRESS_SVC_MANIFEST" ]; then
  expected_json="$(${KUBECTL} apply --dry-run=client -f "$INGRESS_SVC_MANIFEST" -o json)"
  svc_ns="$(echo "$expected_json" | jq -r '.metadata.namespace')"
  svc_name="$(echo "$expected_json" | jq -r '.metadata.name')"
  EXPECTED_INGRESS_IP="$(echo "$expected_json" | jq -r '.spec.loadBalancerIP // empty')"
else
  svc_ns="ingress"
  svc_name="ingress"
fi

log "Checking Service ${svc_ns}/${svc_name}..."
if ! live_json="$(${KUBECTL} -n "$svc_ns" get svc "$svc_name" -o json 2>/dev/null)"; then
  echo "FAIL: Service ${svc_ns}/${svc_name} not found" >&2
  exit 1
fi

live_type="$(echo "$live_json" | jq -r '.spec.type')"
live_spec_ip="$(echo "$live_json" | jq -r '.spec.loadBalancerIP // empty')"
live_status_ip="$(echo "$live_json" | jq -r '.status.loadBalancer.ingress[0].ip // empty')"

failures=()
if [ "$live_type" != "LoadBalancer" ]; then
  failures+=("spec.type expected LoadBalancer, got $live_type")
fi
if [ -n "$EXPECTED_INGRESS_IP" ] && [ "$live_spec_ip" != "$EXPECTED_INGRESS_IP" ]; then
  failures+=("spec.loadBalancerIP expected $EXPECTED_INGRESS_IP, got ${live_spec_ip:-<empty>}")
fi
if [ -n "$EXPECTED_INGRESS_IP" ] && [ "$live_status_ip" != "$EXPECTED_INGRESS_IP" ]; then
  failures+=("status.loadBalancer.ingress[0].ip expected $EXPECTED_INGRESS_IP, got ${live_status_ip:-<empty>}")
fi

if [ ${#failures[@]} -eq 0 ]; then
  log "PASS  Ingress Service has expected IP $EXPECTED_INGRESS_IP"
else
  log "FAIL  Ingress Service mismatches:"
  for f in "${failures[@]}"; do echo " - $f"; done
  exit_code=1
fi

# Check MetalLB IPAddressPool contains 10.64.140.0/24 (if CRD exists)
exit_code=${exit_code:-0}
CIDR_EXPECTED="10.64.140.0/24"
if ${KUBECTL} get crd ipaddresspools.metallb.io >/dev/null 2>&1; then
  pools_json="$(${KUBECTL} get ipaddresspools.metallb.io -A -o json)"
  if echo "$pools_json" | jq -e --arg cidr "$CIDR_EXPECTED" '.items[]?.spec.addresses[]? | select(. == $cidr)' >/dev/null; then
    log "PASS  A MetalLB IPAddressPool includes $CIDR_EXPECTED"
  else
    log "WARN  No MetalLB IPAddressPool advertising $CIDR_EXPECTED"
  fi
else
  log "INFO  MetalLB IPAddressPool CRD not found; skipping pool check"
fi

exit ${exit_code}
