# MicroK8s Operations

This directory contains operational tooling and notes for managing a MicroK8s Kubernetes cluster on Ubuntu (Raspberry Pi friendly). Ubuntu was chosen over Raspberry Pi OS due to fuller compatibility with arm64 packages and Kubernetes dependencies.

- Target OS: Ubuntu (arm64)
- Cluster type: MicroK8s
- Access pattern: Admin scripts running locally and via SSH to nodes

## Prerequisites

- Ubuntu with MicroK8s installed
- SSH access to cluster nodes (typically as root)
- Kubectl available via one of:
  - `kubectl`
  - `microk8s kubectl`

## Directory layout

### Tracked directories (versioned in git)

- **scripts/** — Operational scripts for cluster lifecycle (upgrades, restarts, diagnostics)
  - `lib.sh` — Shared helper library (kubectl detection, jq installer, error traps)
  - `experimental/` — Work-in-progress scripts
  - See [scripts/README.md](scripts/README.md) for developer guide and script reference
- **manifests/** — Custom Kubernetes manifests (Ingress, services, deployments)
  - Custom manifests for cluster workloads
  - `deprecated/` — Old manifests kept for reference
- **patch/** — ConfigMap/resource patches (e.g., CoreDNS customization)
- **tests/** — Automated tests (e.g., ingress validation)
- **docs/** — Project documentation and TODOs
  - `TODO.md` — Future work tracking
  - `sessions/` — Session notes (gitignored)
- **unsorted/** — Temporary or uncategorized scripts/helpers
  - `workarounds/` — Temporary fixes for specific issues
  - See [unsorted/README.md](unsorted/README.md) for cleanup guidance

### Ignored directories (local/node-specific, not tracked)

- **secrets/** — Local plaintext secrets (moved from manifests; DO NOT COMMIT)
- **cloudflared/** — Cloudflare Tunnel credentials (credentials gitignored)
- **snap-links/** — Symlinks to local MicroK8s snap paths (node-specific)
- **helm/** — Helm charts with embedded credentials (gitignored)
- **deprecated/** — Archived code/configs (gitignored)
- **origin-ca-issuer/** — External git repository (gitignored)
- **backup/** — Cluster backups (large, node-specific, gitignored)

## Common tasks

### Cluster operations
- Apply all manifests:
  ```bash
  ./apply-all.sh
  ```
- Upgrade cluster nodes:
  ```bash
  ./scripts/upgrade-microk8s.sh
  ```
- Restart MicroK8s on specific nodes:
  ```bash
  ./scripts/restart-microk8s.sh node1 node2
  ```
- Check cluster status:
  ```bash
  ./scripts/get-status.sh
  ```

### Security & secrets management
- Install pre-commit hook to prevent committing secrets:
  ```bash
  ./scripts/install-git-hooks.sh
  ```
- For detailed security guidance, see [SECURITY.md](SECURITY.md)

### Testing
- Validate ingress resources (HTTPS + cert SANs):
  ```bash
  ./tests/ingress_unit_test.sh
  ```

## Script conventions

Scripts in `scripts/` follow these patterns:
- Source `lib.sh` and detect `KUBECTL` automatically
- Use `set -euo pipefail` and an ERR trap for safer execution
- Many scripts are interactive; follow on-screen prompts
- See [scripts/README.md](scripts/README.md) for detailed conventions

## Manifests

- **Location:** `manifests/`
- **Deployment:**
  - Use `./apply-all.sh` to apply everything under `/shared/microk8s/manifests/`
  - You can also apply individual files with kubectl if needed
- **Purpose:** Cluster config and patches (DNS, ingress, storage, etc.)

## Patches vs Manifests

- **manifests/** — Complete Kubernetes resources (new deployments, services, ingresses)
- **patch/** — ConfigMap patches or strategic merge patches for existing resources (e.g., CoreDNS configuration)

## Safety and scope

- **Do not edit files under** `/home/setup/microk8s/addons/` (managed by MicroK8s)
- **Keep changes limited to this repository** (prefer `scripts/` and `manifests/` maintained here)
- **Never commit plaintext secrets** — use the pre-commit hook and follow [SECURITY.md](SECURITY.md)
- For AI/editor automation, see [.github/copilot-instructions.md](.github/copilot-instructions.md) for scope and style guidance
