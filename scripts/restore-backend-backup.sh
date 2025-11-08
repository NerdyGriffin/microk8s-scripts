#!/usr/bin/env bash
# filepath: /home/setup/microk8s/scripts/restore-database-backup.sh
# DESCRIPTION: Restore MicroK8s dqlite backend from tar backup (advanced/dangerous - stops cluster)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set_common_trap

# Check for backup file argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <backup-tar-file> [node-name]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  # Restore to current node from backup" >&2
  echo "  $0 /shared/microk8s/backend.bak/backup_kube-11_2025_08_20_Aug.tar" >&2
  echo "" >&2
  echo "  # Restore to specific node" >&2
  echo "  $0 /shared/microk8s/backend.bak/backup_kube-11_2025_08_20_Aug.tar kube-11" >&2
  echo "" >&2
  echo "WARNING: This will stop MicroK8s and replace the backend database!" >&2
  exit 1
fi

BACKUP_TAR="$1"
TARGET_NODE="${2:-$(hostname)}"

# Verify backup file exists
if [ ! -f "$BACKUP_TAR" ]; then
  echo "Error: Backup file not found: $BACKUP_TAR" >&2
  exit 1
fi

echo "========================================"
echo "MicroK8s Database Restore"
echo "========================================"
echo "Backup file: $BACKUP_TAR"
echo "Target node: $TARGET_NODE"
echo ""
echo "WARNING: This operation will:"
echo "  1. Stop MicroK8s on $TARGET_NODE"
echo "  2. Backup current backend to backend.bak.pre-restore"
echo "  3. Extract backup tar over existing backend"
echo "  4. Restart MicroK8s"
echo ""
echo "This is a DESTRUCTIVE operation!"
echo ""
read -r -p "Continue? (yes/NO): " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Determine if we're operating locally or remotely
if [[ "$TARGET_NODE" == "$(hostname)" ]] || [[ "$TARGET_NODE" == "localhost" ]]; then
  SSH_PREFIX=""
  SUDO_PREFIX="sudo"
  echo "Operating on local node..."
else
  SSH_PREFIX="ssh root@$TARGET_NODE"
  SUDO_PREFIX=""  # Already root via SSH
  echo "Operating on remote node: $TARGET_NODE"
  # Verify we can reach the node
  if ! $SSH_PREFIX hostname >/dev/null 2>&1; then
    echo "Error: Cannot reach node $TARGET_NODE via SSH" >&2
    exit 1
  fi
fi

# Stop MicroK8s
echo ""
echo "Stopping MicroK8s on $TARGET_NODE..."
if [[ -z "$SSH_PREFIX" ]]; then
  sudo microk8s stop
else
  $SSH_PREFIX microk8s stop
fi

# Backup current backend
echo ""
echo "Backing up current backend..."
BACKUP_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
if [[ -z "$SSH_PREFIX" ]]; then
  sudo mkdir -p /var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore
  sudo tar -czf /var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore/backend-${BACKUP_TIMESTAMP}.tar.gz \
    -C /var/snap/microk8s/current/var/kubernetes backend/ 2>/dev/null || true
else
  $SSH_PREFIX "mkdir -p /var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore"
  $SSH_PREFIX "tar -czf /var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore/backend-${BACKUP_TIMESTAMP}.tar.gz \
    -C /var/snap/microk8s/current/var/kubernetes backend/ 2>/dev/null || true"
fi
echo "Current backend saved to: backend.bak.pre-restore/backend-${BACKUP_TIMESTAMP}.tar.gz"

# Clear existing backend (keep cluster.yaml and cluster certs)
echo ""
echo "Clearing existing backend files (preserving cluster config)..."
if [[ -z "$SSH_PREFIX" ]]; then
  sudo bash <<'CLEAR_SCRIPT'
cd /var/snap/microk8s/current/var/kubernetes/backend/
# Keep cluster.yaml, cluster.crt, cluster.key
find . -type f \
  ! -name 'cluster.yaml' \
  ! -name 'cluster.crt' \
  ! -name 'cluster.key' \
  -delete
CLEAR_SCRIPT
else
  $SSH_PREFIX bash <<'CLEAR_SCRIPT'
cd /var/snap/microk8s/current/var/kubernetes/backend/
# Keep cluster.yaml, cluster.crt, cluster.key
find . -type f \
  ! -name 'cluster.yaml' \
  ! -name 'cluster.crt' \
  ! -name 'cluster.key' \
  -delete
