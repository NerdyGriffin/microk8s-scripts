#!/usr/bin/env bash
# DESCRIPTION: Display Ceph cluster status from rook-ceph-external namespace
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

${KUBECTL} --namespace rook-ceph-external get cephcluster
