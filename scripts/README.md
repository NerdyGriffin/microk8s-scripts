# scripts/

Operational scripts for managing MicroK8s clusters (Ubuntu/Raspberry Pi).

## Overview

This directory contains shell scripts for cluster lifecycle operations:
- Node upgrades and restarts
- Database quorum repair
- Addon management
- Diagnostics and log collection
- Secret scanning (pre-commit hooks)

## Quick reference

### Cluster operations
- `upgrade-microk8s.sh` — Interactive upgrade flow (drain → upgrade → uncordon)
- `restart-microk8s.sh <node...>` — Restart MicroK8s on specified nodes
- `shutdown-all-nodes.sh` — Graceful shutdown of all cluster nodes
- `get-status.sh` — Cluster status probe (non-destructive)

### Diagnostics & repair
- `repair-database-quorum.sh` — Restore dqlite quorum (advanced; use with caution)
- `restore-backend-backup.sh` — Restore database backend from backup
- `logs-cert-manager.sh` — Collect cert-manager logs
- `logs-coredns.sh` — Collect CoreDNS logs

### Configuration & patches
- `patch-cert-manager.sh` — Apply cert-manager patches
- `upgrade-addons.sh` — Update MicroK8s addons configuration

### Secret management
- `install-git-hooks.sh` — Install pre-commit secret scanner
- `pre-commit-check-secrets.sh` — Pre-commit hook (scans for plaintext secrets)
- `move-manifest-secrets.sh` — Move secret manifests to secrets/ folder

### Experimental
- `experimental/` — Work-in-progress scripts; use at your own risk

## Shared library (lib.sh)

All scripts source `lib.sh` for consistent behavior. The library provides:

- **`detect_kubectl()`** — Auto-detect kubectl wrapper
  - Prefers `microk8s kubectl` without sudo
  - Falls back to `sudo microk8s kubectl` if needed
  - Exports `$KUBECTL` for use in scripts
  
- **`ensure_jq()`** — Attempt to install jq via apt (Ubuntu-only)
  - Returns non-zero if jq cannot be installed
  - Scripts can fall back to grep/awk if jq is unavailable
  
- **`pause()`** — Interactive pause with non-interactive fallback
  - Prompts user to press Enter when interactive
  - Falls back to sleep when non-interactive (CI/automation)
  
- **`set_common_trap()`** — Standard error trap for diagnostics
  - Enables `set -o errtrace` for inherited traps
  - Reports failing command and line number on error

### Writing new scripts

All new scripts should follow this template:

```bash
#!/bin/bash
# DESCRIPTION: Brief description of what this script does and safety assumptions
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

# Your script logic here
```

**Required conventions:**
- Use `${KUBECTL}` instead of direct `kubectl` or `microk8s kubectl` calls
- Use `set -euo pipefail` for fail-fast behavior
- Call `set_common_trap` for consistent error handling
- Add a DESCRIPTION comment explaining the script's purpose and safety assumptions
- Make scripts executable: `chmod u+x script.sh`

**Node iteration pattern (for multi-node operations):**
```bash
nodeArray=( "${@}" )
if [ $# -eq 0 ]; then
    readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
fi
for nodeFQDN in "${nodeArray[@]}"; do
    ssh "root@$nodeFQDN" "command here"
done
```

## What's new

- Added `lib.sh`: a small shared helper library used by multiple scripts
- Centralized kubectl detection, jq installation, pause helper, and error traps
- Refactored all scripts to use shared helpers for consistency
- Added pre-commit hook system for secret scanning

## Why this change

- Centralizes duplicated logic so bugfixes and enhancements only need to be made once
- Reduces accidental differences between scripts and improves maintainability
- Enforces consistent error handling and kubectl detection patterns

## Safety & scope

- **Valid edit locations:** Only modify files within `/shared/microk8s/scripts/`
- **Never edit:** `/shared/microk8s/addons/`, `/shared/microk8s/origin-ca-issuer/`, or parent directories outside this repository
- Scripts assume Ubuntu and use `microk8s kubectl` or `sudo microk8s kubectl`
- Many scripts are interactive; run from terminal with user confirmation
- For automation, consider environment variables or non-interactive flags

See [../.github/copilot-instructions.md](../.github/copilot-instructions.md) for detailed coding conventions and repository scope.

## Notes

- Scripts assume an Ubuntu-style environment for the optional `ensure_jq` installer
- If you run on other distros, install `jq` manually or adapt `ensure_jq()`
- The scripts use `microk8s kubectl` by default and fall back to `sudo microk8s kubectl` when necessary
