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
    @StateObject private var collapseStore = HierarchyCollapseStore()
    @State private var searchText = ""
    @State private var showFlaggedOnly = false
    @State private var isAddingHome = false
    @State private var newHomeName = ""
    @State private var showAccountSheet = false
    @State private var breadcrumbPath: [String] = []
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        if authStore.isRestoringSession {
            StartupPhotoLoadingView(message: "Checking account...")
        } else if authStore.requiresSignIn {
            LoginView(mode: .reconnect)
                .environmentObject(authStore)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if homeStore.isLoading && homeStore.homeDetails.isEmpty {
                    StartupPhotoLoadingView(message: "Loading your stuff...")
                } else {
                    let filtered = filteredHomes
                    if isFiltering && filtered.isEmpty {
                        ContentUnavailableView(
                            emptyFilterTitle,
                            systemImage: showFlaggedOnly ? "flag" : "magnifyingglass",
                            description: Text(emptyFilterDescription)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                if !isFiltering {
                                    HomeDropZone(insertionIndex: 0, homeStore: homeStore)
                                }
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, home in
                                    HomeBoxView(
                                        home: home,
                                        homeStore: homeStore,
                                        collapseStore: collapseStore,
                                        isSearchActive: isFiltering
                                    )
                                    if !isFiltering {
                                        HomeDropZone(insertionIndex: index + 1, homeStore: homeStore)
                                    }
                                }

                                if !isFiltering {
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
                            updateBreadcrumbPath(from: anchors)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .top) {
                BreadcrumbBar(path: breadcrumbPath)
            }
            .overlay {
                if isSearchFocused {
                    SearchDismissTapShield {
                        dismissSearchInput()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomSearchControls(
                    searchText: $searchText,
                    showFlaggedOnly: $showFlaggedOnly,
                    isSearchFocused: $isSearchFocused
                )
            }
            .overlay(alignment: .bottom) {
                DragTrashZone(homeStore: homeStore)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 76)
            }
            .navigationTitle("Stuff Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isSearchFocused {
                            dismissSearchInput()
                        } else {
                            showAccountSheet = true
                        }
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
            .onReceive(homeStore.$homeDetails) { homes in
                collapseStore.prune(validNodes: validCollapsibleNodes(in: homes))
            }
        }
    }

    private func dismissSearchInput() {
        guard isSearchFocused else { return }
        isSearchFocused = false
    }

    private func updateBreadcrumbPath(from anchors: [BreadcrumbAnchor]) {
        let threshold: CGFloat = 48
        let candidate = anchors
            .filter { $0.minY <= threshold }
            .max(by: { $0.minY < $1.minY })
        let candidatePath = candidate?.path ?? []
        let nextPath = candidatePath.count > 1 ? candidatePath : []

        guard nextPath != breadcrumbPath else { return }

        DispatchQueue.main.async {
            if breadcrumbPath != nextPath {
                breadcrumbPath = nextPath
            }
        }
    }

    private var filteredHomes: [HomeDetail] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty || showFlaggedOnly else { return homeStore.homeDetails }

        return homeStore.homeDetails.compactMap { home in
            let q = query.lowercased()
            let hasQuery = !q.isEmpty
            let homeMatches = hasQuery && home.name.localizedCaseInsensitiveContains(q)

            // Find locations whose name matches
            let directMatchIds = Set(
                home.locations
                    .filter { hasQuery && $0.name.localizedCaseInsensitiveContains(q) }
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

            // Find items that match by name/notes/properties
            let matchingItems = home.items.filter {
                guard hasQuery else { return true }
                return $0.name.localizedCaseInsensitiveContains(q) ||
                ($0.notes ?? "").localizedCaseInsensitiveContains(q) ||
                ($0.serialNumber ?? "").localizedCaseInsensitiveContains(q) ||
                ($0.modelNumber ?? "").localizedCaseInsensitiveContains(q) ||
                $0.properties.contains {
                    $0.key.localizedCaseInsensitiveContains(q) ||
                    $0.value.localizedCaseInsensitiveContains(q)
                }
            }

            let visibleItems = home.items.filter { item in
                if showFlaggedOnly && !item.isFlagged { return false }
                if !hasQuery { return true }
                if homeMatches { return true }
                if matchingItems.contains(where: { $0.id == item.id }) { return true }
                if let locId = item.locationId { return matchingLocationIds.contains(locId) }
                return false
            }

            if showFlaggedOnly && visibleItems.isEmpty {
                return nil
            }

            // If home name matches, show everything
            if homeMatches && !showFlaggedOnly {
                return home
            }

            if !homeMatches && directMatchIds.isEmpty && visibleItems.isEmpty {
                return nil
            }

            // Collect all location IDs we need to show (matching + ancestors)
            var allNeeded = showFlaggedOnly ? Set<String>() : matchingLocationIds
            // Add locations needed for matching items
            allNeeded.formUnion(visibleItems.compactMap { $0.locationId })
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

            return HomeDetail(
                id: home.id,
                name: home.name,
                ownerId: home.ownerId,
                role: home.role,
                icon: home.icon,
                locations: filteredLocations,
                items: visibleItems
            )
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || showFlaggedOnly
    }

    private var emptyFilterTitle: String {
        showFlaggedOnly ? "No Flagged Items" : "No Results"
    }

    private var emptyFilterDescription: String {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if showFlaggedOnly && !query.isEmpty {
            return "No flagged items match \"\(query)\"."
        }
        if showFlaggedOnly {
            return "Flag items to keep them close at hand."
        }
        return "No matches for \"\(query)\"."
    }

    private func validCollapsibleNodes(in homes: [HomeDetail]) -> Set<CollapsibleTreeNode> {
        var nodes = Set(homes.map { CollapsibleTreeNode.home($0.id) })
        nodes.formUnion(
            homes
                .flatMap(\.locations)
                .map { CollapsibleTreeNode.location($0.id) }
        )
        return nodes
    }
}

private struct SearchDismissTapShield: View {
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            .accessibilityHidden(true)
    }
}

private struct BottomSearchControls: View {
    @Binding var searchText: String
    @Binding var showFlaggedOnly: Bool
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: isSearchFocused ? 0 : 10) {
            if !isSearchFocused {
                BottomFlagFilterButton(isOn: $showFlaggedOnly)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .scale(scale: 0.78, anchor: .leading).combined(with: .opacity)
                        )
                    )
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField("Search stuff...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit {
                        isSearchFocused = false
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: isSearchFocused ? 52 : 48)
            .padding(.horizontal, isSearchFocused ? 15 : 13)
            .bottomSearchFieldSurface(isFocused: isSearchFocused)
        }
        .padding(.horizontal, isSearchFocused ? 10 : 14)
        .padding(.top, isSearchFocused ? 10 : 8)
        .padding(.bottom, isSearchFocused ? 10 : 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isSearchFocused)
        .animation(.easeInOut(duration: 0.18), value: searchText.isEmpty)
    }
}

