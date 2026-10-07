# Attachment adoption and garbage collection

Migration `013_attachment_gc_reservations` adds durable object-key reservations.
All inventory transactions use the same Postgres transaction advisory lock
`(724193, 1)` under READ COMMITTED. Item POST/PATCH checks incoming photo/document
keys against reservations inside that transaction, before writing references.
Location/item moves run through the same transaction helper. The canonical parser
in `scripts/lib/attachment-keys.cjs` is shared by reads, adoption, and cleanup.

Cleanup lists candidates as before, retaining the scheduled sweep's positive age
grace and missing-age protection. Each deletion batch then:

1. Starts a READ COMMITTED transaction and acquires the inventory lock.
2. Reads current references, and current home IDs for deleted-home cleanup.
3. Reserves only unreferenced eligible keys and commits.
4. Releases the connection, then asks S3 to delete at most 1,000 keys.
5. Records successful deletion timestamps. Reservations are never removed.

A writer that acquires the lock first commits a reference the collector observes.
A collector that acquires it first commits a reservation that makes subsequent
adoption return HTTP 409, `attachment_retired`. The user can upload the file again
to obtain a fresh random key. Byte/type/home-authorization validation still runs.
S3 calls do not hold the database lock. Every current attachment reference writer
was inspected: item POST/PATCH and item/location move transactions participate.
New writers or bulk import/restore tools must participate in this protocol too.
Direct SQL writes that bypass it are unsupported during collection.

This is a durable reservation protocol, not a distributed transaction with S3.
A timeout or partial delete leaves reservations in place because the provider's
outcome might be unknown. Subsequent cleanup safely retries. A failed reservation
commit sends no S3 deletion. A failed success-timestamp update may leave a missing
`deleted_at`; that is conservative and does not reopen adoption. Reserved keys must
never be reused, even if an old presigned PUT recreates their object afterward.

The lock deliberately serializes short inventory transactions across accounts.
Network byte validation precedes the transaction; S3 deletion follows it. Observe
latency before broad rollout. Per-key/indexed references could reduce contention
later; this release favors a simple verifiable protocol for the current app.

## Deployment and rollback

Coordinate with the monitoring owner before deployment. Quiesce old cleanup jobs,
wait for in-flight deletes, deploy migration 013 and the new API/cleanup image,
and drain old API processes before permitting cleanup. Do not mix old collectors
with the new API or new collectors with old writers. The migration is additive;
existing attachments need no backfill and no objects are deleted by migration.
Verify the migration role's existing default privileges grant runtime SELECT,
INSERT, UPDATE on `attachment_gc_tombstones`. No new S3 capability is needed.

Keep the table and reservations across rollback. Once collection uses this
protocol, prefer a forward fix retaining its adoption check. Reverting to an old
writer or dropping reservations can reopen the race. A database restore must be
coordinated with S3: never restore pre-reservation references to objects that may
already have been deleted, or erase reservations while a delete may be in flight.

No production cleanup was performed in this change. Real S3/versioning/IAM
acceptance and any real-user-data deletion remain separately authorized actions.
