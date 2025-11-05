#!/bin/bash
set -euo pipefail
set -o errtrace
trap 'rc=$?; echo "ERROR: ${BASH_SOURCE[0]}:$LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR
microk8s kubectl -n kube-system get pod | grep coredns | awk '{ print $1 }' | xargs microk8s kubectl -n kube-system logs