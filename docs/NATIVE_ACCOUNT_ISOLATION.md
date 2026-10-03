# Native account isolation guard (2026-10-03)

The legacy SwiftData inventory had no account owner. Signing out removed tokens
but retained homes, items, and pending changes. A subsequent sign-in could expose
that inventory and upload it to another account. A failed home-list request was
also treated as an empty account. The isolated audit change contains this behavior
without deleting or migrating existing data.

The retained store now binds to the verified server user ID, not an email or home
owner. A different account cannot open a nonempty store. Counts include deleted
records and legacy SyncOperation entries; a failed store read cannot authorize
reassignment. An unattributed legacy/local store stays locked until its user
explicitly confirms that all its inventory belongs to the newly verified account.
Cancelling leaves the data and pending work intact. A genuinely empty store can be
bound to another verified account.

Sync requires the verified identity to match that binding. A session generation
covers requests, refreshes, retries, and an entire sync. Signing out or signing in
invalidates earlier work; responses are checked again on MainActor before model
updates. A late refresh cannot overwrite or clear newer credentials. Network
refresh failures retain credentials for recovery. Screen state is recreated when
the active identity changes.

Initial/full sync now fetches the home list before uploading; failure leaves
pending data in place. Only a confirmed 404 permits recreation, not 403 or network
errors. Deletion tombstones remain until success or 404. Replacing local inventory
fetches all home details successfully before clearing the local store.

## Verification

The final app sources passed **57 XCTest cases**, including 11 account-boundary
cases using in-memory SwiftData, isolated preferences, synthetic Keychain values,
and URLProtocol responses. Tests cover sign-out/reopen, blocked account switch,
legacy claim/cancel, queue/tombstone isolation, failed home list, failed replacement,
failed deletion followed by 404, forbidden-home recreation, late home responses,
late refresh after a new sign-in, failed stored-identity lookup, and the claim UI.
The claim UI capture was subsequently rerun alone after connecting its test window
to a scene; its rendered screen was inspected, including both claim/cancel buttons.

Commands used an existing public package cache and new disposable simulators:

```bash
xcodebuild -project ios/StuffTracker.xcodeproj -scheme StuffTracker \
  -destination 'platform=iOS Simulator,id=<disposable-audit-simulator>' \
  -derivedDataPath <audit-temporary-derived-data> \
  -clonedSourcePackagesDirPath <audit-temporary-derived-data>/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -only-testing:StuffTrackerTests -parallel-testing-enabled NO \
  -resultBundlePath audit-evidence/native-verified.xcresult test
# Final screenshot-only check:
# same command, using -only-testing:StuffTrackerTests/NativeAccountBoundaryTests/testLegacyInventoryClaimScreen
# and audit-evidence/native-screen-verified.xcresult
```

The Release simulator configuration also compiled successfully with the same
cache and `-configuration Release -destination generic/platform=iOS\ Simulator
build`, verifying the release account-screen reset path. No device archive or
deployment was made.

All audit simulators were removed. Local evidence is excluded from Git. No real account
inventory, media, credentials, or installed user app was migrated or modified.

## Contained limitations and next migration

This is a single retained-store guard, not seamless multi-account storage. A
nonempty store must be reopened with its bound account. Legacy ownership cannot be
recovered automatically; the explicit claim is the user's assertion, and existing
mixed-account legacy data needs a separate review/export workflow. A stored session
that cannot be verified at launch now shows the reconnect screen rather than its
cached inventory; the cache remains intact. This deliberately limits offline
access during an unresolved identity check.

A future migration should create a separate SwiftData store and attachment cache
for each stable user ID, preserve an immutable copy of the legacy store, provide an
explicit claim/export path, and switch only after the new store and pending queue
are durably verified. Test crash recovery at every step. Never infer ownership
from a shared home's owner ID. Do not delete the legacy store until migration and
user recovery have been verified. This audit did not execute such a migration.

Already-sent network mutations cannot be recalled at sign-out. They retain their
original credentials; the guards prevent late results from changing local state or
continuing the old sequence under a new account. The SwiftData save helper's
existing disk-error reporting and cross-process persistence are not redesigned by
this patch. Physical-device and comprehensive accessibility testing remain open.
