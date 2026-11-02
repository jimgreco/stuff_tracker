# CubbyLog — coding handoff

Snapshot: **2026-11-02 UTC**. This is a takeover map, not release authorization. Recheck Git status, the requested scope and current runtime before acting. Existing AGENTS.md and linked contract/runbooks remain applicable. Older dated status notes are evidence from their stated date, not current permissions.

## Purpose and architecture

CubbyLog inventories household belongings, locations, photos, documents and activity.

TypeScript Node backend/PostgreSQL with S3 attachments; browser client and native SwiftUI StuffTracker app. Home membership/roles and account-owned stores are enforced server-side and in native persistence.

## Locations and current work

- Usual local workspace: `/Users/jgreco/code/stuff`.
- Source inspected for this handoff: `/Users/jgreco/Documents/Codex/2026-10-25/task/integration-2026-10-30/cubby`.
- Existing repository: [jimgreco/stuff_tracker](https://github.com/jimgreco/stuff_tracker); default branch `main`, verified source head `6e54e75a5b9fe1f7769f14530ad77f8be50f8bd1`.
- Documentation branch: `docs/agent-handoff-2026-11-02`, based on that head; application code was not changed.
- Primary checkout is at `466f8163ab16678e060496d1cc58f2a870ca9553` on `main` and differs from remote main. Do not reset it or assume it contains released features; use the inspected source or a new isolated checkout.

## Code and guide map

- [backend/src](../backend/src)
- [backend/scripts](../backend/scripts)
- [backend/test](../backend/test)
- [web](../web)
- [ios/StuffTracker](../ios/StuffTracker)
- [ios/StuffTrackerTests](../ios/StuffTrackerTests)

Read the relevant existing guide before changing its contract:

- [docs/OPERATIONS.md](OPERATIONS.md)
- [docs/NATIVE_ACCOUNT_ISOLATION.md](NATIVE_ACCOUNT_ISOLATION.md)
- [docs/ATTACHMENT_GC.md](ATTACHMENT_GC.md)
- [docs/HARDENING_BACKLOG.md](HARDENING_BACKLOG.md)
- [docs/native-testflight-existing-assets.md](native-testflight-existing-assets.md)

## Local setup and dependencies

Commands below are source-verified entry points, **not commands executed during this documentation pass**. Use disposable local data. Read the command comments and linked setup guide before running migrations, creating fixtures or starting listeners. Reuse prepared environments where suitable.

- `npm --prefix backend ci`
- `cp backend/.env.example backend/.env  # isolated local database/storage`
- `npm --prefix backend run db:migrate  # separate local migration credentials`
- `npm --prefix backend run dev  # predev also invokes migration; inspect configuration first`

Configuration names/locations only; never copy secret values into source, terminal output or handoff documents:

- `DATABASE_URL`
- `MIGRATION_DATABASE_URL`
- `DB_EXPECTED_APP_ROLE`
- `JWT_SECRET`
- `GOOGLE_CLIENT_ID`
- `APPLE_BUNDLE_ID`
- `APP_BASE_URL`
- `S3_BUCKET`
- `S3_REGION`
- `STUFF_ADMIN_EMAILS`

Use existing lockfiles/manifests; do not upgrade dependencies to perform a handoff. For native work, select an actually installed Xcode SDK/simulator from the checked-in project configuration.

## Tests and verification

- `npm --prefix backend test`
- `npm --prefix backend run build`
- `Use web/README.md for browser fixtures and native Xcode tests for iOS changes. Operations smoke/cleanup tools may write and are separate from local tests.`

Documentation-only changes require path/link, accuracy, diff and secret-exclusion review; do not run heavyweight builds or production smoke mutations for prose changes. Application tests were not rerun in this pass. Past test/release evidence below retains its original date. UI changes still require actual rendered inspection, and synthetic tests do not prove real provider/device acceptance.

## Decisions and constraints

- Photo/document filters combine with search and ancestry. Select-all uses final matching items only within the current home; preserve role checks and destructive confirmation.
- Name ordering and matching bulk selection already ship. Keep signed/private attachment access, garbage-collection retention and durable delete receipts.
- The production household entitlement/editor repair was completed separately. Do not alter account state or sharing as a coding shortcut.

## Release state and workflow effects

- Web/API: deployed and verified **2026-11-02**, source `c7c6ba651ccd5e879bff2d19430715300edbda3d`. Exact revision/readiness and scoped activation were recorded; this documentation pass did not redeploy.
- Native: version **1.3**, build **240**, source `6e54e75a5b9fe1f7769f14530ad77f8be50f8bd1`. **Available in TestFlight**, processing/audience verified November 2 for exactly **2 existing internal testers**; external/public distribution excluded. [Verification evidence](https://github.com/jimgreco/stuff_tracker/actions/runs/41461193539). No public App Store release was performed.
- Main push runs backend verification and can run native TestFlight. Server activation is separately gated. Preserve exact audience identities and existing profiles.

Recent exact-source GitHub results observed November 2 (workflow purpose matters):

- [Deploy to EC2 run 41461193575](https://github.com/jimgreco/stuff_tracker/actions/runs/41461193575): `completed` / `success`.
- [TestFlight run 41461193539](https://github.com/jimgreco/stuff_tracker/actions/runs/41461193539): `completed` / `success`.

The handoff is published on a documentation feature branch, not main. Current checked-in GitHub push triggers are main-only (or absent). Blog hosting branch settings were separately checked. No native release, image publication or server deployment is intended from this documentation push.

## Known gaps and next safe work

- No native release blocker remains; approved exact-two identity guard passed for240. Dependency audit repair c7c6ba6 is already in the released server.
- App Review/device evidence, attachment recovery and destructive cleanup are distinct tasks; consult existing operations/backlog notes before asserting completion.

Before the next task, verify source HEAD, dirty/staged work and the selected subsystem; read only the relevant guide. Check whether a listed idea is already implemented in another branch before rebuilding it. Preserve unrelated work and paused experiments. Release/permission/data changes require the applicable current authorization.