private struct BottomFlagFilterButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "flag.fill" : "flag")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 48, height: 48)
        }
        .foregroundStyle(isOn ? .orange : .secondary)
        .bottomFlagFilterSurface(isOn: isOn)
        .accessibilityLabel(isOn ? "Showing flagged items" : "Show flagged items")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct BottomSearchFieldSurfaceModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(Color(.systemBackground).opacity(isFocused ? 0.22 : 0.16), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(isFocused ? 0.28 : 0.16), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(isFocused ? 0.16 : 0.10), radius: isFocused ? 18 : 12, y: 6)
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.stroke(Color(.separator).opacity(isFocused ? 0.24 : 0.16), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 5)
        }
    }
}

private struct BottomFlagFilterSurfaceModifier: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(iOS 26.0, *) {
            if isOn {
                content
                    .background(Color.orange.opacity(0.14), in: shape)
                    .glassEffect(.regular.tint(.orange).interactive(), in: shape)
                    .overlay(shape.stroke(Color.orange.opacity(0.28), lineWidth: 0.75))
                    .shadow(color: Color.orange.opacity(0.18), radius: 12, y: 5)
            } else {
                content
                    .background(Color(.systemBackground).opacity(0.16), in: shape)
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.75))
                    .shadow(color: Color.black.opacity(0.10), radius: 12, y: 5)
            }
        } else {
            content
                .background(isOn ? Color.orange.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: shape)
                .overlay(shape.stroke(isOn ? Color.orange.opacity(0.32) : Color(.separator).opacity(0.16), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

private extension View {
    func bottomSearchFieldSurface(isFocused: Bool) -> some View {
        modifier(BottomSearchFieldSurfaceModifier(isFocused: isFocused))
    }

    func bottomFlagFilterSurface(isOn: Bool) -> some View {
        modifier(BottomFlagFilterSurfaceModifier(isOn: isOn))
    }
}

private struct StartupPhotoLoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            Image("AppLaunchPhoto")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.42),
                    Color.black.opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Stuff Tracker")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                ProgressView(message)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.88))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BreadcrumbBar: View {
    let path: [String]

    var body: some View {
        if path.count > 1 {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(segment)
                        .font(.caption)
                        .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .floatingBreadcrumbSurface()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.16), value: path)
        }
    }
}

private struct FloatingBreadcrumbSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(.systemBackground).opacity(0.16), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: Color.black.opacity(0.10), radius: 12, y: 5)
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: shape)
                .overlay(shape.stroke(Color(.separator).opacity(0.18), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

private extension View {
    func floatingBreadcrumbSurface() -> some View {
        modifier(FloatingBreadcrumbSurfaceModifier())
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
    @State private var itemTargeted = false
    @State private var locationTargeted = false
    @State private var homeTargeted = false

    private var isTargeted: Bool {
        itemTargeted || locationTargeted || homeTargeted
    }

    var body: some View {
        ZStack {
            if isTargeted {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.title2)
                        .foregroundStyle(.white)

                    Text("Drop to Delete")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .trashDropSurface()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isTargeted ? 82 : 44)
        .contentShape(Rectangle())
        .accessibilityHidden(!isTargeted)
        .animation(.easeInOut(duration: 0.18), value: isTargeted)
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            for home in homeStore.homeDetails where home.items.contains(where: { $0.id == dragged.id }) {
                Task { @MainActor in
                    homeStore.deleteItem(homeId: home.id, itemId: dragged.id)
                }
                return true
            }
            return false
        } isTargeted: { itemTargeted = $0 }
        .dropDestination(for: DraggedLocation.self) { locations, _ in
            guard let dragged = locations.first else { return false }
            Task { @MainActor in
                homeStore.deleteLocation(homeId: dragged.homeId, locationId: dragged.id)
            }
            return true
        } isTargeted: { locationTargeted = $0 }
        .dropDestination(for: DraggedHome.self) { homes, _ in
            guard let dragged = homes.first else { return false }
            Task { @MainActor in
                homeStore.deleteHome(dragged.id)
            }
            return true
        } isTargeted: { homeTargeted = $0 }
    }
}

private struct TrashDropSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(Color.red.opacity(0.38), in: shape)
                .glassEffect(.regular.tint(.red).interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                .shadow(color: Color.red.opacity(0.24), radius: 14, y: 6)
        } else {
            content
                .background(Color.red, in: shape)
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        }
    }
}

private extension View {
    func trashDropSurface() -> some View {
        modifier(TrashDropSurfaceModifier())
    }
}
