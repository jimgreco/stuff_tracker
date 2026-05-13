# Test Coverage

## Current Suites

### iOS: StuffTrackerTests

Run with:

```bash
xcodebuild -project ios/StuffTracker.xcodeproj \
  -scheme StuffTracker \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

Coverage:

- `SyncUploadPlannerTests`
  - Orders pending locations parent-before-child.
  - Allows pending children when parents are already clean.
  - Fails fast for missing parent locations.
  - Fails fast for cyclic parent relationships.
  - Protects pending/deleted local records from server merge overwrites.

- `APIEncodingTests`
  - Encodes item `location_id: null` when an item is moved to the home root.
  - Encodes location `parent_id: null` when a location is moved to the top level.
  - Encodes new top-level `floor` locations with an explicit null parent.
  - Omits removed legacy item fields when absent.

### Backend: Node Test Runner

Run with:

```bash
cd backend
npm test
```

Coverage:

- Location sync validation accepts `floor`, `room`, and `container`.
- Unknown location types are rejected.
- Item sync validation accepts explicit root-level `location_id: null`.
- The migration helper recreates `locations_type_check` with `floor` support.
- Fresh schema SQL includes the same location type constraint.

## Still Worth Adding

- Integration tests against a disposable Postgres database.
- End-to-end sync tests that run the iOS sync client against the local backend.
- SwiftData-backed tests for `LocalDataManager` once its singleton can accept an in-memory store.
