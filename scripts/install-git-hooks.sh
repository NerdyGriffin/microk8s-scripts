#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SRC="$DIR/pre-commit-check-secrets.sh"

if [ ! -f "$HOOK_SRC" ]; then
  echo "Hook source not found: $HOOK_SRC"
  exit 2
fi

if [ ! -d .git ]; then
  echo "This script must be run from the repo root (where .git exists)."
  exit 2
fi

mkdir -p .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "Installed pre-commit hook to .git/hooks/pre-commit"
echo "Note: .git/hooks is local to your clone and is not committed. Run this on each developer machine."
