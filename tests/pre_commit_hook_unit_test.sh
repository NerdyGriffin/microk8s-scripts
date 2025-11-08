#!/usr/bin/env bash
# Unit test for pre-commit secret-scan hook
# Creates a contrived staged file with secret-like content and verifies the hook blocks commits.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/.." && pwd)"
cd "$REPO_ROOT"

TMP_FILE="tests/tmp-secret-for-hook-$$.txt"
trap 'git restore --staged "$TMP_FILE" >/dev/null 2>&1 || true; rm -f "$TMP_FILE"' EXIT

# Create a test file that should trigger the hook. To avoid committing raw secrets
# into the repo, the payload is stored base64-encoded and decoded at runtime.
payload_b64='bm9ybWFsIGxpbmUKcGFzc3dvcmQ6IHN1cGVyc2VjcmV0MTIzCi0tLS0tQkVHSU4gUFJJVkFURSBLRVktLS0tLQpNSUlDLi4uRkFLRUtFWS4uLgotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg=='
printf '%s' "$payload_b64" | base64 -d > "$TMP_FILE"

# Stage the file
git add "$TMP_FILE"

# Run the canonical hook directly with debug enabled
echo "Running canonical hook (PRE_COMMIT_DEBUG=1)..."
if PRE_COMMIT_DEBUG=1 bash dev/git-hooks/pre-commit-check-secrets.sh; then
  echo "ERROR: Hook did not detect secrets when run directly (unexpected)"
  exit 2
else
  echo "PASS: Hook detected secrets when run directly (as expected)"
fi

# Do NOT perform a real git commit that would add secret blobs to the repo.
# Instead, unstage and remove the temporary file (cleanup handled by trap too).
git restore --staged "$TMP_FILE" >/dev/null 2>&1 || true
rm -f "$TMP_FILE"

echo "PASS: test completed (hook detected secrets and no commit was performed)"
exit 0
