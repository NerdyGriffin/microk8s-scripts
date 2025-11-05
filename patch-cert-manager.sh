#!/bin/bash
# DESCRIPTION: Patch cert-manager deployment to add DNS01 recursive nameserver args
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap
detect_kubectl
ensure_jq >/dev/null 2>&1 || echo "Continuing without jq (will use fallback dedupe)."

# Configurables
NS="${NS:-cert-manager}"
CONTAINER="${CONTAINER:-cert-manager-controller}"
NAMESERVERS="${NAMESERVERS:-1.1.1.1:53,1.0.0.1:53}"

# Helper to build a strategic-merge patch payload targeting the container by name
build_patch_payload() {
    local args_json="$1"
    cat <<EOF
{"spec":{"template":{"spec":{"containers":[{"name":"$CONTAINER","args":$args_json}]}}}}
EOF
}

cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n "$NS" 2>/dev/null || true)
if [ -z "$cert_manager_json" ]; then
    echo "Warning: deployment cert-manager not found in namespace $NS. Skipping DNS patch."
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    # Current args for the named controller container
    current_args_json=$(echo "$cert_manager_json" | jq -c --arg name "$CONTAINER" '[.spec.template.spec.containers[] | select(.name==$name) | (.args // [])][0] // []')
    # Merge desired flags, dedupe while preserving first-seen order
    new_args_json=$(echo "$current_args_json" | jq --arg ns "$NAMESERVERS" '
        . + ["--dns01-recursive-nameservers-only", ("--dns01-recursive-nameservers="+$ns)]
        | reduce .[] as $a ([]; if index($a) then . else . + [$a] end)
    ')
    payload=$(build_patch_payload "$new_args_json")
    $KUBECTL patch deployment cert-manager -n "$NS" --type=strategic -p "$payload" >/dev/null
else
    # Fallback without jq: fetch current args space-separated, then dedupe preserving order
    current_args_str=$($KUBECTL get deployment cert-manager -n "$NS" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$CONTAINER')].args}" 2>/dev/null || true)
    dedup=""
    add_unique() {
        for a in "$@"; do
            case " $dedup " in *" $a "*) : ;; *) dedup="${dedup:+$dedup }$a" ;; esac
        done
    }
    # shellcheck disable=SC2206
    [ -n "$current_args_str" ] && add_unique ${current_args_str}
    add_unique "--dns01-recursive-nameservers-only" "--dns01-recursive-nameservers=$NAMESERVERS"
    if [ -n "$dedup" ]; then
        new_args_json="[\"$(printf '%s' "$dedup" | sed 's/"/\\"/g; s/ /","/g')\"]"
    else
        new_args_json="[]"
    fi
    payload=$(build_patch_payload "$new_args_json")
    $KUBECTL patch deployment cert-manager -n "$NS" --type=strategic -p "$payload" >/dev/null
fi

# Display resulting args for the patched container so the user can verify changes.
echo
echo "--- cert-manager args after patch ---"
if command -v jq >/dev/null 2>&1; then
    cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n "$NS" 2>/dev/null || true)
    echo "Container: $CONTAINER"
    echo "$cert_manager_json" | jq -r --arg name "$CONTAINER" '.spec.template.spec.containers[] | select(.name==$name) | (.args[]? // empty)'
else
    echo "Container: $CONTAINER"
    $KUBECTL get deployment cert-manager -n "$NS" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$CONTAINER')].args}" | sed 's/ /\n/g' || true
fi

exit 0
