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
