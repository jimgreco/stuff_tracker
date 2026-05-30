# SwiftData Local Persistence & Sync Implementation

## Overview
Your CubbyLog app now has full offline support with automatic cloud sync when authenticated. Users can start using the app immediately without signing in, and all their data is saved locally. When they sign in, everything syncs seamlessly.

## What Was Added

### 1. **Local Data Models** (`LocalModels.swift`)
- `LocalHome` - SwiftData model for homes
- `LocalLocation` - SwiftData model for rooms/containers  
- `LocalItem` - SwiftData model for items
- `SyncOperation` - Queue for tracking pending syncs

Each model includes:
- `needsSync` flag to track changes
- `isDeleted` flag for soft deletes
- Conversion methods to/from API models
- Timestamps for tracking changes

### 2. **LocalDataManager** (`LocalDataManager.swift`)
Singleton class that manages all SwiftData operations:
- CRUD operations for homes, locations, and items
- Local search functionality
- Merge from server data
- Sync queue management
- All operations are performed on the main actor

### 3. **SyncManager** (`SyncManager.swift`)
Handles bidirectional sync between local and server:

**Key Features:**
- `pullFromServer()` - Fetches latest data from API and merges locally
- `pushToServer()` - Uploads local changes to server
- `performFullSync()` - Complete two-way sync
- Tracks sync status, pending changes, and errors
- Automatically retries failed operations (up to 3 times)
- Observable properties for UI updates

**Error Handling:**
- Network failures don't block the UI
- Falls back to local data when offline
- Shows user-friendly error messages
- Queues operations for retry

### 4. **Updated HomeStore** (`HomeStore.swift`)
Now uses local-first architecture:

**Loading Pattern:**
1. Load from local database immediately (instant UI)
2. If authenticated, sync with server in background
3. Update UI with latest server data

**Saving Pattern:**
1. Save to local database immediately (instant feedback)
2. Update UI right away
3. If authenticated, sync to server asynchronously
4. Show "saved locally" message if offline

**Benefits:**
- App works instantly, even offline
- No loading spinners for local operations
- Network errors don't interrupt workflow
- Seamless sync when connection available

### 5. **Enhanced Account View** (`AccountView.swift`)
Updated sync status screen shows:
- Current sync state (syncing/synced/offline)
- Last sync timestamp
- Pending changes count
- Manual "Sync Now" button
- Sync errors if any

### 6. **App Entry Point** (`StuffTrackerApp.swift`)
- Initializes SwiftData container
- Provides SyncManager as environment object
- Performs initial sync on app launch if authenticated

## How It Works

### Offline Mode (Not Signed In)
```
User creates home → Saved to SwiftData → Instant UI update
                  ↓
           needsSync = true
```

### Online Mode (Signed In)
```
User creates home → Saved to SwiftData → Instant UI update
                  ↓                    ↓
           needsSync = true      POST to API
                                       ↓
                                Update local with
                                server ID & clear sync flag
```

### Sign-In Sync Flow
```
User signs in → performFullSync()
              ↓
      pushToServer() - Upload local changes
              ↓
      pullFromServer() - Get shared homes from server
              ↓
      Merge both datasets
```

## Network Error Handling

The app gracefully handles:

1. **No Internet** - Works completely offline
2. **Server Down** - Falls back to local data
3. **Timeout** - Queues for retry
4. **Auth Errors** - Prompts re-authentication
5. **Conflict** - Server data wins (for now)

Error messages follow this pattern:
- "Saved locally. Will sync when online." (Success with pending sync)
- "Using offline data: [error]" (Loading fallback)
- "Delete will sync when online." (Deferred operation)

## Data Sync Strategy

**Conflict Resolution:**
- Last write wins (server takes priority)
- Future: Could implement timestamp-based or manual resolution

**Soft Deletes:**
- Items marked as `isDeleted = true` locally
- Synced to server as DELETE request
- Filtered out of UI queries

**Optimistic Updates:**
- UI updates immediately
- Server sync happens asynchronously
- Errors shown as non-blocking notifications

## Usage Examples

### Creating a Home Offline
```swift
// User not signed in
await homeStore.createHome(name: "My House")
// → Saved to SwiftData with local UUID
// → Shows in UI immediately
// → needsSync = true

// User signs in later
await syncManager.performFullSync()
// → Uploads to server
// → Gets back server ID
// → Updates local record
```

### Network Failure Recovery
```swift
// User makes change while offline
await homeStore.createItem(name: "Keys", locationId: nil)
// → Saved locally ✓
// → Sync attempt fails (no network)
// → Shows "Will sync when online"

// Network comes back
await syncManager.performFullSync()
// → Automatically retries
// → Success! ✓
```

## Testing Checklist

- [ ] Create home while offline
- [ ] Add items/locations while offline  
- [ ] Sign in and verify sync
- [ ] Make changes while online
- [ ] Toggle airplane mode during operations
- [ ] Sign out and verify local data persists
- [ ] Delete items and verify sync
- [ ] Force quit and reopen app

## Future Enhancements

1. **Background Sync** - Sync when app enters foreground
2. **Conflict Resolution UI** - Let user choose which version to keep
3. **Photo Upload Queue** - Handle image uploads separately
4. **Selective Sync** - Only sync specific homes
5. **Compression** - Reduce bandwidth for large syncs
6. **Delta Sync** - Only sync changed fields
7. **Sync Indicator** - Subtle UI showing sync status

## API Requirements

Your backend should support:
- GET /homes - List all homes for user
- GET /homes/:id - Get full home details
- POST /homes - Create new home
- PATCH /homes/:id - Update home
- DELETE /homes/:id - Delete home
- Similar endpoints for locations and items

All responses should return the full object with server-generated IDs.

## Performance Notes

- SwiftData queries are indexed and fast
- Search uses predicates for efficiency
- Batch operations reduce network calls
- Lazy loading for large datasets
- Main actor ensures UI smoothness

---

Your app now provides a seamless offline-first experience with robust sync capabilities! 🎉
