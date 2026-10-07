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
- `8f816a5893ae6cbfa9032a2106341a3c62f8bf70` — durable original-ID create receipts,
  migration 014, cancellation/cascade retirement, native capability gating,
  preserved/exportable unknown legacy outcomes and replay regressions.
- `fa63f0916507321642b7d15c79493d04ae922420` /
  `2bfec6006fab04b8b8b4b0cc17d157dbefb684fc` — coordinated monitoring integration from source commits
  `e4864598245ff505b73036390c516782d39078de` and
  `0d00446c39afa43b3a1fea57a51111fef16b4c1b`. Health checks fail visibly on missing
  configuration or probe failure; operations explicitly use existing GitHub
  failure email and make zero webhook requests.
- `485e0f7d96d05e42bb8266eebec39a8d3e4d106d` — preserves persisted legacy
  home/location/item tombstones using a nonreserved SwiftData property mapped to
  the old attribute; tests the exact shipped model declarations and disk reopening.

Independent review passed the replay repair and combined implementation at
`2bfec60`; narrow independent review also passed the native tombstone correction
at `485e0f7`, verified the frozen model declarations and checked the 73-test/build
evidence. The
subsequent handoff commit changes documentation and one fixture whitespace line.
No dependency update, real cleanup, provider send, credential change or real-user
recovery is included. No TestFlight workflow change was made: **a normal
push/merge to main automatically starts native testing, archive and upload**.

## Verification on the combined implementation

| Check | Result | Local evidence (excluded from Git) |
| --- | --- | --- |
| Exact-lockfile install | `npm ci --ignore-scripts` in isolated checkout succeeded | `evidence/npm-ci.log` |
| Backend TypeScript | Build succeeded | `evidence/aggregate-backend-build.log` |
| Backend unit / synthetic / PostgreSQL suite | 97 passed, including all 7 gated integration tests | `evidence/aggregate-backend-tests.log` |
| Operations and health fixtures | 11 passed; zero provider calls | `evidence/aggregate-operations.log` |
| Native release guards | 22 JS and 16 Python tests passed | `evidence/aggregate-release-guards.log`, `aggregate-release-python.log` |
| Production lockfile audit | 0 known advisories | `evidence/production-audit.json` |
| All-dependency audit | 1 existing low development-only esbuild advisory; dependency lane follow-up | `evidence/all-dependency-audit.json` |
| Native XCTest | 73 passed, including the shipped-schema fixture and all replay regressions | `evidence/native-final-verified.log`, `.xcresult` |
| Native Release simulator | Build succeeded on final native implementation `485e0f7` | `evidence/native-final-release.log` |
| Recovery UI | Synthetic account rendered and visually inspected; claim, export, skip and cancel visible | `evidence/native-final-screens/` |
| Whitespace / cleanup script syntax | Passed | `git diff --check`, `node --check` |

PostgreSQL tests use only `127.0.0.1:54873/cubby_gc_20261007_test`, a disposable
Postgres 16 cluster. The integration reset guard rejects nonlocal/non-`_test`
databases. All S3 responses are synthetic. Tests cover reference adoption racing
GC in both orders, permanent reservations across partial/provider failure,
account-scoped create receipts, request-hash mismatch, rollback with no receipt,
concurrent retries, deletion overtaking creation and parent cascades. Native tests
cover lost POST replies and A→B fences for both items and locations, original-ID
retry, lost DELETE replies, old-server capability failure and export of unresolved
legacy rows. The legacy model fixture is frozen from remote main `5854a24`. It
exposed the old `isDeleted` getter collision with SwiftData lifecycle state: persisted predicate
results showed tombstones while direct getters returned false. The final rename
uses `originalName` and verifies all three persisted tombstone types survive,
remain hidden from active inventory, and retain pending state in the archive.

The replay simulator is `CubbyReplay20261007`, iPhone 17 Pro / iOS 26.2,
`F3E14CC7-C7C3-4167-887B-08516AA1E76F`; Xcode uses `-jobs 2` and no parallel testing.
No physical-device archive, Apple signing/upload, actual S3/IAM validation or
production acceptance is implied. The simulator and test database are owned by
this lane and are stopped/removed after verification.

