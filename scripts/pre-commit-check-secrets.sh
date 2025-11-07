#!/usr/bin/env bash
set -euo pipefail

# pre-commit local check to block plaintext secrets across the repo.
# Scans ALL staged files (respects .gitignore automatically). Install to .git/hooks/pre-commit.

staged_files=$(git diff --cached --name-only --diff-filter=ACM || true)
if [ -z "$staged_files" ]; then
  exit 0
fi

errors=0
for f in $staged_files; do
  # get staged version
  if ! content=$(git show ":$f" 2>/dev/null); then
    continue
  fi

  # Detect Kind: Secret (YAML 'kind: Secret') or presence of 'data:' or 'stringData:' top-level keys
  if echo "$content" | grep -qE '(^kind:[[:space:]]*Secret|^[[:space:]]*(data|stringData):)'; then
    echo "ERROR: staged file '$f' looks like a Kubernetes Secret. Do NOT commit plain secrets."
    echo " - Move it to the 'secrets/' folder, encrypt it (SOPS) or create a SealedSecret instead."
    errors=$((errors+1))
  fi

  # Heuristic checks for secret-like keys and tokens (case-insensitive)
  if echo "$content" | grep -qiE '(^|[^A-Z])((password|passwd|api[_-]?token|api[_-]?key|tunnel[_-]?secret|jwt[_-]?secret|secret[_-]?key|access[_-]?key))([^A-Z]|$)'; then
    echo "WARNING: staged file '$f' contains secret-like keywords (password, apiToken, TunnelSecret, jwt_secret, etc.)."
    errors=$((errors+1))
  fi

  # Private key material markers
  if echo "$content" | grep -qE '-----BEGIN (ENCRYPTED )?PRIVATE KEY-----|ARGO[[:space:]]+TUNNEL[[:space:]]+TOKEN'; then
    echo "ERROR: staged file '$f' appears to contain private key material or Argo Tunnel token."
    errors=$((errors+1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "Commit aborted by pre-commit secret-scan hook."
  exit 1
fi

exit 0
