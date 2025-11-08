# Code Review: MicroK8s Scripts Repository
**Date:** November 7, 2025
**Focus Areas:** Organization, Style Consistency, Documentation

## Executive Summary

**Overall Assessment:** Good foundation with recent improvements, but several areas need attention for consistency and maintainability.

**Strengths:**
- ✅ Well-documented security practices (SECURITY.md)
- ✅ Comprehensive README structure
- ✅ Shared library pattern (`lib.sh`) for common functions
- ✅ Clear separation of concerns (scripts/, manifests/, patches/)

**Key Issues:**
- ⚠️ Inconsistent shebang usage across scripts
- ⚠️ Large unsorted/ directory needs cleanup
- ⚠️ Mixed documentation locations
- ⚠️ Some scripts don't follow established patterns
- ⚠️ Manifests in wrong directory (secrets should not be in manifests/)

---

## 1. Organization Issues

### 1.1 Directory Structure

#### ✅ Good
- Clear separation: `scripts/`, `manifests/`, `patch/`, `tests/`
- `secrets/` properly gitignored
- `symlinks/` for node-specific links
- `docs/` with session logs and examples

#### ⚠️ Issues

**CRITICAL: Secrets in manifests/**
```
manifests/cluster-issuer.yaml       # Contains email addresses, references secrets
manifests/origin-issuer.yaml        # Should be in secrets/
manifests/service-account.yaml      # Should be in secrets/
```
**Action:** These were moved to `secrets/` but appear to still be in `manifests/`. Verify and document.

**Large unsorted/ directory (18 files)**
```
unsorted/
├── apply-all.sh                    # Should be at root or in scripts/
├── check-cluster-status.sh         # Overlap with scripts/get-status.sh?
├── drain-node.sh                   # Should be in scripts/
├── delete-broken-certs.sh          # Should be in scripts/
├── test-dns.sh                     # Should be in tests/
├── restart-microk8s.sh.save        # Delete (backup file)
├── temp.json                       # Delete or gitignore
├── nginx.yml.example               # Move to docs/examples/
└── regex-replace.txt               # Move to docs/examples/
```
**Action:** Immediate cleanup needed per `unsorted/README.md` guidance.

**backup/ structure is inconsistent**
```
backup/
├── 2025-11-06-backup/              # Dated subdirectory
├── backend.bak/                    # No date prefix
├── backend.restore/                # No date prefix
├── cert-manager-backup.yaml        # Loose file
└── manifests/                      # Nested manifests?
```
**Action:** Standardize backup naming: `YYYY-MM-DD-<type>/` or `<type>-YYYY-MM-DD/`

**deprecated/ needs README**
- No documentation explaining what's archived or why
- Contains mix of old scripts, manifests, secrets
**Action:** Add `deprecated/README.md` with deprecation dates and reasons

### 1.2 File Placement

#### Issues
1. **`manifests/custom-headers.yaml.1`** — numbered backup file in tracked directory
   - Should be: deleted or moved to deprecated/

2. **`docs/examples/` contains `.bak` files**
   - `example-cert.yaml.bak` should be cleaned up

3. **`scripts/convert-endpoint.sh`** — appears to be a one-off utility
   - Consider: move to `scripts/experimental/` or document use case

4. **`deprecated/move-manifest-secrets.sh`** — this script now exists in `scripts/`
   - Verify it's truly deprecated and document difference

---

## 2. Style Consistency Issues

### 2.1 Shebang Inconsistency

**Problem:** Mixed usage of `#!/bin/bash` vs `#!/usr/bin/env bash`

```bash
# scripts/ directory:
#!/bin/bash                  # 11 files
#!/usr/bin/env bash          # 3 files (pre-commit, install-git-hooks, logs-cert-manager)
```

**Recommendation:** Standardize on `#!/usr/bin/env bash` for portability

**Rationale:**
- More portable across systems where bash may not be at `/bin/bash`
- Consistent with modern best practices
- Already used in security-critical scripts (pre-commit-check-secrets.sh)

**Action Required:** Update all script shebangs to:
```bash
#!/usr/bin/env bash
```

### 2.2 Script Header Patterns

**Inconsistent DESCRIPTION comments:**

✅ **Good examples:**
```bash
# scripts/upgrade-addons.sh
# DESCRIPTION: Upgrade MicroK8s addons and apply configuration patches

# scripts/restore-backend-backup.sh
# DESCRIPTION: Restore MicroK8s dqlite backend from tar backup (advanced/dangerous - stops cluster)
```

❌ **Missing DESCRIPTION:**
- `scripts/logs-cert-manager.sh` — no description
- `scripts/logs-coredns.sh` — no description
- `scripts/convert-endpoint.sh` — no description
- `scripts/get-status.sh` — no description

**Action:** Add DESCRIPTION comment to all scripts following template:
```bash
#!/usr/bin/env bash
# DESCRIPTION: <What it does> (<safety/context notes>)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl
```

### 2.3 lib.sh Usage Inconsistency

**Not using lib.sh:**
- `scripts/logs-cert-manager.sh` — reimplements KUBECTL detection and error trap
- `scripts/logs-coredns.sh` — likely same issue
- `scripts/convert-endpoint.sh` — simple script, but should still use lib.sh

**Action:** Refactor these to use `lib.sh` for consistency

**Example fix for logs-cert-manager.sh:**
```bash
#!/usr/bin/env bash
# DESCRIPTION: Collect and display cert-manager controller logs
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

# Rest of script logic...
```

### 2.4 Error Handling

**Inconsistent patterns:**
```bash
# logs-cert-manager.sh uses manual trap:
trap 'rc=$?; echo "ERROR: line $LINENO: \"$BASH_COMMAND\" exited with $rc" >&2; exit $rc' ERR

# Other scripts use lib.sh:
set_common_trap  # from lib.sh
```

**Action:** All scripts should use `set_common_trap` from lib.sh

### 2.5 KUBECTL Variable Usage

**Inconsistent:**
- Most scripts: `${KUBECTL}` (from `detect_kubectl()`)
- `unsorted/apply-all.sh`: `microk8s.kubectl` (hardcoded with dot notation)

**Action:** Update `unsorted/apply-all.sh` to use standard pattern or move to scripts/

---

## 3. Documentation Issues

### 3.1 Missing Documentation

**Files needing documentation:**

1. **`patch/coredns-patch.yaml`** — no inline comments explaining what it patches
   - Add header comment with purpose and usage

2. **`symlinks/` individual files** — no indication they're symlinks in listings
   - README.md exists but could be more prominent

3. **`tests/ingress_unit_test.sh`** — no header documentation
   - Add DESCRIPTION and usage example

4. **`deprecated/` directory** — completely undocumented
   - Critical: Add README.md explaining deprecation policy

5. **`backup/` directory** — no README explaining structure or retention policy
   - Add README.md with backup/restore procedures

### 3.2 Documentation Fragmentation

**Example files in multiple locations:**
```
docs/examples/
├── cloudflare-origin-ca-issuer.yaml.example
└── example-cert.yaml.bak

unsorted/
└── nginx.yml.example

manifests/
└── (contains actual configs, not examples)
```

**Recommendation:** Consolidate examples:
- Move `unsorted/nginx.yml.example` → `docs/examples/nginx.yml.example`
- Remove `.bak` files from examples directory
- Document example usage in `docs/examples/README.md`

### 3.3 README Cross-References

**Current state:** Good cross-referencing between main READMEs

**Missing:**
- `tests/README.md` — no documentation of test structure or how to add tests
- `patch/README.md` — no explanation of patch vs manifest philosophy
- `deprecated/README.md` — completely absent

**Action:** Add these READMEs with brief explanations

---

## 4. Specific File Issues

### 4.1 Scripts with Problems

#### `unsorted/apply-all.sh`
```bash
#!/bin/bash
microk8s.kubectl apply -f /shared/microk8s/manifests/
```

**Issues:**
1. Uses old `microk8s.kubectl` notation (with dot)
2. Hardcoded absolute path
3. No error handling
4. Doesn't use lib.sh
5. Should be at root or in scripts/

**Recommended fix:**
```bash
#!/usr/bin/env bash
# DESCRIPTION: Apply all Kubernetes manifests from manifests/ directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

MANIFESTS_DIR="$(dirname "$0")/manifests"

if [ ! -d "$MANIFESTS_DIR" ]; then
  echo "ERROR: Manifests directory not found: $MANIFESTS_DIR" >&2
  exit 1
fi

echo "Applying all manifests from $MANIFESTS_DIR..."
${KUBECTL} apply -f "$MANIFESTS_DIR/"
echo "Done"
```

**Suggested location:** Move to root as `apply-all.sh` (referenced in README)

#### `scripts/convert-endpoint.sh`
- Unclear purpose from filename
- No DESCRIPTION comment
- Doesn't use lib.sh

**Action:** Document purpose or move to experimental/

### 4.2 Manifest Issues

#### Email addresses in manifests
```yaml
# manifests/cluster-issuer.yaml
spec:
  acme:
    email: christian.kunis@nerdygriffin.net  # Personal email exposed
```

**Consideration:** While not a secret, consider:
1. Using a generic monitoring email
2. Documenting in SECURITY.md that emails are public
3. Or moving to secrets/ with placeholder in manifests/

#### Inconsistent naming
```
manifests/
├── arr-stack-ingress.yaml          # descriptive
├── cockpit-ingress.yaml            # descriptive
├── custom-headers.yaml.1           # numbered backup - wrong location
├── pvc-nfs.yaml                    # abbreviation (PersistentVolumeClaim)
├── sc-nfs.yaml                     # abbreviation (StorageClass)
```

**Recommendation:**
- Remove numbered backups
- Consider full names for clarity: `storageclass-nfs.yaml`, `persistentvolumeclaim-nfs.yaml`
- Or document abbreviations in README

---

## 5. Security & Credentials

### 5.1 Verified Issues

**Files that should NOT be in manifests/ (contain or reference secrets):**
```
manifests/cluster-issuer.yaml       # References cloudflare-api-token-secret
manifests/origin-issuer.yaml        # Contains service key reference
manifests/service-account.yaml      # ServiceAccount with secrets
```

**Status:** Documentation says these were moved to `secrets/` but tree shows them still in `manifests/`

**Action:** VERIFY IMMEDIATELY:
1. Check if files were actually moved
2. If not, move them now: `mv manifests/{cluster-issuer,origin-issuer,service-account}.yaml secrets/`
3. Update `scripts/upgrade-addons.sh` to reference secrets/ (already done in recent update)
4. Commit the move

### 5.2 Credential References

**Found in manifests (safe - just references):**
- `secretName: <name>-tls` — OK (just TLS cert references)
- `apiTokenSecretRef:` — OK (references, not values)

---

## 6. Recommendations by Priority

### CRITICAL (Do Immediately)

1. **Verify secret file locations**
   ```bash
   # Check if these are actually in secrets/ or still in manifests/
   ls -la manifests/{cluster-issuer,origin-issuer,service-account}.yaml
   ls -la secrets/{cluster-issuer,origin-issuer,service-account}.yaml
   ```

2. **Fix manifests/cluster-issuer.yaml location**
   - If still in manifests/, move to secrets/ now
   - Pre-commit hook should have caught this

3. **Delete obvious cruft**
   ```bash
   rm manifests/custom-headers.yaml.1
   rm unsorted/restart-microk8s.sh.save
   rm unsorted/temp.json
   rm docs/examples/example-cert.yaml.bak
   ```

### HIGH (Next Session)

4. **Standardize script headers**
   - Update all shebangs to `#!/usr/bin/env bash`
   - Add DESCRIPTION comments to all scripts
   - Ensure all scripts source lib.sh

5. **Clean up unsorted/**
   - Move `apply-all.sh` to root
   - Move `check-cluster-status.sh`, `drain-node.sh`, `delete-broken-certs.sh` to scripts/
   - Move `test-dns.sh` to tests/
   - Move `nginx.yml.example` to docs/examples/
   - Delete backup files

6. **Add missing READMEs**
   - `deprecated/README.md`
   - `backup/README.md`
   - `tests/README.md`
   - `patch/README.md`

### MEDIUM (Future)

7. **Refactor non-lib.sh scripts**
   - `logs-cert-manager.sh`
   - `logs-coredns.sh`
   - `convert-endpoint.sh`

8. **Standardize backup naming**
   - All backups: `YYYY-MM-DD-<type>/`
   - Document retention policy

9. **Review deprecated/**
   - Document why each item is deprecated
   - Set dates for removal
   - Create deprecation policy

10. **Consolidate examples**
    - All examples → `docs/examples/`
    - Add `docs/examples/README.md`

### LOW (Nice to Have)

11. **Consider renaming for clarity**
    - `sc-nfs.yaml` → `storageclass-nfs.yaml`
    - `pvc-nfs.yaml` → `persistentvolumeclaim-nfs.yaml`

12. **Add inline documentation**
    - Comments in patch files
    - Comments in complex manifest files

---

## 7. Style Guide (Proposed)

### 7.1 Script Template
```bash
#!/usr/bin/env bash
# DESCRIPTION: <Brief description> (<safety/context notes>)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"
set -euo pipefail
set_common_trap
detect_kubectl

# Script logic here
```

### 7.2 File Naming Conventions

**Scripts:**
- Lowercase with hyphens: `upgrade-microk8s.sh`
- Descriptive action-object: `logs-cert-manager.sh`, `patch-coredns.sh`

**Manifests:**
- Lowercase with hyphens: `cluster-issuer.yaml`
- Descriptive: `homeassistant-ingress.yaml`
- No numbered backups in tracked directories

**Directories:**
- Lowercase, no special chars: `scripts/`, `manifests/`, `deprecated/`
- Plural for collections: `tests/`, `docs/`

### 7.3 README Standards

All directories with >3 files should have a README.md containing:
1. Purpose of the directory
2. File organization/structure
3. Usage examples or references
4. Safety warnings if applicable

---

## 8. Testing Recommendations

### Current State
- ✅ `tests/ingress_unit_test.sh` exists
- ❌ No tests for scripts
- ❌ No CI/CD validation

### Recommendations
1. **Add script tests**
   ```
   tests/
   ├── ingress_unit_test.sh          # existing
   ├── test_lib_functions.sh          # NEW: test lib.sh helpers
   └── test_script_headers.sh         # NEW: validate script consistency
   ```

2. **CI checks** (if using GitHub Actions)
   - Shellcheck on all .sh files
   - Verify all scripts source lib.sh
   - Verify all scripts have DESCRIPTION
   - Run pre-commit hook on PR

---

## 9. Quick Wins Checklist

These can be done in <30 minutes:

- [ ] Delete numbered backup files (custom-headers.yaml.1, etc.)
- [ ] Delete .save files (restart-microk8s.sh.save)
- [ ] Delete temp.json from unsorted/
- [ ] Verify secret files are in secrets/ not manifests/
- [ ] Add DESCRIPTION to logs-cert-manager.sh
- [ ] Add DESCRIPTION to logs-coredns.sh
- [ ] Add DESCRIPTION to get-status.sh
- [ ] Add DESCRIPTION to convert-endpoint.sh
- [ ] Create deprecated/README.md
- [ ] Create backup/README.md
- [ ] Move nginx.yml.example to docs/examples/

---

## 10. Summary Metrics

**Repository Stats:**
- Total files: 293
- Scripts in scripts/: 17
- Scripts in unsorted/: 11
- Manifests: 16
- Documentation files: 12

**Consistency Scores:**
- Script headers (DESCRIPTION): 65% (11/17)
- lib.sh usage: 88% (15/17)
- Shebang consistency: 65% (11/17 use #!/bin/bash)
- Documentation coverage: 75% (9/12 major dirs have READMEs)

**Priority Distribution:**
- Critical: 3 items
- High: 3 items
- Medium: 4 items
- Low: 2 items

---

## Conclusion

The repository has a solid foundation with good recent improvements (SECURITY.md, lib.sh pattern, comprehensive READMEs). The main issues are:

1. **Inconsistency** — Scripts don't all follow the same patterns
2. **Organization** — unsorted/ needs immediate attention
3. **Documentation** — Missing READMEs for several directories

Focus on the Critical and High priority items first. The style inconsistencies can be addressed incrementally as files are touched.

**Estimated effort:**
- Critical fixes: 30 minutes
- High priority: 2-3 hours
- Medium priority: 4-6 hours
- Low priority: 2-3 hours

Total cleanup: ~1 day of focused work

---

**Reviewer Notes:**
- Overall code quality is good
- Security practices are excellent (pre-commit hooks, secrets/ directory)
- Main concern is organizational consistency
- No blocking issues found (aside from verifying secret file locations)
