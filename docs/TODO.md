# Project TODOs

- [ ] Investigate storing encrypted secrets in repo (SOPS / SealedSecrets). This will allow keeping secrets alongside manifests while keeping them encrypted at-rest and in git history.
  - Rationale: avoid committing plain Secret manifests while still keeping declarative infra in git.
  - Next steps: test SOPS with age/GPG; evaluate SealedSecrets controller for your cluster.
