import SwiftUI

// MARK: - Breadcrumb preference key

struct BreadcrumbAnchor: Equatable {
    let path: [String] // e.g. ["Home Name", "Floor Name", "Room Name"]
    let minY: CGFloat
}

struct BreadcrumbPreferenceKey: PreferenceKey {
    static var defaultValue: [BreadcrumbAnchor] = []
    static func reduce(value: inout [BreadcrumbAnchor], nextValue: () -> [BreadcrumbAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore
    @StateObject private var homeStore = HomeStore()
    @State private var searchText = ""
    @State private var isAddingHome = false
    @State private var newHomeName = ""
    @State private var showAccountSheet = false
    @State private var breadcrumbPath: [String] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Search bar ───────────────────────────────────────────────
                SearchBar(text: $searchText)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // ── Breadcrumb bar ───────────────────────────────────────────
                if breadcrumbPath.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(Array(breadcrumbPath.enumerated()), id: \.offset) { index, segment in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(segment)
                                .font(.caption)
                                .foregroundStyle(index == breadcrumbPath.count - 1 ? .primary : .secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                }

                if homeStore.isLoading && homeStore.homeDetails.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let filtered = filteredHomes
                    if !searchText.isEmpty && filtered.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No results")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                if searchText.isEmpty {
                                    HomeDropZone(insertionIndex: 0, homeStore: homeStore)
                                }
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, home in
                                    HomeBoxView(home: home, homeStore: homeStore)
                                    if searchText.isEmpty {
                                        HomeDropZone(insertionIndex: index + 1, homeStore: homeStore)
                                    }
                                }

                                if searchText.isEmpty {
                                    if isAddingHome {
                                        InlineAddField(placeholder: "Home name", text: $newHomeName) {
                                            let name = newHomeName
                                            newHomeName = ""
                                            isAddingHome = false
                                            Task { await homeStore.createHome(name: name) }
                                        } onCancel: {
                                            newHomeName = ""
                                            isAddingHome = false
                                        }
                                    }

                                    HStack {
                                        Button {
                                            isAddingHome = true
                                        } label: {
                                            Label("Add home", systemImage: "plus")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.bottom, 8)

                                    TrashBinView(homeStore: homeStore)
                                }
                            }
                            .padding()
                        }
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(BreadcrumbPreferenceKey.self) { anchors in
                            // Find the topmost box whose top is at or above the scroll top
                            let threshold: CGFloat = 80
                            let candidate = anchors
                                .filter { $0.minY <= threshold }
                                .max(by: { $0.minY < $1.minY })
                            breadcrumbPath = candidate?.path ?? []
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                DragTrashZone(homeStore: homeStore)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Stuff Tracker")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAccountSheet = true
                    } label: {
                        if let avatarUrl = authStore.currentUser?.avatarUrl,
                           let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: authStore.isAuthenticated ? "person.circle.fill" : "person.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAccountSheet) {
                AccountView(homeStore: homeStore)
                    .environmentObject(authStore)
                    .environmentObject(SyncManager.shared)
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { homeStore.errorMessage != nil },
                set: { if !$0 { homeStore.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(homeStore.errorMessage ?? "")
            }
            .task { await homeStore.loadHomes() }
        }
    }

    private var filteredHomes: [HomeDetail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return homeStore.homeDetails }

        return homeStore.homeDetails.compactMap { home in
            let q = query.lowercased()
            let homeMatches = home.name.localizedCaseInsensitiveContains(q)

            // Find locations whose name matches
            let directMatchIds = Set(
                home.locations
                    .filter { $0.name.localizedCaseInsensitiveContains(q) }
                    .map { $0.id }
            )

            // Expand to include all descendants of matching locations
            var matchingLocationIds = directMatchIds
            var toExpand = directMatchIds
            while !toExpand.isEmpty {
                let children = Set(
                    home.locations
                        .filter { loc in loc.parentId.map { toExpand.contains($0) } ?? false }
                        .map { $0.id }
                )
                let newChildren = children.subtracting(matchingLocationIds)
                matchingLocationIds.formUnion(newChildren)
                toExpand = newChildren
            }

            // Find items that match by name/notes/tags
            let matchingItems = home.items.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                ($0.notes ?? "").localizedCaseInsensitiveContains(q) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }

            if !homeMatches && directMatchIds.isEmpty && matchingItems.isEmpty {
                return nil
            }

            // If home name matches, show everything
            if homeMatches {
                return home
            }

            // Collect all location IDs we need to show (matching + ancestors)
            var allNeeded = matchingLocationIds
            // Add locations needed for matching items
            allNeeded.formUnion(matchingItems.compactMap { $0.locationId })
            // Walk up to include ancestor locations
            var toResolve = allNeeded
            while !toResolve.isEmpty {
                let parents = Set(toResolve.compactMap { id in
                    home.locations.first(where: { $0.id == id })?.parentId
                })
                let newParents = parents.subtracting(allNeeded)
                allNeeded.formUnion(newParents)
                toResolve = newParents
            }

            let filteredLocations = home.locations.filter { allNeeded.contains($0.id) }
            // Include items that match OR are inside a matching location (including descendants)
            let filteredItems = home.items.filter { item in
                if matchingItems.contains(where: { $0.id == item.id }) { return true }
                if let locId = item.locationId { return matchingLocationIds.contains(locId) }
                return false
            }

            return HomeDetail(
                id: home.id,
                name: home.name,
                ownerId: home.ownerId,
                role: home.role,
                icon: home.icon,
                locations: filteredLocations,
                items: filteredItems
            )
        }
    }
}

// MARK: - Empty state

struct EmptyHomePrompt: View {
    @EnvironmentObject var authStore: AuthStore
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("Welcome to Stuff Tracker")
                .font(.title.bold())
            
            Text("Track your stuff across rooms and containers")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            Button("Create Your First Home", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            
            if !authStore.isAuthenticated {
                VStack(spacing: 8) {
                    Text("Working offline")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Sign in from the menu to sync across devices")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Drag trash zone

struct DragTrashZone: View {
    @ObservedObject var homeStore: HomeStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 4) {
            if isTargeted {
                Image(systemName: "trash.fill")
                    .font(.title2)
                Text("Drop to Delete")
                    .font(.caption.bold())
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: isTargeted ? .infinity : nil)
        .frame(height: isTargeted ? 70 : 0)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: isTargeted ? 16 : 0))
        .padding(.horizontal, isTargeted ? 16 : 0)
        .padding(.bottom, isTargeted ? 8 : 0)
        .opacity(isTargeted ? 1 : 0)
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            for home in homeStore.homeDetails {
                if home.items.contains(where: { $0.id == dragged.id }) {
                    Task { await homeStore.deleteItem(homeId: home.id, itemId: dragged.id) }
                    return true
                }
            }
            return false
        } isTargeted: {
            withAnimation(.easeInOut(duration: 0.2)) { isTargeted = $0 }
        }
    }
}

