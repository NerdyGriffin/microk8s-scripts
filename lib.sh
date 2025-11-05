#!/bin/bash
# Common helpers for microk8s-scripts
# Keep this file small and POSIX-friendly for easy sourcing from scripts.

detect_kubectl() {
    # If caller pre-set KUBECTL, honor it
    if [ -n "${KUBECTL:-}" ]; then
        return 0
    fi
    if microk8s kubectl version --client >/dev/null 2>&1; then
        KUBECTL="microk8s kubectl"
    elif sudo microk8s kubectl version --client >/dev/null 2>&1; then
        KUBECTL="sudo microk8s kubectl"
    else
        echo "Error: microk8s kubectl not available (tried with and without sudo)" >&2
        return 1
    fi
    export KUBECTL
}

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    echo "jq not found — attempting to install jq with apt..."
    # Try apt-only (this repository targets Ubuntu). On failure return non-zero.
    sudo apt-get update && sudo apt-get install -y jq && return 0
    echo "Failed to install jq via apt. Continuing without jq." >&2
    return 1
}

pause() {
    if [ -t 0 ]; then
        # shellcheck disable=SC2162
        read -r -p 'Press [Enter] key to continue...'
    else
        sleep 10
    fi
}

export -f detect_kubectl ensure_jq pause 2>/dev/null || true

set_common_trap() {
    # Install a consistent ERR trap and enable errtrace for functions/subshells.
    set -o errtrace
    rc=0
    trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR
}

