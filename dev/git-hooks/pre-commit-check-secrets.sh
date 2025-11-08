#!/usr/bin/env bash
set -euo pipefail

# pre-commit local check to block plaintext secrets across the repo.
# Scans ALL staged files (respects .gitignore automatically). Install to .git/hooks/pre-commit.

staged_zero=$(git diff --cached --name-only --diff-filter=ACM -z || true)
if [ -z "$staged_zero" ]; then
  exit 0
fi

errors=0
# Read NUL-delimited filenames safely (handles spaces/newlines in names)
while IFS= read -r -d '' f; do
  # get staged version (use -- to be safe with paths starting with -)
  if ! content=$(git show -- ":$f" 2>/dev/null); then
    continue
  fi

  # Detect actual Kubernetes Secret manifests (kind: Secret with data/stringData)
  # Ignore ConfigMaps and references like 'secretName:' which are just pointers
  if echo "$content" | grep -q '^kind:[[:space:]]*Secret'; then
    if echo "$content" | grep -qE '^(data|stringData):[[:space:]]*$'; then
      echo "ERROR: staged file '$f' is a Kubernetes Secret manifest. Do NOT commit plain secrets."
      echo " - Move it to the 'secrets/' folder, encrypt it (SOPS) or create a SealedSecret instead."
      errors=$((errors+1))
    fi
  fi

  # Heuristic checks for actual credential values (not just field names)
  # Look for patterns like: password: "value", api_token: value, or apiKey: "abc123"
  # Exclude comments and secretName references
  if echo "$content" | grep -v '^[[:space:]]*#' | grep -v 'secretName:' | \
     grep -qE '(password|passwd|api[_-]?token|api[_-]?key|tunnel[_-]?secret|jwt[_-]?secret|secret[_-]?key|access[_-]?key)[[:space:]]*:[[:space:]]*["\047][^"\047]{8,}["\047]'; then
    echo "WARNING: staged file '$f' may contain credential values (long strings after password/token/key fields)."
    errors=$((errors+1))
  fi

  # Private key material markers
  if echo "$content" | grep -qE '-----BEGIN (ENCRYPTED )?PRIVATE KEY-----|ARGO[[:space:]]+TUNNEL[[:space:]]+TOKEN'; then
    echo "ERROR: staged file '$f' appears to contain private key material or Argo Tunnel token."
    errors=$((errors+1))
  fi
done < <(printf '%s' "$staged_zero")

if [ "$errors" -gt 0 ]; then
  echo "Commit aborted by pre-commit secret-scan hook."
  exit 1
fi

exit 0
