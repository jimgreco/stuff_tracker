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
- [x] Add post-deploy smoke tests for health, auth, upload signing, and basic item CRUD.
- [x] Add structured production HTTP/error logs with request IDs.
- [x] Add server-side token revocation support and a logout-all API endpoint.
- [x] Add a database backup freshness check for scheduled backup monitoring.
- [x] Add a read-only S3 hardening check for public access, policy status, encryption, and lifecycle review.
- [x] Add a scheduled production health check workflow for `/health/live` and `/health`.
- [x] Add a scheduled production ops check workflow for backup freshness and S3 hardening verification.
- [x] Make S3 fully private: block public access, remove the public-read bucket policy, rely on least-privilege EC2 IAM, require encrypted uploads, confirm bucket default encryption, and keep the lifecycle rule.
- [x] Add a scheduled production database backup workflow that writes durable host backups and make ops checks fail when no fresh backup exists.
- [x] Add server-side auth sessions with device/session listing and per-session revocation.
- [x] Add optional production webhook alerts for unhandled backend errors.
- [x] Add a manual production restore-drill workflow that restores the newest backup into a temporary database and verifies key tables.
- [x] Add optional operations webhook alerts for deploy, health, backup, ops-check, and restore-drill workflow failures.
- [x] Run a production backup restore drill and record actual restore time and recovery point.
- [x] Add optional rolling 5xx error-rate alerts for production HTTP responses.
- [x] Add rotating refresh tokens with shorter-lived access tokens and iOS automatic refresh.
- [x] Harden database access with separate app and migration DB roles, least privilege grants, connection limits, app DB credential rotation, and runtime DB role checks.
- [x] Run an operational drill covering the documented deploy rollback path, production DB credential rotation, production smoke verification, ops checks, and backup restore verification.

## Next

- No open hardening backlog items are currently tracked.

## Suggested Order

- All currently tracked hardening items are complete.
