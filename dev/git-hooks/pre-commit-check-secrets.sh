#!/usr/bin/env bash
set -euo pipefail

# pre-commit local check to block plaintext secrets across the repo.
# Scans ALL staged files (respects .gitignore automatically). Install to .git/hooks/pre-commit.
#
# Robustness improvements:
# - Capture staged filenames up-front with mapfile to avoid process-substitution timing issues
# - Use git show, falling back to git cat-file when appropriate
# - PRE_COMMIT_DEBUG=1 prints which checks triggered for easier debugging

DEBUG=${PRE_COMMIT_DEBUG:-0}
errors=0

# Capture NUL-delimited staged filenames safely into an array
mapfile -d '' -t files < <(git diff --cached --name-only --diff-filter=ACM -z || true)

if [ ${#files[@]} -eq 0 ]; then
  # Nothing staged; exit cleanly
  exit 0
fi

for f in "${files[@]}"; do
  # read content of staged blob; prefer blob lookup via index (most reliable in hooks)
  content=""
  blob=""
  blob=$(git ls-files --stage -- "$f" 2>/dev/null | awk '{print $2}' || true)
  if [ -n "$blob" ]; then
    content=$(git cat-file -p "$blob" 2>/dev/null || true)
  else
    # fallback to path-based reads
    if content=$(git show -- ":$f" 2>/dev/null); then
      :
    elif content=$(git cat-file -p ":$f" 2>/dev/null); then
      :
    else
      # Could not read staged content; skip
      if [ "$DEBUG" -eq 1 ]; then
        echo "DEBUG: could not read staged content for '$f'"
      fi
      continue
    fi
  fi

  # helper to print debug matches
  _dbg_match() {
    if [ "$DEBUG" -eq 1 ]; then
      printf '%s\n' "$content" | grep -nE -- "$1" || true
    fi
  }

  # Detect actual Kubernetes Secret manifests (kind: Secret with data/stringData)
  if printf '%s\n' "$content" | grep -qE -- '^kind:[[:space:]]*Secret'; then
    if printf '%s\n' "$content" | grep -qE -- '^(data|stringData):[[:space:]]*$'; then
      echo "ERROR: staged file '$f' is a Kubernetes Secret manifest. Do NOT commit plain secrets."
      echo " - Move it to the 'secrets/' folder, encrypt it (SOPS) or create a SealedSecret instead."
      _dbg_match '^(data|stringData):[[:space:]]*$'
      errors=$((errors+1))
      continue
    fi
  fi

  # Heuristic checks for actual credential values (not just field names)
  if printf '%s\n' "$content" | grep -v '^[[:space:]]*#' | grep -v 'secretName:' | \
     grep -E -q -- '(password|passwd|api[_-]?token|api[_-]?key|tunnel[_-]?secret|jwt[_-]?secret|secret[_-]?key|access[_-]?key)[[:space:]]*:[[:space:]]*["\047][^"\047]{8,}["\047]'; then
    echo "WARNING: staged file '$f' may contain credential values (long strings after password/token/key fields)."
    _dbg_match '(password|passwd|api[_-]?token|api[_-]?key|tunnel[_-]?secret|jwt[_-]?secret|secret[_-]?key|access[_-]?key)[[:space:]]*:[[:space:]]*["\047][^"\047]{8,}["\047]'
    errors=$((errors+1))
  fi

  # Private key material markers
  if printf '%s\n' "$content" | grep -E -q -- '-----BEGIN (ENCRYPTED )?PRIVATE KEY-----|ARGO[[:space:]]+TUNNEL[[:space:]]+TOKEN'; then
    echo "ERROR: staged file '$f' appears to contain private key material or Argo Tunnel token."
    _dbg_match '-----BEGIN (ENCRYPTED )?PRIVATE KEY-----|ARGO[[:space:]]+TUNNEL[[:space:]]+TOKEN'
    errors=$((errors+1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "Commit aborted by pre-commit secret-scan hook."
  exit 1
fi

exit 0
