# Security Policy

This document describes security practices and secret handling procedures for this MicroK8s operations repository.

## Overview

This repository contains operational tooling for MicroK8s cluster management. Some configuration files may contain or reference sensitive information (API tokens, passwords, private keys, certificates). **Never commit plaintext secrets to the repository.**

## Table of Contents

- [Secret Handling Workflow](#secret-handling-workflow)
- [Pre-Commit Hook](#pre-commit-hook)
- [Directory Security Model](#directory-security-model)
- [What Constitutes a Secret](#what-constitutes-a-secret)
- [Credential Rotation](#credential-rotation)
- [Removing Secrets from Git History](#removing-secrets-from-git-history)
- [Future: Encrypted Secrets](#future-encrypted-secrets)
- [Reporting Security Issues](#reporting-security-issues)

## Secret Handling Workflow

### 1. Install the pre-commit hook

Before making any commits, install the secret scanning hook:

```bash
./scripts/install-git-hooks.sh
```

This installs `scripts/pre-commit-check-secrets.sh` into `.git/hooks/pre-commit` (local to your clone).

### 2. Move secrets to the ignored `secrets/` directory

Any Kubernetes Secret manifests or files containing credentials should be moved to `secrets/`:

```bash
# Manual move
mv manifests/my-secret.yaml secrets/

# Or use the automated scanner
./scripts/move-manifest-secrets.sh
```

The `secrets/` directory is gitignored and **will not be committed**.

### 3. Reference secrets externally

Instead of embedding secrets in manifests, reference them:

```yaml
# Good: reference an existing secret
env:
  - name: API_TOKEN
    valueFrom:
      secretKeyRef:
        name: my-secret
        key: token

# Bad: embed the token
env:
  - name: API_TOKEN
    value: "abc123secrettoken"
```

### 4. Use placeholders in versioned configs

If you need to track a config template that requires secrets:

```yaml
# values-example.yaml (committed)
apiToken: "CHANGEME_INSERT_TOKEN_HERE"
password: "CHANGEME_INSERT_PASSWORD_HERE"
```

Document the required secrets in a README or in comments.

## Pre-Commit Hook

The pre-commit hook (`scripts/pre-commit-check-secrets.sh`) scans all staged files for:

- Kubernetes Secret manifests (`kind: Secret`, `stringData:`, `data:` keys)
- Secret-like keywords: `password`, `passwd`, `api_token`, `api_key`, `tunnel_secret`, `jwt_secret`, `secret_key`, `access_key`
- Private key material: `-----BEGIN PRIVATE KEY-----`, `-----BEGIN ENCRYPTED PRIVATE KEY-----`
- Cloudflare Argo Tunnel tokens: `ARGO TUNNEL TOKEN`

If detected, the commit is **aborted** with an error message.

### Installing on each machine

The hook is local to each git clone (`.git/hooks/` is not versioned). Each developer/admin must run:

```bash
./scripts/install-git-hooks.sh
```

### Bypassing the hook (emergency only)

If you absolutely must bypass (e.g., committing a non-sensitive file that triggers false positive):

```bash
git commit --no-verify -m "message"
```

**Use with extreme caution.** Review carefully before bypassing.

## Directory Security Model

### Tracked (versioned in git)
- `scripts/` — Operational scripts (no secrets)
- `manifests/` — Kubernetes manifests (no plaintext secrets; use Secret references)
- `patch/` — ConfigMap patches (review for embedded tokens)
- `tests/` — Test scripts
- `docs/` — Documentation

### Ignored (not tracked; may contain secrets)
- `secrets/` — **Plaintext secrets moved here; never commit**
- `cloudflared/` — Cloudflare Tunnel credentials (`.json`, `.pem` files gitignored)
- `helm/` — Helm values with embedded passwords/tokens (entire directory gitignored)
- `snap-links/` — Local symlinks (node-specific; not secrets but not portable)
- `deprecated/` — Archived configs (may contain old secrets; gitignored)
- `backup/` — Cluster backups (may contain sensitive data; gitignored)

## What Constitutes a Secret

Treat the following as secrets and **never commit**:

### Credentials
- Passwords, passphrases, PINs
- API keys and tokens (Cloudflare API token, GitHub PAT, etc.)
- OAuth client secrets
- Database passwords
- SMTP passwords
- JWT secrets
- Encryption keys

### Cryptographic material
- Private keys (RSA, ECDSA, ed25519)
- TLS certificates with embedded private keys
- SSH private keys
- GPG/PGP private keys
- Cloudflare Argo Tunnel tokens

### Kubernetes Secrets
- Any YAML manifest with `kind: Secret`
- Base64-encoded data in `data:` or plaintext in `stringData:` fields
- Service account tokens

### Configuration with embedded secrets
- Helm values files with `password:`, `apiKey:`, `token:` fields populated
- ConfigMaps containing tokens or credentials
- Environment files (`.env`) with secrets

## Credential Rotation

If a secret was accidentally committed:

### 1. Rotate the credential immediately

Treat the exposed credential as **compromised**. Generate a new secret and update all references:

- **API tokens:** Revoke old token, generate new one
- **Passwords:** Change password
- **Private keys:** Generate new keypair, revoke old public key
- **Cloudflare Tunnel tokens:** Delete tunnel, create new one

### 2. Remove from working tree

```bash
# Move to secrets/ (gitignored)
mv manifests/leaked-secret.yaml secrets/

# Or delete if no longer needed
git rm manifests/leaked-secret.yaml

# Commit the removal
git commit -m "security: remove leaked secret"
```

### 3. Purge from git history

See [Removing Secrets from Git History](#removing-secrets-from-git-history) below.

### 4. Update documentation

Document what was rotated and ensure team members update local configs.

## Removing Secrets from Git History

Removing a file from the latest commit is **not enough**. The secret remains in git history and can be retrieved by anyone with access to the repository.

### Using git-filter-repo (recommended)

Install `git-filter-repo`:
```bash
# Ubuntu/Debian
sudo apt install git-filter-repo

# Or via pip
pip install git-filter-repo
```

Remove specific files:
```bash
# Backup first
git clone /shared/microk8s /tmp/microk8s-backup

# Remove files from all history
git filter-repo --path cloudflared/cert.pem --invert-paths \
                --path cloudflared/f6d4f944-45a5-4497-bba9-ebd31de176ca.json --invert-paths \
                --path helm/charts/values-secret.yaml --invert-paths

# Force push (coordinate with team!)
git push origin --force --all
git push origin --force --tags
```

### Using BFG Repo-Cleaner (alternative)

```bash
# Install BFG
# https://rtyley.github.io/bfg-repo-cleaner/

# Remove specific files
bfg --delete-files 'cert.pem' /shared/microk8s
bfg --delete-files '*.json' --no-blob-protection /shared/microk8s

cd /shared/microk8s
git reflog expire --expire=now --all
git gc --prune=now --aggressive

git push origin --force --all
```

### After rewriting history

1. **Coordinate with all contributors:** They must re-clone or rebase
2. **Verify secrets are gone:** Use `git log --all --full-history -- path/to/file`
3. **Rotate affected credentials** (treat as compromised)

## Future: Encrypted Secrets

See [docs/TODO.md](docs/TODO.md) for planned improvements.

### Recommended approaches

1. **SOPS (Mozilla)** — Encrypt YAML files with age/GPG/KMS
   - Pros: Fine-grained encryption; supports multiple backends
   - Cons: Requires key management
   - Workflow: Encrypt values files, commit encrypted version, decrypt at apply-time

2. **Sealed Secrets (Bitnami)** — Controller-based secret encryption
   - Pros: Cluster-native; safe to commit sealed manifests
   - Cons: Requires running controller; dependency
   - Workflow: `kubeseal` encrypts Secret → commit SealedSecret YAML → controller decrypts on-cluster

### Example: SOPS workflow

```bash
# Install sops and age
sudo apt install age
wget https://github.com/mozilla/sops/releases/latest/download/sops_amd64.deb
sudo dpkg -i sops_amd64.deb

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Create .sops.yaml in repo root
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
EOF

# Encrypt a file
sops -e secrets/my-secret.yaml > secrets/my-secret.enc.yaml

# Commit encrypted version
git add secrets/my-secret.enc.yaml .sops.yaml
git commit -m "Add encrypted secret"

# Decrypt for use
sops -d secrets/my-secret.enc.yaml | kubectl apply -f -
```

## Reporting Security Issues

If you discover a security vulnerability or accidentally committed secret:

1. **Do not open a public issue**
2. **Rotate the credential immediately** (assume compromised)
3. Contact the repository maintainer directly
4. Follow credential rotation and history purging steps above

For this repository: contact the repository owner via GitHub private message or email.

## Best Practices Summary

✅ **DO:**
- Install and use the pre-commit hook
- Store secrets in `secrets/` directory (gitignored)
- Use Kubernetes Secret references in manifests
- Rotate credentials if accidentally exposed
- Purge secrets from git history after exposure
- Use placeholders (`CHANGEME`) in example configs

❌ **DON'T:**
- Commit plaintext passwords, tokens, or keys
- Embed secrets directly in manifests or Helm values
- Bypass the pre-commit hook without careful review
- Assume removing a file in the latest commit removes it from history
- Share credentials via chat/email (use secure secret stores)

## Additional Resources

- [GitHub: Removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [SOPS documentation](https://github.com/mozilla/sops)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [git-filter-repo](https://github.com/newren/git-filter-repo)
