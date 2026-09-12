# Stuff Tracker — Codex Guide

## Efficient Start

- Use supplied context once. Before code edits, inspect `git status --short --branch`,
  `git diff --stat`, and `git diff --cached --stat`, then relevant hunks. Preserve
  unrelated work and stage only the requested scope when committing.
- Start with the paths below and narrow `rg` searches. Batch independent reads;
  reuse installed dependencies and build caches unless a change invalidates them.
- Make routine reversible decisions and complete the authorized outcome. Avoid
  speculative cleanup, repeated permission questions, and unrelated work.
- Run meaningful checks for the changed surface once after edits settle, including
  the repository's required gates. Repeat only when new evidence invalidates them.
  Documentation-only edits need diff, link/path, and whitespace review.
- For requested releases, follow the current workflow and verify the final pushed
  SHA and applicable live results. Keep build, deployment, TestFlight upload, and
  physical-device evidence distinct. Report the outcome and actual verification.

## Local Pointers

- API/domain code, migrations, and tests: `backend/src/`, `backend/scripts/`,
  `backend/test/`; browser UI: `web/` and `web/README.md`.
- Native app and tests: `ios/StuffTracker/`, `ios/StuffTrackerTests/`;
  Xcode project: `ios/StuffTracker.xcodeproj`.
- Backend checks: `npm --prefix backend test` and
  `npm --prefix backend run build`; native edits use the relevant Xcode targets,
  and visible changes need inspection on the affected web/native screen.
- Keep API request/response changes aligned with both clients and preserve
  account/home authorization and the existing subscription behavior.
- Operations and release checks: `docs/OPERATIONS.md`,
  `.github/workflows/deploy.yml`, `.github/workflows/testflight.yml`, and
  `backend/scripts/smoke-deploy.cjs`. Inspect current scripts before invoking
  operational checks, migrations, cleanup, or production writes.
