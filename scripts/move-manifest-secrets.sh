#!/usr/bin/env bash
set -euo pipefail

# Move manifest files under manifests/ that look like Kubernetes Secrets into the secrets/ folder.
# Safe to run multiple times; will not overwrite existing files without appending a suffix.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
MANIFESTS_DIR="$DIR/manifests"
SECRETS_DIR="$DIR/secrets"

if [ ! -d "$MANIFESTS_DIR" ]; then
  echo "No manifests/ directory found; nothing to do."
  exit 0
fi

mkdir -p "$SECRETS_DIR"

shopt -s nullglob
for f in "$MANIFESTS_DIR"/*.{yml,yaml,YML,YAML}; do
  # read file content and check for secret indicators
  if grep -qE '(^kind:[[:space:]]*Secret|^[[:space:]]*(data|stringData):)' "$f"; then
    base=$(basename "$f")
    dest="$SECRETS_DIR/$base"
    if [ -e "$dest" ]; then
      # avoid overwriting; find available suffix
      i=1
      while [ -e "$SECRETS_DIR/${base}.old$i" ]; do
        i=$((i+1))
      done
      dest="$SECRETS_DIR/${base}.old$i"
    fi
    echo "Moving secret manifest: $f -> $dest"
    mv "$f" "$dest"
  fi
done

echo "Done. Moved any detected secret manifests to '$SECRETS_DIR'."
