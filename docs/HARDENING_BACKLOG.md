# Hardening Backlog

This is the working checklist for security, reliability, and operations hardening. Keep completed work in this file so future changes have a clear trail.

## Done

- [x] Add backend runtime hardening: Helmet, CORS allowlist behavior, JSON body limits, trust-proxy parsing, hidden `x-powered-by`, 404 handling, centralized errors, and health endpoints.
- [x] Validate runtime environment, including production JWT secret length.
- [x] Move iOS auth token storage from `UserDefaults` to Keychain with a one-time migration.
- [x] Harden Google and Apple account linking with transaction-backed user upserts and identity-conflict handling.
- [x] Add auth and upload rate limits.
- [x] Add attachment upload size limits, photo content-type validation, signed read URLs, S3 key parsing, and orphan-upload cleanup.
- [x] Add numbered database migrations and a `schema_migrations` table.
- [x] Add database backup and cleanup scripts.
- [x] Add backend CI with typecheck, tests, npm audit, and Postgres-backed integration checks.
- [x] Make required GitHub checks report consistently for backend and iOS workflows.
- [x] Protect `main` with required `verify` and `test` checks.
- [x] Pin EC2 SSH host keys in `EC2_SSH_KNOWN_HOSTS`.
- [x] Remove deploy-time SSH host-key scanning fallback.
- [x] Move GitHub Actions checkout and Node setup actions to Node 24-ready major versions.
- [x] Document database restore steps, verification checks, and provisional recovery targets.

## Next

- [ ] Tighten GitHub branch protection: require pull requests before merging, require conversation resolution, consider requiring one review, and decide whether to enforce rules for admins.
- [ ] Make S3 fully private: block public access, use least-privilege IAM, enforce server-side encryption, and review bucket lifecycle policy.
- [ ] Validate uploaded file bytes instead of trusting MIME strings; strip image metadata and consider recompressing photos before upload/storage.
- [ ] Add session hardening: shorter JWT lifetime, refresh tokens or reauth flow, token revocation, device/session listing, and logout-all.
- [ ] Add production observability: structured logs, app error reporting, uptime checks, deploy alerts, and error-rate alerts.
- [ ] Schedule database backups and run a restore drill; record actual restore time and recovery point.
- [ ] Harden database access: separate app and migration DB roles, least privilege, SSL enforcement, connection limits, and secret rotation.
- [ ] Add dependency and supply-chain automation: Dependabot, GitHub code scanning, and secret scanning review.
- [ ] Add post-deploy smoke tests: health, auth, upload-signing, and basic item CRUD.
- [ ] Add an operational runbook for incident response, credential rotation, failed deploy rollback, and database restore.

## Suggested Order

1. GitHub branch protection policy.
2. S3 private-by-default policy and IAM cleanup.
3. Backup scheduling plus restore drill.
4. Observability and deploy smoke tests.
5. JWT/session hardening.
6. Database role separation and SSL enforcement.
7. Dependency/code scanning automation.
