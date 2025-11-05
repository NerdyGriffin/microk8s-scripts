# microk8s-scripts
A collection of scripts that I use to help me manage and automate Microk8s on Raspberry Pi

This directory contains helper scripts for administering MicroK8s clusters (mainly on Ubuntu/Raspberry Pi).

What's new
- Added `lib.sh`: a small shared helper library used by multiple scripts. It provides:
	- `detect_kubectl()` — detects and exports a `KUBECTL` invocation (prefers `microk8s kubectl`, falls back to `sudo microk8s kubectl`).
	- `ensure_jq()` — attempts an apt-based install of `jq` (Ubuntu-only) and returns non-zero if unavailable.
	- `pause()` — interactive pause helper that falls back to sleep when non-interactive.
	- `set_common_trap()` — installs a consistent error trap for diagnostics.

Why this change
- Centralizes duplicated logic across scripts so bugfixes and enhancements (e.g., changing kubectl detection) only need to be made in one place.
- Reduces accidental differences between scripts and improves maintainability.

How to use
1. Scripts already updated in this folder source `lib.sh` automatically. You don't need to do anything special to get the new behavior.
2. If you add new scripts, add at the top:

```bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl
```

3. When calling `jq`-dependent helpers, you can call `ensure_jq` to attempt install on Ubuntu (it will return non-zero if it cannot install).

Commit
- A commit `chore(lib): refactor scripts to use shared lib and small robustness fixes` contains the refactor and lint fixes.

Notes
- These scripts assume an Ubuntu-style environment for the optional `ensure_jq` installer. If you run on other distros, install `jq` manually or adapt `ensure_jq()`.
- The scripts use `microk8s kubectl` by default and will fall back to `sudo microk8s kubectl` when necessary.
