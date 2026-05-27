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

## Subscription Operations

The backend is the source of truth for account plans. Free owned homes are limited to 100 total containers plus items, 5 images, and 5 documents. Active App Store, manual, promo, or admin entitlements remove those limits. Sharing a home requires the home owner to have an active paid entitlement; invited free users can use that paid owner's home with the paid feature set while the owner remains paid.

Configure App Store Connect with these auto-renewable subscription product IDs unless `APP_STORE_SUBSCRIPTION_PRODUCT_IDS` is changed:

```sh
com.jimgreco.stufftracker.pro.monthly
com.jimgreco.stufftracker.pro.yearly
```

Point App Store Server Notifications V2 at the production backend:

```text
POST https://<backend-origin>/app-store/notifications
```

Production and sandbox App Store signed payload verification requires Apple root certificates on the backend host. Set either `APP_STORE_ROOT_CERTIFICATE_PATHS` to comma-separated certificate files or `APP_STORE_ROOT_CERTIFICATES_DIR` to a directory containing `.cer`, `.der`, or `.pem` files. Production also requires `APP_STORE_APP_APPLE_ID`. Keep `APP_STORE_BUNDLE_ID` aligned with the shipped iOS bundle identifier.

In the production `../deploy` Compose stack, these are supplied to the Stuff container from `~/deploy/.env` as `STUFF_APP_STORE_APP_APPLE_ID` and `STUFF_ADMIN_API_TOKEN`. The product IDs and bundle ID have safe defaults in `docker-compose.yml`, and Apple root certificates are mounted from `~/deploy/apple-pki`.

The iOS app sends verified StoreKit transactions to `POST /account/app-store/transactions`, using the authenticated user ID as the StoreKit app account token. On renewals, refunds, and revocations, App Store Server Notifications update the same entitlement row by original transaction ID.

Web does not sell subscriptions. To enable an account from web or support without App Store purchase, set `ADMIN_API_TOKEN` and call:

```sh
curl -X POST "$API_ORIGIN/admin/entitlements" \
  -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","source":"manual"}'
```

Use `source` values `manual`, `promo`, or `admin`. Add an ISO `expires_at` value for time-limited grants.

## Production Health Monitoring

The `Production Health` GitHub Actions workflow checks `/health/live` and `/health` on an hourly schedule. Set the `PRODUCTION_BASE_URL` repository secret to the public backend origin, with no trailing slash, to enable the check.

If `PRODUCTION_BASE_URL` is unset, the workflow exits successfully with a notice so the workflow can be merged before the secret is configured. When enabled, the check fails if either health endpoint is unreachable, if `ok` is not `true`, or if `/health` does not report `db: true`.

Treat a failing scheduled health run as an availability incident and follow the incident response runbook above.

## Production Ops Checks

The `Production Ops Checks` GitHub Actions workflow runs daily and can also be started manually. When `EC2_HOST`, `EC2_USER`, `EC2_SSH_KEY`, and `EC2_SSH_KNOWN_HOSTS` are configured, it SSHes to the production host and runs these read-only checks:

```sh
# Host backup freshness check against ~/deploy/backups/stuff by default.
npm run storage:s3:check
npm run db:hardening:check
```

The backup freshness check reads host backups from `~/deploy/backups/stuff` by default. Override that path on the production host with `STUFF_DB_BACKUP_DIR` in `~/deploy/.env`. Freshness failures should be treated as incidents.

Treat a failing scheduled ops check as an operational incident. Backup freshness failures mean the backup job, backup directory, durable copy, or `DB_BACKUP_MAX_AGE_HOURS` needs review. S3 hardening failures mean public access block, policy status, default encryption, or lifecycle configuration needs review in AWS before the app should be considered production-hardened. Database hardening failures mean production may no longer be running through the least-privilege app role and should be investigated before the app is considered production-hardened.

## Production Logging

Production HTTP access logs are JSON lines with `event=http_request`, `request_id`, method, path, status, duration, response length, remote address, and user agent. The API accepts a valid `x-request-id` header or generates one, then echoes it on the response so app logs and client-side reports can be correlated.

Unhandled production errors are logged as JSON lines with `event=unhandled_error` and the same `request_id` when one is available.

Set `OPERATIONS_ALERT_WEBHOOK_URL` to post unhandled production backend errors to an operations channel. The payload includes `service`, `event`, `level`, `message`, `request_id`, `timestamp`, and the serialized error. `OPERATIONS_ALERT_TIMEOUT_MS` controls the webhook timeout and defaults to 3000 ms.

