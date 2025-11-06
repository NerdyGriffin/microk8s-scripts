## Purpose

This repository is a small collection of operational helper scripts for managing MicroK8s clusters (targeting Ubuntu / Raspberry Pi). The scripts are shell-first, admin-focused, and intended to be run interactively or from automation controlling cluster nodes over SSH.

Use these instructions to help write, modify, or extend scripts in this repo so changes are consistent and immediately useful.

## Scope and file restrictions

**IMPORTANT**: When making code changes:
- **Only edit files within** `/home/setup/microk8s/scripts/` (this repository root).
- **Never modify files in** `/home/setup/microk8s/addons/`, `/home/setup/microk8s/origin-ca-issuer`, or any parent directories outside this repository.
- **Valid locations for edits**:
  - Top-level `.sh` scripts in this directory
  - `lib.sh` (shared helpers)
  - Files in `experimental/` subdirectory
  - Documentation files (`README.md`, this file)
  - YAML patches for Kubernetes resources (e.g., `manifests/coredns-patch.yaml`)
- **Excluded from edits**:
  - `/home/setup/microk8s/addons/` — this is the MicroK8s addons directory, managed separately
  - Any files in parent directories (e.g., `/home/setup/microk8s/` outside `scripts/`)
  - System files or paths outside this repository

If asked to modify files outside `/home/setup/microk8s/scripts/`, politely decline and suggest alternatives within the repository scope.

## Big picture

- What this repo contains: short, focused shell scripts (top-level .sh) and small YAML patches (for k8s resources like `coredns-patch.yaml`).
- Main responsibilities: node lifecycle operations (restart, upgrade), cluster diagnostics/backups (`repair-database-quorum.sh`), and addon/patch tooling.
- Why: centralize reusable admin tasks and reduce ad-hoc SSH/manual steps.

## Key files and patterns to reference

- `lib.sh` — canonical shared helpers. Always read this first. Important functions:
  - `detect_kubectl()` — determines `KUBECTL` (prefers system kubectl, then `microk8s kubectl`, then `sudo microk8s kubectl`). Callers rely on exported `$KUBECTL`.
  - `ensure_jq()` — attempts an apt install of `jq` (Ubuntu-only) and returns non-zero if not available.
  - `set_common_trap()` — standard ERR trap used for diagnostics.
  - `pause()` — interactive pause helper used widely in upgrade scripts.

- Example scripts that show repo conventions:
  - `restart-microk8s.sh` — uses `source lib.sh`, `set -euo pipefail`, `set_common_trap`, `detect_kubectl`, then iterates nodes via SSH as `root@${node}`.
  - `upgrade-microk8s.sh` — demonstrates non-destructive drains/uncordon flow and uses `pause()` at key manual checkpoints.
  - `repair-database-quorum.sh` — shows advanced dqlite manipulation and rsync/ssh usage for backend data.

## Coding conventions and assumptions

- All scripts should source `lib.sh` near the top and call `set_common_trap` and `detect_kubectl`.
  Preferred header:

  ```bash
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$DIR/lib.sh"
  set -euo pipefail
  set_common_trap
  detect_kubectl
  ```

- Exit and error handling: scripts use `set -euo pipefail` + `set_common_trap`. Preserve that pattern rather than introducing custom signal handling unless necessary.
- Interactivity: many scripts are interactive (use `pause()` and read prompts). If adding automation-only modes, keep interactivity configurable via flags.
- `KUBECTL` override: callers may pre-set `KUBECTL` in environment; always honor it.
- Platform-specific helpers: `ensure_jq()` uses apt — assume Ubuntu. If you change install logic, document distro assumptions clearly.

## Developer workflows & quick commands

- Run a status probe (no cluster changes):

  `./get-status.sh`

- Restart MicroK8s on specific nodes (prompted confirmation):

  `./restart-microk8s.sh node1 node2`

- Upgrade flow (multi-step, interactive):

  `./upgrade-microk8s.sh node1` — reads node list if none provided, drains/uncords, calls `upgrade-addons.sh` when finished.

- Debugging tips:
  - Run a script with `bash -x` to trace execution: `bash -x ./upgrade-microk8s.sh node1`.
  - If `kubectl` isn't detected, set `KUBECTL="microk8s kubectl"` and re-run.
  - Look at `lib.sh` trap messages for the failing command and line number.

## Integration points & environment

- SSH to nodes as `root@<fqdn>` is used throughout. New code should adopt the same model (or centralize SSH behavior to a helper function).
- Snap/snap-refresh commands are used for microk8s upgrades (see `upgrade-microk8s.sh`). Be conservative: upgrades are interactive and involve draining.
- Config patches (like `coredns-patch.yaml`) are applied directly against the cluster using `$KUBECTL`.

## Examples to copy from

- **New script template** — copy this header for consistency:
  ```bash
  #!/bin/bash
  # DESCRIPTION: Brief description of what this script does and safety assumptions
  set -euo pipefail
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$DIR/lib.sh"
  set_common_trap
  detect_kubectl
  ```

- **Node iteration pattern** — from `restart-microk8s.sh` and `upgrade-microk8s.sh`:
  ```bash
  nodeArray=( "${@}" )
  if [ $# -eq 0 ]; then
      readarray -t nodeArray < <(${KUBECTL} get nodes -o name 2>/dev/null | sed 's|node/||')
  fi
  for nodeFQDN in "${nodeArray[@]}"; do
      ssh "root@$nodeFQDN" "command here"
  done
  ```

## What to avoid

- Don't remove `set -euo pipefail` or the common trap. That changes failure semantics across all scripts.

## When you add files

- Add new scripts to top-level, source `lib.sh`, and include a short DESCRIPTION comment at the file top explaining operational impact and safety assumptions.
- **All new files must be created within** `/home/setup/microk8s/scripts/` or its subdirectories.
- If adding automation-only helpers, place them in `experimental/` or document them clearly in the top-level `README.md` before use.
- Kubernetes manifests should be in `manifests/`.
- **Never create files in** `/home/setup/microk8s/addons/` or parent directories.

## CI and quality checks

To maintain consistency across scripts, consider these validation patterns:

- **Basic shellcheck** — run on all `.sh` files:
  ```bash
  find . -name "*.sh" -exec shellcheck {} \;
  ```

- **Verify lib.sh sourcing** — ensure new scripts follow the pattern:
  ```bash
  grep -L 'source.*lib\.sh' *.sh | grep -v lib.sh || echo "All scripts source lib.sh ✓"
  ```

- **Check error handling** — verify scripts use proper error handling:
  ```bash
  grep -L 'set -euo pipefail' *.sh | grep -v lib.sh || echo "All scripts use strict mode ✓"
  ```

---

If anything here is unclear or you want more coverage, tell me which area to expand and I will iterate.
