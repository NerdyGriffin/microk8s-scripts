#!/usr/bin/env bash
set -euo pipefail

# Installer for git hooks (pre-commit) with symlink-first strategy and copy fallback.
# Run this from the repository root.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$DIR/pre-commit-check-secrets.sh"
REPO_ROOT="$(cd "$DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
TARGET="$HOOKS_DIR/pre-commit"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Hook source not found: $HOOK_SRC" >&2
  exit 2
fi

if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "This script must be run from a git repository clone (no .git directory found at $REPO_ROOT)." >&2
  exit 2
fi

mkdir -p "$HOOKS_DIR"

# Try to create/update a symlink
set +e
ln -sfn "$HOOK_SRC" "$TARGET"
ln_rc=$?
set -e

if [ $ln_rc -ne 0 ]; then
  echo "Symlink failed (rc=$ln_rc). Falling back to copy..."
  cp "$HOOK_SRC" "$TARGET"
fi

chmod +x "$TARGET"

echo "Installed pre-commit hook to $TARGET"
if [ $ln_rc -eq 0 ]; then
  echo "Symlinked to $HOOK_SRC (updates to the repo hook will be picked up automatically)."
else
  echo "Copied from $HOOK_SRC (re-run installer after updates to the repo hook)."
fi