The backend also posts `http_error_rate` alerts when production 5xx responses cross the rolling threshold. Defaults are `ERROR_RATE_ALERT_WINDOW_MS=300000`, `ERROR_RATE_ALERT_MIN_REQUESTS=20`, `ERROR_RATE_ALERT_MIN_5XX=5`, `ERROR_RATE_ALERT_5XX_PERCENT=20`, and `ERROR_RATE_ALERT_COOLDOWN_MS=900000`. Tune these values if normal low-traffic behavior creates noise.

The same `OPERATIONS_ALERT_WEBHOOK_URL` GitHub secret enables workflow failure alerts for deploy, production health, production backup, production ops checks, and restore drills. If the secret is unset, those workflows emit a notice and continue without sending an alert.

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
- `DB_PASSWORD`
- `STUFF_DATABASE_URL`
- `STUFF_MIGRATION_DATABASE_URL`
- `JWT_SECRET`
- `GOOGLE_CLIENT_ID`
- Apple Sign In configuration for `APPLE_BUNDLE_ID`
- S3 bucket credentials and bucket policy
- iOS signing certificate, provisioning profile, and App Store Connect API key

## Session Tokens

Backend auth tokens are signed with `JWT_SECRET`. `JWT_EXPIRES_IN` controls the access-token lifetime using the `jsonwebtoken` duration format, and defaults to `30m` when unset. `REFRESH_TOKEN_EXPIRES_IN_DAYS` controls refresh-token lifetime and defaults to `90`.

Production should set explicit values and review them during release hardening. Access tokens can be short-lived because `POST /auth/refresh` rotates an opaque refresh token and returns a new access token for the same server-side session. Server-side logout-all revocation is available through `POST /auth/logout-all`. New sign-ins also create server-side auth sessions, `GET /auth/sessions` lists active sessions for the current user, and `DELETE /auth/sessions/:sessionId` revokes one session.

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

Production can set `MIGRATION_DATABASE_URL` separately from `DATABASE_URL`. When present, the container runs migrations with `MIGRATION_DATABASE_URL` and then starts the API with `DATABASE_URL`, allowing the app runtime to use a lower-privilege role than the migration role.

## Database Access Hardening

The `Production DB Hardening` workflow can validate or apply Stuff database role hardening on the production host. In apply mode it:

- Creates or rotates separate `stuff_app` and `stuff_migrator` roles.
- Grants the app role table DML privileges without schema ownership or create privileges.
- Transfers existing public-schema objects to the migration role.
- Sets role and database connection limits.
- Writes `STUFF_DATABASE_URL` and `STUFF_MIGRATION_DATABASE_URL` into `~/deploy/.env`.
- Restarts the Stuff container, waits for `/health`, runs `npm run db:hardening:check`, and runs deploy smoke tests.

The current production database is reachable only over the private Docker network. The generated Stuff database URLs use `sslmode=disable` for that internal connection; require SSL before moving Postgres onto a network path outside the private host/container boundary. Set `DB_REQUIRE_SSL=true` for the runtime DB hardening check when SSL is enabled.

Latest recorded production DB hardening apply:

- Date: 2026-05-25 17:24 UTC.
- Workflow run: `Production DB Hardening` run `26412219942`, commit `da9ddd89d3ddd45f30f74deba4bf7bf3a17cfe07`.
- Result: rotated `stuff_app` and `stuff_migrator` passwords, wrote `STUFF_DATABASE_URL` and `STUFF_MIGRATION_DATABASE_URL`, restarted the Stuff container, and confirmed `/health`.
- Role verification: `stuff_app` and `stuff_migrator` exist; database connection limit is `16`; role connection limits are `stuff_app=10` and `stuff_migrator=2`; both roles are non-superuser, no-createdb, and no-createrole.
- Runtime verification: `npm run db:hardening:check` confirmed the app connects as `stuff_app` to database `stuff`; SSL is currently `off` for the private Docker-network connection.
- Smoke verification: `npm run smoke:deploy` passed.
- Follow-up ops check: `Production Ops Checks` run `26412243579` confirmed the backup is fresh, S3 hardening passed, and the runtime DB role check still passes after rotation.

Manual validation:

```sh
cd backend
DB_EXPECTED_APP_ROLE=stuff_app npm run db:hardening:check
```

## Database Backups

The `Production Backup` GitHub Actions workflow runs daily and can also be started manually. It SSHes to the production host, runs `pg_dump` from the Postgres container, writes a gzipped backup to `~/deploy/backups/stuff`, and deletes backups older than `STUFF_DB_BACKUP_RETENTION_DAYS` days. The default retention is 30 days.

Production backup host settings:

- `STUFF_DB_BACKUP_DIR`: optional host backup directory, defaulting to `~/deploy/backups/stuff`.
- `STUFF_DB_BACKUP_RETENTION_DAYS`: optional retention window, defaulting to `30`.
- `DB_BACKUP_MAX_AGE_HOURS`: freshness threshold used by `Production Ops Checks`, defaulting to `26`.

The backend image also includes `pg_dump` and `gzip`, so the app backup script can be used in environments where `DB_BACKUP_DIR` points at durable storage. The script writes a gzipped `pg_dump` to `DB_BACKUP_DIR`.

```sh
cd backend
npm run db:backup
```

Check that the newest backup is recent and non-empty:

```sh
cd backend
npm run db:backup:check
```

`DB_BACKUP_MAX_AGE_HOURS` defaults to `26`. Schedule the backup and freshness check on the server with cron or systemd, send freshness failures to an alerting channel, and sync the backup directory to durable storage.

## Database Restore

Backups created by `npm run db:backup` are gzipped plain SQL dumps. Restore into a new database first, verify the result, then decide whether to promote it. Do not restore directly over production unless you have explicitly accepted the data-loss window.

The `Production Restore Drill` GitHub Actions workflow can be started manually. It finds the newest production backup, restores it into a temporary database inside the production Postgres container, checks key table counts, reports elapsed time, and drops the temporary database on exit.

Latest recorded restore drill:

- Date: 2026-05-25 17:22 UTC.
- Backup: `stuff-tracker-2026-05-25T11-18-51Z.sql.gz`.
- Workflow run: `Production Restore Drill` run `26412147708`.
- Restore target: temporary production-host database `stuff_restore_drill_20260525172220`, dropped automatically.
- Verification: `schema_migrations=4`, `users=2`, `homes=2`, `items=62`.
- Restore elapsed time: 1 second.
- Observed recovery point: backup was about 6 hours old at restore time.

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
- Run `npm run db:backup:check` on the host that writes backups.
- Restore the newest backup into a disposable database.
- Run the basic verification queries.
- Point a staging or local backend at the restored database and check `/health`.
- Record elapsed restore time and the backup timestamp.

Current recovery expectations:

- RTO target: restore service within 30 minutes after backup access is available.
- RPO target: no better than the configured backup schedule.

## Operational Drill Log

Latest recorded hardening drill:

- Date: 2026-05-25 17:21-17:25 UTC.
- Deploy and rollback path: `Deploy to EC2` run `26412217910` passed after the hardening workflow fix. The rollback path remains the documented revert or forward-fix through `main`; no intentional production rollback was performed during this drill.
- Credential rotation: `Production DB Hardening` run `26412219942` rotated app and migration DB role passwords, restarted Stuff, validated the runtime DB role, and passed deploy smoke tests.
- Restore verification: `Production Restore Drill` run `26412147708` restored the newest backup into a temporary database and verified key table counts.
- Follow-up monitoring: `Production Ops Checks` run `26412243579` passed backup freshness, S3 hardening, and runtime DB hardening checks.
- Remaining note: production DB SSL is intentionally off while Postgres is only reachable over the private Docker network; enable database SSL and `DB_REQUIRE_SSL=true` before moving Postgres outside that boundary.

## Attachment Cleanup

Review S3 bucket hardening without changing bucket policy:

```sh
cd backend
npm run storage:s3:check
```

The check fails if public access block is incomplete, the bucket policy is public, or default server-side encryption is missing. It warns when lifecycle configuration is missing. A missing bucket policy is acceptable for the production bucket because attachment access is granted through the EC2 instance role only.

Production S3 posture:

- Public access block: all four settings enabled.
- Bucket policy: none.
- EC2 instance role policy: `s3:GetObject`, `s3:PutObject`, and `s3:AbortMultipartUpload` on the attachment bucket objects; `s3:GetBucketLocation`, `s3:GetBucketPublicAccessBlock`, `s3:GetBucketPolicyStatus`, `s3:GetEncryptionConfiguration`, and `s3:GetLifecycleConfiguration` on the bucket for read-only posture checks.
- Default bucket encryption: AES256.
- Direct uploads: the backend includes `x-amz-server-side-encryption` in the required signed-upload headers, defaulting to `AES256`.
- Lifecycle: abort incomplete multipart uploads after 7 days.

Run a dry cleanup first:

```sh
cd backend
npm run storage:cleanup
```

Delete orphaned S3 uploads older than `ORPHANED_UPLOAD_MIN_AGE_HOURS` by setting:

```sh
DELETE_ORPHANED_UPLOADS=true npm run storage:cleanup
```
