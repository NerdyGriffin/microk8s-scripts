#!/usr/bin/env bash
# DESCRIPTION: Run all infrastructure unit tests and aggregate results
# - Executes all test scripts in tests/ directory
# - Reports pass/fail count and exits non-zero if any test fails

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Change to root directory so tests can source lib.sh
cd "$ROOT_DIR"

declare -a tests=(
    "ingress_unit_test.sh"
    "ingress_external_ip_unit_test.sh"
    "metallb_unit_test.sh"
    "storageclass_nfs_csi_unit_test.sh"
)

pass_count=0
fail_count=0
failed_tests=()

log "Running ${#tests[@]} infrastructure unit tests..."
echo

for test in "${tests[@]}"; do
    test_path="$DIR/$test"
    if [ ! -x "$test_path" ]; then
        log "SKIP  $test (not executable or not found)"
        continue
    fi

    log "Running $test..."
    if "$test_path"; then
    ((pass_count++)) || true
        log "✓ PASS $test"
    else
    ((fail_count++)) || true
        failed_tests+=("$test")
        log "✗ FAIL $test"
    fi
    echo
done

echo "========================================"
log "Summary: PASS=${pass_count} FAIL=${fail_count}"
echo "========================================"

if [ ${fail_count} -gt 0 ]; then
    echo "Failed tests:"
    for ft in "${failed_tests[@]}"; do
        echo " - $ft"
    done
    exit 1
fi

log "All tests passed!"
exit 0
