# Native per-account stores and retained-inventory recovery

The 2026-10-03 audit shipped an owner-bound single-store containment guard. This
change replaces the single-store restriction with independent SwiftData stores
keyed by the stable server user ID. Email and shared-home ownership never establish
local inventory ownership. The shipped `default.store` is not renamed, repurposed,
cleared, or automatically deleted by migration.

## Storage and publication

`Application Support/CubbyAccounts/catalog.json` maps verified account IDs to
opaque UUID directories containing `inventory.store`. The same atomic catalog
records which account claimed the legacy store. An unknown/corrupt catalog, failed
read, or missing published account database fails closed instead of replacing data
with an empty store. Sign-out detaches the active context; A → B → A opens each
account's independent inventory, pending changes and tombstones.

For a migration, the app takes a versioned `InventoryArchive` snapshot of every
LocalHome, LocalLocation, LocalItem and SyncOperation. It preserves exact model
attributes, raw property/document payloads (including malformed legacy payloads),
relationship identities, sort order, timestamps, deletion flags, pending flags,
queue payloads, failure counts and last errors. Unlinked rows are retained.

A `legacy-recovery.json` archive is written without replacing an existing archive.
If the source later differs from its saved archive, recovery stops for review.
The snapshot is imported into a fresh UUID store. The context is saved, then a
separate context reads and compares all records. Only after equality succeeds does
one atomic catalog replacement publish the store and claim. A crash before
publication leaves the original and unpublished attempt intact; retry uses a new
store. A crash after publication reopens that store without importing twice.
Incomplete attempt directories and superseded account stores remain retained for
recovery; no automatic pruning is part of this release.

The archive/catalog and media-cache files use complete file protection. SwiftData
uses the platform's persistent-store protection. No CloudKit database is enabled.
These are local stores protected by the device/app sandbox, not separately
password-encrypted vaults. Loss of disk capacity or filesystem errors abort
migration rather than dropping rows. Available space must cover the retained
source, archive, and new store; practical device-size acceptance remains required.

## Ownership and recovery

A legacy store bound by the shipped owner guard migrates only for that exact
verified user. Another account can use a separate empty store without seeing or
claiming it. Unattributed inventory requires an explicit claim that **all** records
belong to the verified account. No home list, home owner, email, or failure response
is used to infer ownership.

The recovery screen offers claim, private JSON export, continue without importing,
and cancel. Claim permits retained pending writes and deletions to sync; its text
states this consequence. Export does not claim or upload inventory. Continue opens
a separate account store and retains recovery under Account → Review older
inventory. Cancel invalidates the pending confirmation and keeps data intact.

When recovery is requested after an account has been used, disjoint records are
copied into a new combined store. Any overlapping record identity rejects the
whole merge and retains both sources. Export enables review of mixed-account or
conflicting legacy data; there is deliberately no automatic split, overwrite or
replay of ambiguous rows. The JSON archive references hosted media; it is not a
self-contained download of every attachment.

## Asynchronous boundaries and caches

An account transition invalidates API session generations. Sync also carries a
local store generation. Late reads/deletes/refreshes cannot commit into another
account, finish its sync status, or block its new sync. Item attachment editing
checks the captured session/store before committing an upload result. Remote
photo caches use hashed account subdirectories and never read the old unscoped
cache; late downloads cannot publish/cache after a switch. API and photo network
sessions use ephemeral URL caches. Subscription state clears on store transitions
and rechecks the identity after provider/network awaits.

Already-sent server mutations retain their original credentials and cannot be
recalled on sign-out. Pending local work stays for reconciliation. The existing
SyncOperation payloads are preserved, not blindly replayed by a new interpreter.
Unsaved editor state was never a durable queue and is not converted into one here.
Cached inventory remains locked when launch cannot verify the stored server
identity; offline login is not expanded by this migration.

## Rollout and remaining acceptance

Ship through TestFlight to a disposable account/device first. Exercise A/B/A with
pending additions/deletions, claim/cancel/export/skip, unknown or mixed legacy
ownership, expired/offline sign-in, large inventories, disk-full interruption,
and physical-device Data Protection lock/unlock. No real local inventory has been
migrated, recovered, exported or deleted in development. Real-user recovery and
mixed-store ownership decisions require the owner's review.

Do not downgrade a migrated installation to the owner-bound single-store build:
it would reopen the old retained inventory, not the new account stores. Use a
forward fix. Preserve the app container and catalog for recovery; do not uninstall
or copy individual SQLite files without their WAL/sidecars. Recovery sources and
unpublished/superseded stores are deliberately retained, including after normal
active-store clearing; removal of historical local copies is a separately scoped
recovery/retention decision, not automatic cleanup in this release.

Verified in synthetic XCTest fixtures: on-disk migration of every field and orphan
row; interruptions after archive/import/publication; account switching; queue and
tombstone retention; mid-sync switches; late responses/deletes/refresh/media/plan;
legacy claim/export/skip/cancel and overlap rejection. The recovery screen was
rendered and inspected. See the dated release plan for exact commits and commands.
