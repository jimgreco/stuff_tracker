# CubbyLog account-store / attachment-GC release — 2026-10-07

Prepared on `codex/cubbylog-account-stores-20261007`, isolated checkout
`/Users/jgreco/Documents/Codex/2026-10-07/task-3/cubbylog`, from verified remote main
`5854a24`. The original `/Users/jgreco/code/stuff` checkout and prior task-19 audit
were preserved. This release is committed locally, not pushed, deployed, archived
for devices, or uploaded to TestFlight.

## Exact implementation commits

- `2331bb0ad7304a3eb0948367fa8bc49da1f83fc4` — attachment adoption/cleanup serialization,
  durable deletion reservations, migration 013, synthetic provider and real-Postgres
  race tests.
- `84b141d293b81d2587ccf877cd6d38673719daac` — independent native account stores,
  lossless migration/archive, explicit legacy recovery/export/skip/conflict handling,
  scoped media caches, session/store/plan guards, and regression tests.

These commits form the proposed release scope. The subsequent documentation commit
only records this release plan. No health/alert/backup workflow changes, dependency
updates, real cleanup, provider sends, credential changes or real-user recovery
are included.

## Verification on the implementation tree

| Check | Result | Local evidence (excluded from Git) |
| --- | --- | --- |
| Exact-lockfile install | `npm ci --ignore-scripts` in isolated checkout succeeded | `evidence/npm-ci.log` |
| Backend TypeScript | Build succeeded | `evidence/backend-build.log` |
| Backend unit/synthetic suite | 90 passed; 5 DB tests intentionally gated in this invocation | `evidence/backend-full-exact-lock.log` |
| PostgreSQL integration | All 5 gated tests passed against disposable Postgres 16 | `evidence/postgres-exact-lock.log` |
| Media-specific synthetic suite | 9 passed, no actual S3 client calls | `evidence/backend-media.log` |
| Production lockfile audit | 0 known advisories | `evidence/production-audit.json` |
| All-dependency audit | 1 existing low development-only esbuild advisory; dependency lane follow-up | `evidence/all-dependency-audit.json` |
| Native XCTest | 67 passed, 0 failed | `evidence/native-verified.log`, `.xcresult` |
| Native Release simulator | Build succeeded | `evidence/native-release-build.log` |
| Recovery UI | Synthetic account rendered; claim, export, skip and cancel visible | `evidence/native-screen-verified/` |
| Whitespace / cleanup script syntax | Passed | `git diff --check`, `node --check` |

The initial native run passed 62/64 tests: two byte-equality export checks detected
unstable JSON key order. Exports now use sorted keys; the expanded final 67-case
suite passes. First backend invocation encountered sandbox loopback restrictions;
normal tests were rerun with `DATABASE_URL` unset and database integration disabled.
The real database run used a newly initialized unique cluster and a local `_test`
database. Integration reset code now rejects nonlocal/non-`_test` targets.

Test fixture details: PostgreSQL `127.0.0.1:54873/cubby_gc_20261007_test`, all S3
responses synthetic; native simulator `CubbyAccounts20261007`, iPhone 17 Pro /
iOS 26.2, `0407880C-5CC4-4938-86CA-2D8D38B6FEBD`. Xcode ran with `-jobs 2` and
`-parallel-testing-enabled NO`, using a copied public package cache. That simulator
was deleted and the PostgreSQL fixture stopped; other simulators were untouched.
No physical-device archive, Apple signing/upload, actual S3/IAM validation or
production acceptance is implied by these results.

The development-only advisory is [GHSA-g7r4-m6w7-qqqr](https://github.com/advisories/GHSA-g7r4-m6w7-qqqr),
which affects the esbuild development server on Windows (`0.27.3–0.28.0`). A fix is
available; it is not in the production dependency tree and no lockfile update was
mixed into this lane. Route that update through the dependency lane.

## Coordinated release sequence

1. Parent confirms this exact scope and a shared-host window with the monitoring
   owner. Retain the current image and a verified database backup under the existing
   operations runbook. Prevent old cleanup jobs overlapping migration/deployment;
   do not edit shared monitoring workflows in this branch.
2. Publish/review these commits and run normal CI against their exact SHA. The
   current deploy workflow only deploys via explicit main `workflow_dispatch` with
   `deploy=true`; no workflow was dispatched during this task.
3. Apply additive migration 013 through the existing migration role and deploy the
   matching API plus cleanup scripts as one image. Drain old API/collector processes
   before enabling the new collector. Verify runtime table permissions inherited
   from the migration role's existing default privileges. No data backfill or new
   AWS permission is required by the implementation.
4. Perform the established smoke/check-only validation in the coordinated window.
   Its production smoke creates/deletes synthetic account rows, so include it in
   the parent's exact authorized release scope. Dry-run orphan inventory is an S3
   read; an actual cleanup pass is a separate deletion decision. Migration itself
   reserves or deletes no existing object.
5. Build/upload the native commit through the existing TestFlight process. Accept
   on a disposable physical device/account before broad rollout: known-owner legacy
   migration, unknown/mixed claim rejection or export, cancel/skip/recover, A/B/A
   with offline pending writes and deletes, mid-sync switching, network failure,
   Data Protection lock/unlock, low disk space and a realistically large inventory.
6. Only after owner acceptance schedule any real mixed-legacy recovery or historical
   archive removal. A claim asserts all retained records belong to the verified
   account and allows pending mutations/deletions to sync. Export never uploads.

## Recovery and rollback limits

- The original single store, immutable recovery archive, failed import attempts and
  superseded stores stay retained. This intentionally consumes extra local disk.
  Mixed ownership is not automatically split. Overlapping record IDs reject the
  whole import; both versions remain for export/review.
- Native downgrade after migration is unsafe: the previous app opens the old
  single store and cannot see the new account stores. Prefer a forward fix and
  preserve the entire app container, catalog, WAL and sidecars. Offline access
  still requires a successfully verified launch identity.
- Once GC uses reservations, keep the reservation table even if a release is
  reverted. Do not resume old writers/collectors that ignore the protocol. A
  provider timeout or partial deletion retains a permanent no-adoption reservation;
  re-upload uses a new random key. Coordinate DB restores with S3 history so old
  references/reservation state cannot be restored over irreversible object changes.
- Inventory transactions take one short global advisory lock. Observe contention
  during staged rollout. Object validation/deletion happens outside that lock;
  no throughput claim has been made from these correctness tests.
- Historical local recovery copies are not purged by active-store clearing. Any
  retention/purge policy, recovery of real user data, actual provider cleanup,
  credential/configuration change, or production rollout belongs in one bundled
  parent decision. No such action was executed here.

Implementation details: [native isolation and recovery](NATIVE_ACCOUNT_ISOLATION.md)
and [attachment reservation protocol](ATTACHMENT_GC.md).
