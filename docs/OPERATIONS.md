# Operations

## Required GitHub Secrets

- `EC2_SSH_KEY`: private deployment key.
- `EC2_SSH_KNOWN_HOSTS`: pinned SSH host key entry for `EC2_HOST`.
- `EC2_USER`: deployment user.
- `EC2_HOST`: deployment host.
- iOS signing and App Store Connect secrets used by `.github/workflows/testflight.yml`.

Generate the pinned host key from a trusted network and review it before saving. Include each hostname or IP form that `EC2_HOST` might use:

```sh
ssh-keyscan -H "$EC2_HOST"
```

## Branch Protection

Protect `main` in GitHub and require these status checks before merge:

- `verify`
- `test`

Keep direct pushes limited to maintainers. The deploy workflow only deploys on pushes to `main`; pull requests run verification without deploying.

## Incident Response

Use this runbook for production incidents, suspected credential exposure, failed deploys, and data recovery events. Keep notes with exact UTC timestamps, the observed impact, commands run, and the commit or backup involved.

Initial triage:

- Identify the affected surface: iOS app, backend API, database, S3 attachments, CI/CD, or account auth.
- Check the latest GitHub Actions runs for `Deploy to EC2` and `TestFlight`.
- Check `/health/live` for process liveness and `/health` for database connectivity.
- If the incident follows a deploy, compare the current commit against the last known-good commit.
- Avoid destructive recovery commands until the impact, recovery point, and expected data loss are explicit.

Escalation criteria:

- Authentication is unavailable or appears compromised.
- Writes are failing or data integrity is uncertain.
- Attachment uploads or reads expose data unexpectedly.
- A deploy changed production behavior and cannot be fixed quickly.
- Database restore, credential rotation, or provider console changes are required.

## Failed Deploy Rollback

Preferred rollback path is a revert or forward-fix through `main`, because the deploy workflow is the source of record for production backend code.

1. Identify the last known-good commit.
2. Revert the bad commit or prepare a forward-fix locally.
3. Run backend verification:

   ```sh
   cd backend
   npm run build
   npm test
   npm audit --omit=dev
   ```

4. Push to `main` and watch the `Deploy to EC2` workflow.
5. Confirm `/health` after deploy completion.

If GitHub Actions is unavailable and production is down, manually deploy a clean checkout of the last known-good commit from a trusted machine using the same backend files and pinned SSH host key. Record that manual action and reconcile `main` afterward.

## Post-Deploy Smoke Tests

The deploy workflow runs `npm run smoke:deploy` inside the rebuilt production container after each backend deploy. The smoke test checks `/health/live`, `/health`, authenticated `/homes`, home creation/deletion, item creation/deletion, and attachment upload signing.

The smoke test creates a short-lived user and a temporary home/item, then deletes them before exiting. If cleanup fails, delete rows matching `deploy-smoke-%@stufftracker.local` after recording the failed run.

## Production Logging

Production HTTP access logs are JSON lines with `event=http_request`, `request_id`, method, path, status, duration, response length, remote address, and user agent. The API accepts a valid `x-request-id` header or generates one, then echoes it on the response so app logs and client-side reports can be correlated.

Unhandled production errors are logged as JSON lines with `event=unhandled_error` and the same `request_id` when one is available.

## Credential Rotation

Rotate credentials when there is suspected exposure, staff/device loss, provider key rollover, or after an incident involving secrets. Prefer adding a replacement secret before removing the old one when the provider supports overlap.

Rotation checklist:

- Identify all consumers of the secret.
- Create or obtain the replacement credential.
- Update the relevant GitHub secret or server environment variable.
- Redeploy or restart only the affected service.
- Verify the affected flow.
- Revoke the old credential.
- Record the rotation time and verification result.

High-value credentials:

- `EC2_SSH_KEY`
- `EC2_SSH_KNOWN_HOSTS`
- `DATABASE_URL`
- `JWT_SECRET`
- `GOOGLE_CLIENT_ID`
- Apple Sign In configuration for `APPLE_BUNDLE_ID`
- S3 bucket credentials and bucket policy
- iOS signing certificate, provisioning profile, and App Store Connect API key

## Session Tokens

Backend auth tokens are signed with `JWT_SECRET`. `JWT_EXPIRES_IN` controls the token lifetime using the `jsonwebtoken` duration format, and defaults to `90d` when unset.

Production should set an explicit value and review it during release hardening. A shorter lifetime such as `14d` or `30d` limits exposure from a copied token while keeping the current mobile sign-in flow usable. Server-side logout-all revocation is available through `POST /auth/logout-all`; refresh tokens, reauth UX, and device/session listing are not implemented yet, so do not set a very short lifetime until the clients can reauthenticate cleanly.

## GitHub Security Monitoring

Current repository security setting review from GitHub API:

- Secret scanning: enabled.
- Secret scanning push protection: enabled.
- Secret scanning non-provider patterns: disabled.
- Secret scanning validity checks: disabled.
- Dependabot security updates: disabled.

Review cadence:

- Check GitHub security alerts weekly when Dependabot opens updates.
- Treat secret scanning alerts as incidents until the exposed credential is rotated or proven invalid.
- Consider enabling non-provider patterns and validity checks if alert volume is acceptable.
- Consider enabling Dependabot security updates if automated vulnerability PRs are preferred over manual review.

## Database Migrations

Migrations live in `backend/src/db/migrations` and are applied once in lexical order. Add new schema changes as a new numbered SQL file instead of editing an already-applied migration.

```sh
cd backend
npm run db:migrate
```

## Database Backups

The backup script writes a gzipped `pg_dump` to `DB_BACKUP_DIR`.

```sh
cd backend
npm run db:backup
```

Schedule it on the server with cron or systemd and sync the backup directory to durable storage.

## Database Restore

Backups created by `npm run db:backup` are gzipped plain SQL dumps. Restore into a new database first, verify the result, then decide whether to promote it. Do not restore directly over production unless you have explicitly accepted the data-loss window.

Prerequisites:

- Access to the backup file.
- A target Postgres database URL in `RESTORE_DATABASE_URL`.
- `psql` and `gunzip` available on the restore host.

Restore to a fresh database:

```sh
export RESTORE_DATABASE_URL='postgresql://...'
gunzip -c /path/to/stuff-tracker-backup.sql.gz | psql "$RESTORE_DATABASE_URL"
```

Basic verification:

```sh
psql "$RESTORE_DATABASE_URL" -c 'select count(*) from homes;'
psql "$RESTORE_DATABASE_URL" -c 'select count(*) from items;'
psql "$RESTORE_DATABASE_URL" -c 'select count(*) from schema_migrations;'
```

Restore drill checklist:

- Confirm the newest backup is present in durable storage.
- Restore the newest backup into a disposable database.
- Run the basic verification queries.
- Point a staging or local backend at the restored database and check `/health`.
- Record elapsed restore time and the backup timestamp.

Current recovery expectations until a real drill is recorded:

- RTO target: restore service within 30 minutes after backup access is available.
- RPO target: no better than the configured backup schedule; this remains undefined until backups are scheduled.

## Attachment Cleanup

Run a dry cleanup first:

```sh
cd backend
npm run storage:cleanup
```

Delete orphaned S3 uploads older than `ORPHANED_UPLOAD_MIN_AGE_HOURS` by setting:

```sh
DELETE_ORPHANED_UPLOADS=true npm run storage:cleanup
```
