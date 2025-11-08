# Project TODOs

- [ ] Convert the automation script to ansible playbooks
- [ ] Create backup and restore automations that use `microk8s dbctl`
- [ ] Investigate storing encrypted secrets in repo (SOPS / SealedSecrets). This will allow keeping secrets alongside manifests while keeping them encrypted at-rest and in git history.
  - Rationale: avoid committing plain Secret manifests while still keeping declarative infra in git.
  - Next steps: test SOPS with age/GPG; evaluate SealedSecrets controller for your cluster.
