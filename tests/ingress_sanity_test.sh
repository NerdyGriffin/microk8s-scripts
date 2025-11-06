#!/bin/bash
# DESCRIPTION: Validate ingress endpoints over HTTPS and TLS certificates for all Ingress hosts
# - Discovers all hosts from kubernetes Ingress resources
# - For each host:
#   * curl -I https://host to verify HTTP connectivity (accept 2xx/3xx)
#   * openssl s_client to fetch the certificate, ensure SAN contains the host
# - Also verifies TURN configmaps (TCP/UDP 3478 mapping) for Nextcloud Talk if present

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
source "$ROOT_DIR/lib.sh"
set_common_trap
detect_kubectl
ensure_jq

ok_count=0
fail_count=0
failed_hosts=()

log() { echo "[$(date +%H:%M:%S)] $*"; }

get_all_hosts() {
  ${KUBECTL} get ing -A -o json \
    | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $n | (.spec.rules[]?.host // empty) | select(. != "")'
}

check_http() {
  local host="$1"
  # Use GET and accept common app responses as 'reachable'
  local code
  code=$(curl -sSL --max-time 20 "https://${host}/" -o /dev/null -w '%{http_code}' || echo "000")
  case "$code" in
    2*|3*|400|401|403|405|501) echo "$code"; return 0 ;;
    *) echo "$code"; return 1 ;;
  esac
}

extract_san_names() {
  # Reads a PEM cert on stdin and prints SAN DNS names (one per line)
  # Try modern -ext output first; fallback to -text parsing if needed
  local san
  san="$(openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -o 'DNS:[^, ]*' | sed 's/^DNS://')"
  if [ -n "$san" ]; then
    echo "$san"
    return 0
  fi
  openssl x509 -noout -text 2>/dev/null \
    | sed -n '/Subject Alternative Name/,/X509v3/{p}' \
    | grep -o 'DNS:[^,\n]*' \
    | sed 's/^DNS://'
}

check_cert_matches_host() {
  local host="$1"
  # Fetch server cert; verify it includes host in SAN list
  local pem san
  if ! pem=$(timeout 10 bash -lc "openssl s_client -servername ${host} -connect ${host}:443 </dev/null 2>/dev/null | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p'"); then
    return 1
  fi
  san="$(echo "$pem" | extract_san_names || true)"
  if ! echo "$san" | grep -Fxq "$host"; then
    return 1
  fi
  return 0
}

test_host() {
  local host="$1"
  local http_code=""
  if http_code=$(check_http "$host"); then
    if check_cert_matches_host "$host"; then
      log "PASS  ${host} (HTTP ${http_code}, cert SAN includes host)"
      ((ok_count++))
      return 0
    else
      log "FAIL  ${host} (HTTP ${http_code}, cert SAN missing host)"
      failed_hosts+=("${host}: cert_san_missing")
      ((fail_count++))
      return 1
    fi
  else
    log "FAIL  ${host} (HTTP ${http_code})"
    failed_hosts+=("${host}: http_${http_code}")
    ((fail_count++))
    return 1
  fi
}

check_turn_config() {
  # Validate that ingress TURN configmaps route 3478 only to default/nextcloud-talk:3478
  local tcp udp
  tcp=$(${KUBECTL} -n ingress get cm nginx-ingress-tcp-microk8s-conf -o json 2>/dev/null | jq -r '.data["3478"] // empty') || true
  udp=$(${KUBECTL} -n ingress get cm nginx-ingress-udp-microk8s-conf -o json 2>/dev/null | jq -r '.data["3478"] // empty') || true
  if [[ "$tcp" == "default/nextcloud-talk:3478" && "$udp" == "default/nextcloud-talk:3478" ]]; then
    log "PASS  TURN configmaps map 3478 TCP/UDP to default/nextcloud-talk:3478"
  else
    log "WARN  TURN configmaps not set as expected (tcp=${tcp:-<none>}, udp=${udp:-<none>})"
  fi
}

main() {
  log "Discovering ingress hosts..."
  mapfile -t hosts < <(get_all_hosts | sort -u)
  if [ ${#hosts[@]} -eq 0 ]; then
    log "No ingress hosts found."
    exit 0
  fi
  log "Testing ${#hosts[@]} hosts..."
  for h in "${hosts[@]}"; do
    test_host "$h" || true
  done
  check_turn_config || true

  echo
  log "Summary: PASS=${ok_count} FAIL=${fail_count}"
  if [ ${fail_count} -gt 0 ]; then
    printf 'Failed hosts:\n'
    for fh in "${failed_hosts[@]}"; do echo " - $fh"; done
    exit 1
  fi
}

main "$@"