CLEAR_SCRIPT
fi

# Extract backup tar
echo ""
echo "Extracting backup tar..."
if [[ -z "$SSH_PREFIX" ]]; then
  # Local extraction
  sudo tar -xvf "$BACKUP_TAR" -C / --strip-components=0
else
  # Remote extraction - need to copy tar first if not on shared storage
  if [[ "$BACKUP_TAR" == /shared/* ]]; then
    # Backup is on shared storage, can extract directly
    $SSH_PREFIX "tar -xvf '$BACKUP_TAR' -C / --strip-components=0"
  else
    # Need to copy tar to remote node first
    echo "Copying backup to remote node..."
    REMOTE_TMP="/tmp/restore-backup-$BACKUP_TIMESTAMP.tar"
    scp "$BACKUP_TAR" "root@$TARGET_NODE:$REMOTE_TMP"
    $SSH_PREFIX "tar -xvf '$REMOTE_TMP' -C / --strip-components=0"
    $SSH_PREFIX "rm -f '$REMOTE_TMP'"
  fi
fi

# Restore original cluster.yaml if backup overwrote it
echo ""
echo "Restoring cluster configuration..."
if [[ -z "$SSH_PREFIX" ]]; then
  sudo bash <<'RESTORE_CLUSTER'
BACKEND_DIR="/var/snap/microk8s/current/var/kubernetes/backend"
BACKUP_DIR="/var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ]; then
  # Extract just cluster.yaml from the pre-restore backup
  tar -xzf "$LATEST_BACKUP" -C /tmp/ \
    var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml 2>/dev/null || true

  if [ -f /tmp/var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml ]; then
    cp /tmp/var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml \
       "$BACKEND_DIR/cluster.yaml"
    rm -rf /tmp/var/snap/microk8s/current/var/kubernetes/backend/
    echo "Restored cluster.yaml from pre-restore backup"
  fi
fi
RESTORE_CLUSTER
else
  $SSH_PREFIX bash <<'RESTORE_CLUSTER'
BACKEND_DIR="/var/snap/microk8s/current/var/kubernetes/backend"
BACKUP_DIR="/var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

if [ -n "$LATEST_BACKUP" ]; then
  # Extract just cluster.yaml from the pre-restore backup
  tar -xzf "$LATEST_BACKUP" -C /tmp/ \
    var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml 2>/dev/null || true

  if [ -f /tmp/var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml ]; then
    cp /tmp/var/snap/microk8s/current/var/kubernetes/backend/cluster.yaml \
       "$BACKEND_DIR/cluster.yaml"
    rm -rf /tmp/var/snap/microk8s/current/var/kubernetes/backend/
    echo "Restored cluster.yaml from pre-restore backup"
  fi
fi
RESTORE_CLUSTER
fi

# Set correct permissions
echo ""
echo "Setting permissions..."
if [[ -z "$SSH_PREFIX" ]]; then
  sudo chown -R root:root /var/snap/microk8s/current/var/kubernetes/backend/
  sudo chmod 600 /var/snap/microk8s/current/var/kubernetes/backend/cluster.key
else
  $SSH_PREFIX "chown -R root:root /var/snap/microk8s/current/var/kubernetes/backend/"
  $SSH_PREFIX "chmod 600 /var/snap/microk8s/current/var/kubernetes/backend/cluster.key"
fi

# Start MicroK8s
echo ""
echo "Starting MicroK8s on $TARGET_NODE..."
if [[ -z "$SSH_PREFIX" ]]; then
  sudo microk8s start
else
  $SSH_PREFIX microk8s start
fi

# Wait for readiness
echo ""
echo "Waiting for MicroK8s to be ready..."
sleep 5
if [[ -z "$SSH_PREFIX" ]]; then
  sudo microk8s status --wait-ready
else
  $SSH_PREFIX microk8s status --wait-ready
fi

echo ""
echo "========================================"
echo "Restore complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Verify cluster status: kubectl get nodes"
echo "  2. Check dqlite state: dump-dqlite-state.sh"
echo "  3. If this was the primary node, you may need to run:"
echo "     repair-database-quorum.sh"
echo ""
echo "Rollback instructions (if needed):"
echo "  The previous backend was saved to:"
echo "  /var/snap/microk8s/current/var/kubernetes/backend.bak.pre-restore/backend-${BACKUP_TIMESTAMP}.tar.gz"