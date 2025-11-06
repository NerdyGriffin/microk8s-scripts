#!/bin/bash
# DESCRIPTION: Inspect a dqlite snapshot file (limited - explains why sqlite3 doesn't work)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap

# Check if snapshot argument provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <snapshot-file>" >&2
  echo "" >&2
  echo "Example:" >&2
  echo "  $0 /home/setup/microk8s/backend.restore/snapshot-2724-474356418-108804203" >&2
  echo "" >&2
  echo "NOTE: Dqlite snapshots cannot be read with sqlite3. This script provides" >&2
  echo "basic file information only. To inspect the actual data, you must:" >&2
  echo "  1. Restore the snapshot to a running cluster" >&2
  echo "  2. Use the dqlite CLI to query the restored state" >&2
  echo "  3. Or use dump-dqlite-state.sh on a running cluster" >&2
  exit 1
fi

SNAPSHOT="$1"

# Check if file exists
if [ ! -f "$SNAPSHOT" ]; then
  echo "Error: Snapshot file not found: $SNAPSHOT" >&2
  exit 1
fi

echo "Inspecting dqlite snapshot file: $SNAPSHOT"
echo "========================================"
echo ""

# Show file metadata
echo "File information:"
ls -lh "$SNAPSHOT"
echo ""

# Show file type
echo "File type:"
file "$SNAPSHOT"
echo ""

# Try to show first few bytes (hex dump)
echo "First 64 bytes (hex):"
xxd -l 64 "$SNAPSHOT" || hexdump -C -n 64 "$SNAPSHOT"
echo ""

# Check for dqlite magic bytes or headers
echo "Checking for dqlite format markers..."
if xxd -l 16 "$SNAPSHOT" 2>/dev/null | grep -q "6471 6c69 7465"; then
  echo "✓ File appears to contain dqlite format markers"
elif strings -n 8 "$SNAPSHOT" | head -20 | grep -qi "dqlite\|raft\|snapshot"; then
  echo "✓ File contains dqlite/raft-related strings"
else
  echo "⚠ Could not confirm dqlite format (might still be valid)"
fi
echo ""

echo "========================================"
echo "IMPORTANT: Dqlite snapshots cannot be opened with sqlite3."
echo ""
echo "To inspect the actual database content, you must:"
echo "  1. Use dump-dqlite-state.sh on a running cluster, or"
echo "  2. Restore this snapshot and query via dqlite CLI:"
echo ""
echo "     sudo /snap/microk8s/current/bin/dqlite \\"
echo "       -s 127.0.0.1:19001 \\"
echo "       -c /var/snap/microk8s/current/var/kubernetes/backend/cluster.crt \\"
echo "       -k /var/snap/microk8s/current/var/kubernetes/backend/cluster.key \\"
echo "       k8s"
echo ""
echo "For snapshot restoration, see: repair-database-quorum.sh"