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
- [x] Add an operational runbook for incident triage, failed deploy rollback, and credential rotation.
- [x] Add Dependabot automation for backend npm packages and GitHub Actions.
- [x] Add CodeQL code scanning for backend JavaScript/TypeScript.
- [x] Review GitHub secret scanning settings and document alert handling.
- [x] Make JWT lifetime configurable and document production session-token guidance.
- [x] Resolve current backend npm audit advisories for Express, qs, Google auth, gaxios, and uuid.
- [x] Validate stored attachment bytes for newly saved S3 photo and document uploads.
- [x] Strip photo metadata by recompressing selected and captured iOS photos before upload.

## Next

- [ ] Make S3 fully private: block public access, use least-privilege IAM, enforce server-side encryption, and review bucket lifecycle policy.
- [ ] Add session hardening: refresh tokens or reauth flow, token revocation, device/session listing, and logout-all.
- [ ] Add production observability: structured logs, app error reporting, uptime checks, deploy alerts, and error-rate alerts.
- [ ] Schedule database backups and run a restore drill; record actual restore time and recovery point.
- [ ] Harden database access: separate app and migration DB roles, least privilege, SSL enforcement, connection limits, and secret rotation.
- [ ] Add post-deploy smoke tests: health, auth, upload-signing, and basic item CRUD.
- [ ] Run an operational drill covering failed deploy rollback, credential rotation, and database restore.

## Suggested Order

1. S3 private-by-default policy and IAM cleanup.
2. Backup scheduling plus restore drill.
3. Observability and deploy smoke tests.
4. JWT revocation and refresh-token design.
5. Database role separation and SSL enforcement.
