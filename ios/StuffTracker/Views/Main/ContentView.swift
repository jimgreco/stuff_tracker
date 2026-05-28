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

@MainActor
final class FirstRunTutorialController: ObservableObject {
    static let completedDefaultsKey = "has_completed_first_run_tutorial_v1"

    @Published private(set) var hasCompleted: Bool
    @Published var isPresented = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Self.completedDefaultsKey)
    }

    func presentAfterInitialLoad(hasExistingHomes: Bool) {
        guard !hasCompleted else { return }

        if hasExistingHomes {
            complete()
        } else {
            isPresented = true
        }
    }

    func resetAndReplay() {
        setCompleted(false)
        isPresented = true
    }

    func complete() {
        setCompleted(true)
        isPresented = false
    }

    private func setCompleted(_ completed: Bool) {
        hasCompleted = completed
        defaults.set(completed, forKey: Self.completedDefaultsKey)
    }
}

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject private var tutorialController: FirstRunTutorialController
    @StateObject private var homeStore = HomeStore()
    @StateObject private var collapseStore = HierarchyCollapseStore()
    @StateObject private var itemSelection = ItemSelectionController()
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
                ToolbarItem(placement: .topBarLeading) {
                    if itemSelection.isSelecting {
                        Button {
                            itemSelection.clearSelection()
                        } label: {
                            Text("Done")
                        }
                    } else {
                        Button {
                            dismissSearchInput()
                            itemSelection.startSelecting()
                        } label: {
                            Text("Select")
                        }
                    }
                }
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
                AccountView(homeStore: homeStore) {
                    showAccountSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        tutorialController.resetAndReplay()
                    }
                }
                    .environmentObject(authStore)
                    .environmentObject(SyncManager.shared)
            }
            .fullScreenCover(isPresented: $tutorialController.isPresented) {
                FirstRunTutorialView(homeStore: homeStore)
                    .environmentObject(tutorialController)
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { homeStore.errorMessage != nil },
                set: { if !$0 { homeStore.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(homeStore.errorMessage ?? "")
            }
            .task {
                await homeStore.loadHomes()
                tutorialController.presentAfterInitialLoad(hasExistingHomes: !homeStore.homeDetails.isEmpty)
            }
            .onReceive(homeStore.$homeDetails) { homes in
                collapseStore.prune(validNodes: validCollapsibleNodes(in: homes))
                itemSelection.prune(validItemIds: Set(homes.flatMap(\.items).map(\.id)))
            }
        }
        .environmentObject(itemSelection)
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
            let homeIsFlagged = showFlaggedOnly && home.isFlagged

            if homeIsFlagged && (!hasQuery || homeMatches) {
                return home
            }

            func expandedLocationIds(from rootIds: Set<String>) -> Set<String> {
                var expandedIds = rootIds
                var toExpand = rootIds
                while !toExpand.isEmpty {
                    let children = Set(
                        home.locations
                            .filter { loc in loc.parentId.map { toExpand.contains($0) } ?? false }
                            .map { $0.id }
                    )
                    let newChildren = children.subtracting(expandedIds)
                    expandedIds.formUnion(newChildren)
                    toExpand = newChildren
                }
                return expandedIds
            }

            // Find locations whose name matches
            let directMatchIds = Set(
                home.locations
                    .filter { hasQuery && $0.name.localizedCaseInsensitiveContains(q) }
                    .map { $0.id }
            )

            // Expand to include all descendants of matching locations
            let matchingLocationIds = expandedLocationIds(from: directMatchIds)

            let flaggedRootLocationIds = Set(
                home.locations
                    .filter { location in
                        guard showFlaggedOnly && location.isFlagged else { return false }
                        if !hasQuery || homeMatches { return true }
                        return location.name.localizedCaseInsensitiveContains(q) ||
                        matchingLocationIds.contains(location.id)
                    }
                    .map(\.id)
            )
            let flaggedLocationIds = expandedLocationIds(from: flaggedRootLocationIds)

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
                let isInsideFlaggedHome = homeIsFlagged
                let isInsideFlaggedLocation = item.locationId.map { flaggedLocationIds.contains($0) } ?? false
                if showFlaggedOnly && !item.isFlagged && !isInsideFlaggedLocation && !isInsideFlaggedHome { return false }
                if !hasQuery { return true }
                if isInsideFlaggedLocation { return true }
                if homeMatches { return true }
                if matchingItems.contains(where: { $0.id == item.id }) { return true }
                if let locId = item.locationId { return matchingLocationIds.contains(locId) }
                return false
            }

            if showFlaggedOnly && visibleItems.isEmpty && flaggedLocationIds.isEmpty && !(homeIsFlagged && !directMatchIds.isEmpty) {
                return nil
            }

            // If home name matches, show everything
            if homeMatches && !showFlaggedOnly {
                return home
            }

            if !homeMatches && directMatchIds.isEmpty && visibleItems.isEmpty && flaggedLocationIds.isEmpty {
                return nil
            }

            // Collect all location IDs we need to show (matching + ancestors)
            var allNeeded = (showFlaggedOnly && !homeIsFlagged) ? Set<String>() : matchingLocationIds
            allNeeded.formUnion(flaggedLocationIds)
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
                isFlagged: home.isFlagged,
                locations: filteredLocations,
                items: visibleItems
            )
        }
    }

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || showFlaggedOnly
    }

    private var emptyFilterTitle: String {
        showFlaggedOnly ? "No Flags" : "No Results"
    }

    private var emptyFilterDescription: String {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if showFlaggedOnly && !query.isEmpty {
            return "No flagged homes, containers, or items match \"\(query)\"."
        }
        if showFlaggedOnly {
            return "Flag homes, containers, or items to keep them close at hand."
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

// MARK: - First run tutorial

private enum FirstRunTutorialStep: Int, CaseIterable {
    case welcome
    case home
    case rooms
    case item
    case details
    case moving

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .home: return "Create a Home"
        case .rooms: return "Floors and Rooms"
        case .item: return "Add an Item"
        case .details: return "Open Details"
        case .moving: return "Move Things"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: return "shippingbox.fill"
        case .home: return "house.fill"
        case .rooms: return "door.left.hand.open"
        case .item: return "tag.fill"
        case .details: return "slider.horizontal.3"
        case .moving: return "hand.draw.fill"
        }
    }
}

