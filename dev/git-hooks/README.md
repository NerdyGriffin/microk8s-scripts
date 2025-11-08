# Git Hooks

Version-controlled Git hooks for this repository.

## Why keep hooks in the repo?
- Shared, reviewable source of truth (unlike `.git/hooks`, which is unversioned)
- Easy onboarding for new clones
- Maintainable: hooks evolve with the codebase

## Pre-commit secret scanner
Hook: `pre-commit-check-secrets.sh`
- Blocks commits that include plaintext secrets
- Scans staged files only (respects `.gitignore`)

## Install
Run from the repo root:

```
./dev/git-hooks/install-git-hooks.sh
```

This installs (or updates) `.git/hooks/pre-commit`:
- Prefers a symlink to the versioned hook in `dev/git-hooks/`
- Falls back to a file copy if symlink is not possible

You need to run this once per clone. `.git/hooks` is local to your machine and is not committed.
