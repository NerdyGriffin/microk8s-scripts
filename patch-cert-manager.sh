#!/bin/bash
# Safety: fail fast and print diagnostics on errors
# Patch cert-manager deployment to add dns01 recursive nameserver args
# This script expects an optional environment variable KUBECTL to be set to
# the kubectl invocation (e.g. "microk8s kubectl" or "sudo microk8s kubectl").

set -euo pipefail
source "$(dirname "$0")/lib.sh"
set_common_trap
detect_kubectl
ensure_jq >/dev/null 2>&1 || echo "Continuing without jq (will use conservative JSON string checks)."

cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n cert-manager 2>/dev/null || true)
if [ -n "$cert_manager_json" ]; then
    if command -v jq >/dev/null 2>&1; then
        container_index=$(echo "$cert_manager_json" | jq '(.spec.template.spec.containers | to_entries[] | select(.value.name=="cert-manager-controller") | .key) // 0')
        if ! echo "$cert_manager_json" | jq -e ".spec.template.spec.containers[$container_index].args" >/dev/null 2>&1; then
            payload=$(printf '[{"op":"add","path":"/spec/template/spec/containers/%s/args","value":[]}]' "$container_index")
            $KUBECTL patch deployment cert-manager -n cert-manager --type='json' -p="$payload" >/dev/null 2>&1 || true
            cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n cert-manager 2>/dev/null || true)
        fi

        ensure_arg() {
            local arg="$1"
            if ! echo "$cert_manager_json" | jq -e ".spec.template.spec.containers[$container_index].args | index(\"$arg\")" >/dev/null 2>&1; then
                payload=$(printf '[{"op":"add","path":"/spec/template/spec/containers/%s/args/-","value":"%s"}]' "$container_index" "$arg")
                $KUBECTL patch deployment cert-manager -n cert-manager --type='json' -p="$payload"
                cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n cert-manager 2>/dev/null || true)
            fi
        }

        ensure_arg "--dns01-recursive-nameservers-only"
        ensure_arg "--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53"
    else
        # Fallback: conservative JSON-string checks, assume container 0
        $KUBECTL patch deployment cert-manager -n cert-manager --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":[]} ]' >/dev/null 2>&1 || true
        if ! echo "$cert_manager_json" | grep -q '"--dns01-recursive-nameservers-only"'; then
            $KUBECTL patch deployment cert-manager -n cert-manager --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers-only"}]'
        fi
        if ! echo "$cert_manager_json" | grep -q '"--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53"'; then
            $KUBECTL patch deployment cert-manager -n cert-manager --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers=1.1.1.1:53,1.0.0.1:53"}]'
        fi
    fi
else
    echo "Warning: cert-manager deployment not found in namespace cert-manager. Skipping DNS patch."
fi

# Display resulting args for the patched container so the user can verify changes.
echo
echo "--- cert-manager args after patch ---"
if [ -n "${cert_manager_json:-}" ]; then
    if command -v jq >/dev/null 2>&1; then
        # Re-fetch JSON to show the latest state
        cert_manager_json=$($KUBECTL get -o json deployment cert-manager -n cert-manager 2>/dev/null || true)
        container_index=$(echo "$cert_manager_json" | jq '(.spec.template.spec.containers | to_entries[] | select(.value.name=="cert-manager-controller") | .key) // 0')
        echo "Container index: $container_index"
        echo "$cert_manager_json" | jq -r ".spec.template.spec.containers[$container_index].args[]?" || true
    else
        # Use jsonpath to extract args (works with kubectl). jsonpath returns plain text.
        echo "Container index: 0"
        $KUBECTL get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | sed 's/ /\n/g' || true
    fi
else
    echo "No cert-manager JSON available to display args."
fi

exit 0