struct FirstRunTutorialView: View {
    @ObservedObject var homeStore: HomeStore
    @EnvironmentObject private var tutorialController: FirstRunTutorialController
    @State private var step: FirstRunTutorialStep = .welcome
    @State private var homeName = "Home"
    @State private var itemName = "Keys"
    @State private var selectedHomeId: String?
    @State private var selectedItemId: String?
    @State private var didOpenItemDetails = false
    @State private var editingItem: Item?

    private var stepIndex: Int {
        FirstRunTutorialStep.allCases.firstIndex(of: step) ?? 0
    }

    private var selectedHome: HomeDetail? {
        if let selectedHomeId,
           let home = homeStore.homeDetails.first(where: { $0.id == selectedHomeId }) {
            return home
        }
        return homeStore.homeDetails.first
    }

    private var selectedItem: Item? {
        guard let home = selectedHome else { return nil }
        if let selectedItemId,
           let item = home.items.first(where: { $0.id == selectedItemId }) {
            return item
        }
        return home.items.first
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome, .rooms:
            return "Next"
        case .home:
            return selectedHome == nil ? "Create Home" : "Next"
        case .item:
            return selectedItem == nil ? "Create Item" : "Next"
        case .details:
            return didOpenItemDetails ? "Next" : "Open Details"
        case .moving:
            return "Finish"
        }
    }

    private var canUsePrimaryButton: Bool {
        switch step {
        case .home:
            return selectedHome != nil || !homeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .item:
            return selectedItem != nil || !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .details:
            return selectedItem != nil
        default:
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        stepContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                footer
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Tutorial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        tutorialController.complete()
                    }
                }
            }
            .interactiveDismissDisabled()
            .sheet(item: $editingItem) { item in
                let latestItem = latestItem(withId: item.id) ?? item
                ItemEditView(item: latestItem, homeStore: homeStore, homeId: latestItem.homeId)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(stepIndex + 1), total: Double(FirstRunTutorialStep.allCases.count))
                .tint(.accentColor)

            HStack(alignment: .center, spacing: 16) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(stepIndex + 1) of \(FirstRunTutorialStep.allCases.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(step.title)
                        .font(.title2.weight(.bold))
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 14) {
                Text("Stuff Tracker starts with a Home, then lets you organize items directly in that Home or inside optional floors, rooms, and containers.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TutorialFeatureRow(
                    systemImage: "house",
                    title: "Homes",
                    detail: "Create one for each place you want to track."
                )
                TutorialFeatureRow(
                    systemImage: "square.grid.2x2",
                    title: "Spaces",
                    detail: "Floors and rooms are available when you want more structure."
                )
                TutorialFeatureRow(
                    systemImage: "tag",
                    title: "Items",
                    detail: "Add the things you want to find, document, or keep organized."
                )
            }

        case .home:
            VStack(alignment: .leading, spacing: 16) {
                Text("Create your first Home. This is the top-level place where your stuff lives.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField("Home name", text: $homeName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .tutorialTextFieldSurface()

                if let selectedHome {
                    TutorialSelectedRow(
                        systemImage: "checkmark.circle.fill",
                        text: "Using \(selectedHome.name)"
                    )
                }
            }

        case .rooms:
            VStack(alignment: .leading, spacing: 14) {
                Text("Floors and rooms are optional. You can add them later from a Home menu, and items can stay directly in the Home until you need more organization.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TutorialFeatureRow(
                    systemImage: "building.2",
                    title: "Floors",
                    detail: "Useful for larger homes, offices, storage units, or multi-level spaces."
                )
                TutorialFeatureRow(
                    systemImage: "door.left.hand.closed",
                    title: "Rooms",
                    detail: "Use rooms to group items by where you would naturally look for them."
                )
                TutorialFeatureRow(
                    systemImage: "shippingbox",
                    title: "Containers",
                    detail: "Rooms can hold containers, and containers can hold more containers."
                )
            }

        case .item:
            VStack(alignment: .leading, spacing: 16) {
                Text("Add an item to the Home. You can move it into a room or container later.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let selectedHome {
                    TutorialSelectedRow(
                        systemImage: "house.fill",
                        text: selectedHome.name
                    )
                }

                TextField("Item name", text: $itemName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .tutorialTextFieldSurface()

                if let selectedItem {
                    TutorialSelectedRow(
                        systemImage: "checkmark.circle.fill",
                        text: "Created \(selectedItem.name)"
                    )
                }
            }

        case .details:
            VStack(alignment: .leading, spacing: 16) {
                Text("Open the item details to see what is editable: name, icon, quantity, notes, dates, serial and model numbers, value, location, and custom properties.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TutorialFeatureRow(
                    systemImage: "photo.on.rectangle",
                    title: "Photos",
                    detail: "Add photos from your library or camera."
                )
                TutorialFeatureRow(
                    systemImage: "doc.badge.plus",
                    title: "Documents",
                    detail: "Attach manuals, receipts, warranties, or other files."
                )

                if didOpenItemDetails {
                    TutorialSelectedRow(
                        systemImage: "checkmark.circle.fill",
                        text: "Details opened"
                    )
                }
            }

        case .moving:
            VStack(alignment: .leading, spacing: 14) {
                Text("Items, homes, rooms, and containers can be dragged and dropped to reorder or move them where they belong.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TutorialFeatureRow(
                    systemImage: "hand.draw",
                    title: "Drag items",
                    detail: "Long-press an item chip, then drag it into a Home, room, or container."
                )
                TutorialFeatureRow(
                    systemImage: "checkmark.circle",
                    title: "Move several",
                    detail: "Use Select, choose multiple items, then drag the group together."
                )
                TutorialFeatureRow(
                    systemImage: "trash",
                    title: "Drop to delete",
                    detail: "Drag to the bottom trash target when you want to delete something."
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if stepIndex > 0 {
                Button {
                    moveBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button {
                performPrimaryAction()
            } label: {
                Label(primaryButtonTitle, systemImage: step == .moving ? "checkmark" : "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canUsePrimaryButton)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private func performPrimaryAction() {
        switch step {
        case .welcome, .rooms:
            moveForward()
        case .home:
            if selectedHome == nil {
                createTutorialHome()
            }
            if selectedHome != nil {
                moveForward()
            }
        case .item:
            if selectedItem == nil {
                createTutorialItem()
            }
            if selectedItem != nil {
                moveForward()
            }
        case .details:
            if didOpenItemDetails {
                moveForward()
            } else {
                openSelectedItemDetails()
            }
        case .moving:
            tutorialController.complete()
        }
    }

    private func moveForward() {
        let allSteps = FirstRunTutorialStep.allCases
        let nextIndex = min(stepIndex + 1, allSteps.count - 1)
        withAnimation(.easeInOut(duration: 0.18)) {
            step = allSteps[nextIndex]
        }
    }

    private func moveBack() {
        let allSteps = FirstRunTutorialStep.allCases
        let previousIndex = max(stepIndex - 1, 0)
        withAnimation(.easeInOut(duration: 0.18)) {
            step = allSteps[previousIndex]
        }
    }

    private func createTutorialHome() {
        let trimmedName = homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let existingIds = Set(homeStore.homeDetails.map(\.id))
        homeStore.createHome(name: trimmedName)
        selectedHomeId = homeStore.homeDetails.first { !existingIds.contains($0.id) }?.id
            ?? homeStore.homeDetails.first?.id
    }

    private func createTutorialItem() {
        guard let home = selectedHome else { return }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let existingIds = Set(home.items.map(\.id))
        homeStore.createItem(homeId: home.id, name: trimmedName, locationId: nil)
        selectedItemId = homeStore.homeDetails
            .first(where: { $0.id == home.id })?
            .items
            .first { !existingIds.contains($0.id) }?
            .id
    }

    private func openSelectedItemDetails() {
        guard let item = selectedItem else { return }
        didOpenItemDetails = true
        editingItem = item
    }

    private func latestItem(withId itemId: String) -> Item? {
        for home in homeStore.homeDetails {
            if let item = home.items.first(where: { $0.id == itemId }) {
                return item
            }
        }
        return nil
    }
}

private struct TutorialFeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TutorialSelectedRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TutorialTextFieldSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator).opacity(0.26), lineWidth: 0.75)
            }
    }
}

private extension View {
    func tutorialTextFieldSurface() -> some View {
        modifier(TutorialTextFieldSurfaceModifier())
    }
}

// MARK: - Drag trash zone

struct DragTrashZone: View {
    @ObservedObject var homeStore: HomeStore
    @EnvironmentObject private var itemSelection: ItemSelectionController
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
            for home in homeStore.homeDetails {
                let itemIds = dragged.itemIds.filter { itemId in
                    home.items.contains(where: { $0.id == itemId })
                }
                guard !itemIds.isEmpty else { continue }
                Task { @MainActor in
                    homeStore.deleteItems(homeId: home.id, itemIds: itemIds)
                    itemSelection.clearSelection()
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