The development-only advisory is [GHSA-g7r4-m6w7-qqqr](https://github.com/advisories/GHSA-g7r4-m6w7-qqqr),
affecting the esbuild development server on Windows (`0.27.3–0.28.0`). It is not in
the production dependency tree; route that update through the dependency lane.

## Coordinated release sequence

1. Parent approves the final exact SHA and shared-host slot. Use the previously
   guarded local release path selected by the coordinator, **not `deploy.yml`**.
   Retain the current image and a verified database backup. Stop old collectors
   and drain old API instances so no writer can ignore reservations or receipts.
   Do not run cleanup concurrently with the switch.
2. Publish/review the combined commits and verify required CI at the exact SHA.
   Coordinate main publication with native upload authorization because its
   existing automatic TestFlight behavior is preserved. Do not use a monitoring-
   only `[skip ci]` strategy for this native release.
3. Apply **both migrations 013 and 014**, in that order, with `stuff_migrator` through
   the existing guarded migration path. Migration 013 creates the media reservation
   table; 014 creates durable create receipts and deletion-retirement triggers.
   Neither backfills inventory nor deletes/reserves existing S3 objects. Verify
   `schema_migrations` records for both files before starting the new API.
4. Verify runtime access with the existing `stuff_app` identity, without broadening
   its role. Its new minimum table privileges are **SELECT, INSERT, UPDATE** on
   `public.attachment_gc_tombstones` and `public.client_create_receipts`, plus
   existing schema USAGE and inventory privileges. SELECT validates reservations
   and receipts; INSERT commits reservations/receipts; UPDATE records GC completion
   and cancellation/deletion (including the normal invoker trigger). No direct
   DELETE on either ledger, new sequence grant, schema CREATE, table ownership,
   superuser or new AWS permission is required. Verify actual default privileges
   of the migration creator; do not assume the existing hardening check validates
   these new grants. If missing, bundle only these exact grants for parent approval.
5. Start the matching new API and collector image after the old processes are
   drained. Verify authenticated `/account/sync-capabilities` returns
   `client_create_receipts: 1`, runtime access, and the established guarded smoke/
   check-only acceptance. Production smoke creates/deletes synthetic account rows,
   so it must be included in the coordinator's authorized scope. An S3 dry-run is
   read-only; an actual cleanup pass remains a separate deletion decision.
6. Set the sole required monitoring repository variable
   `PRODUCTION_BASE_URL=https://cubbylog.com` in the parent's configuration bundle.
   Retain explicit GitHub-email mode and current email settings. No new webhook
   destination/secret, induced failure or test email is needed. A successful policy
   step does not prove receipt; missing-run and backend-runtime alerts are outside
   this mode. Use a scheduled or separately authorized health run to verify probes.
7. Release the native SHA only after all API instances support receipt protocol 1.
   Mixed old/new API pools and rolling back the API beneath the native capability
   floor are unsupported. Accept on a disposable physical device/account before
   broad rollout: known-owner shipped schema, unknown/mixed claims, export/cancel/
   skip/recover, A/B/A pending writes/deletes, lost replies, Data Protection lock/
   unlock, low disk and realistic inventory size.
8. Resolve real older unknown outcomes only after owner review. A claim confirms
   ownership, not a lost server-ID mapping. Missing legacy IDs remain pending and
   exportable; they are never silently POSTed or discarded. Historical source/
   archive removal and actual S3 cleanup are separately scoped decisions.

New-table permission verification is read-only and must connect as the runtime
role. For example, the coordinator can evaluate `has_table_privilege(current_user,
'public.client_create_receipts', 'SELECT')` (and separately INSERT/UPDATE), then
repeat for `public.attachment_gc_tombstones`. Only after checking the exact target
and explicit approval should any missing grants be applied by the migration role.

## Recovery and rollback limits

- The original single store, immutable recovery archive, failed import attempts and
  superseded stores stay retained. This intentionally consumes extra local disk.
  Mixed ownership is not automatically split. Overlapping record IDs reject the
  whole import; both versions remain for export/review.
- Native downgrade after migration is unsafe: the previous app opens the old
  single store and cannot see the new account stores. Prefer a forward fix and
  preserve the entire app container, catalog, WAL and sidecars. Offline access
  still requires a successfully verified launch identity.
- The compatible backend rollback floor is an image containing **both** the GC
  reservation protocol and migration-014 create/delete receipt protocol (the
  implementation at `8f816a5` or a tested equivalent). `5854a24` and the intermediate
  GC-only commits are not safe rollback images after native receipt writes begin.
  Keep both ledgers and the retirement triggers; never down-migrate, truncate or
  prune them. Prefer a forward fix. If no compatible rollback image exists, stop
  mutations/cleanup instead of restarting incompatible writers.
- Once GC uses reservations, retain its ledger after success or failure. Do not
  resume old writers/collectors that ignore the protocol. A provider timeout or partial deletion retains a permanent no-adoption reservation;
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
