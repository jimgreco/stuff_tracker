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

@MainActor
final class ItemAddComposerController: ObservableObject {
    @Published var isPresented = false
    @Published var name = ""
    private(set) var homeId = ""
    private(set) var locationId: String?

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var submittedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func present(homeId: String, locationId: String?) {
        self.homeId = homeId
        self.locationId = locationId
        name = ""
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        name = ""
        homeId = ""
        locationId = nil
    }
}

@MainActor
final class HierarchyAddComposerController: ObservableObject {
    enum Target: Equatable {
        case home
        case location(homeId: String, parentId: String?, type: Location.LocationType)
    }

    @Published var isPresented = false
    @Published var name = ""
    private(set) var target: Target?

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var submittedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var placeholder: String {
        switch target {
        case .home:
            return "Home name"
        case .location(_, _, let type):
            return "\(type.displayName) name"
        case nil:
            return "Name"
        }
    }

    var submitAccessibilityLabel: String {
        switch target {
        case .home:
            return "Add home"
        case .location(_, _, let type):
            return "Add \(type.displayName.lowercased())"
        case nil:
            return "Add"
        }
    }

    func presentHome() {
        target = .home
        name = ""
        isPresented = true
    }

    func presentLocation(homeId: String, parentId: String?, type: Location.LocationType) {
        target = .location(homeId: homeId, parentId: parentId, type: type)
        name = ""
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        name = ""
        target = nil
    }
}

private extension Location.LocationType {
    var displayName: String {
        switch self {
        case .floor: return "Floor"
        case .room: return "Room"
        case .container: return "Container"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject private var deepLinkStore: DeepLinkStore
    @EnvironmentObject private var tutorialController: FirstRunTutorialController
    @StateObject private var homeStore = HomeStore()
    @StateObject private var collapseStore = HierarchyCollapseStore()
    @StateObject private var itemSelection = ItemSelectionController()
    @StateObject private var itemComposer = ItemAddComposerController()
    @StateObject private var hierarchyComposer = HierarchyAddComposerController()
    @State private var searchText = ""
    @State private var showFlaggedOnly = false
    @State private var showAccountSheet = false
    @State private var showBulkMoveSheet = false
    @State private var showBulkDeleteConfirm = false
    @State private var deepLinkedItem: Item?
    @State private var deepLinkScrollTargetID: String?
    @State private var breadcrumbPath: [String] = []
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchInputPresented = false

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
                        ScrollViewReader { proxy in
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
                                        HStack {
                                            HierarchyAddChip(title: "Add Home") {
                                                presentHomeComposer()
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.bottom, 8)

                                        TrashBinView(homeStore: homeStore)
                                    }
                                }
                                .padding()
                                .padding(.bottom, 104)
                            }
                            .coordinateSpace(name: "scroll")
                            .onPreferenceChange(BreadcrumbPreferenceKey.self) { anchors in
                                updateBreadcrumbPath(from: anchors)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .task(id: deepLinkScrollTargetID) {
                                scrollToDeepLinkedItem(deepLinkScrollTargetID, proxy: proxy)
                            }
                        }
                    }
                }
            }
            .background(CubbyWallBackground())
            .overlay(alignment: .top) {
                if !isSearchInputPresented {
                    BreadcrumbBar(path: breadcrumbPath)
                }
            }
            .overlay {
                if isSearchInputPresented {
                    SearchDismissTapShield {
                        dismissSearchInput()
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if itemSelection.isSelecting {
                    SelectionActionBar(
                        selectedCount: itemSelection.selectedCount,
                        canMove: selectedHomeForActions != nil,
                        isUnflagAction: shouldUnflagSelection,
                        onMove: { showBulkMoveSheet = true },
                        onFlag: { setSelectedItemsFlagged() },
                        onDelete: { requestDeleteSelectedItems() }
                    )
                } else if itemComposer.isPresented {
                    AddComposerBar(
                        placeholder: "Item name",
                        text: $itemComposer.name,
                        canSubmit: itemComposer.canSubmit,
                        submitAccessibilityLabel: "Add item",
                        onCancel: { itemComposer.dismiss() },
                        onSubmit: { submitComposedItem() }
                    )
                } else if hierarchyComposer.isPresented {
                    AddComposerBar(
                        placeholder: hierarchyComposer.placeholder,
                        text: $hierarchyComposer.name,
                        canSubmit: hierarchyComposer.canSubmit,
                        submitAccessibilityLabel: hierarchyComposer.submitAccessibilityLabel,
                        onCancel: { hierarchyComposer.dismiss() },
                        onSubmit: { submitComposedHierarchy() }
                    )
                } else if shouldShowSearchControls {
                    BottomSearchControls(
                        searchText: $searchText,
                        showFlaggedOnly: $showFlaggedOnly,
                        isSearchPresented: isSearchInputPresented,
                        isSearchFocused: $isSearchFocused,
                        onActivateSearch: { activateSearchInput() },
                        onSubmitSearch: { dismissSearchInput() }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                DragTrashZone(homeStore: homeStore)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 76)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .cubbyNavigationBarChrome()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: "CubbyLog")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if itemSelection.isSelecting {
                        Button {
                            itemSelection.clearSelection()
                        } label: {
                            CubbyToolbarTextButtonLabel(title: "Done")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            dismissSearchInput()
                            itemSelection.startSelecting()
                        } label: {
                            CubbyToolbarTextButtonLabel(title: "Select")
                        }
                        .buttonStyle(.plain)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isSearchInputPresented {
                            dismissSearchInput()
                        } else {
                            showAccountSheet = true
                        }
                    } label: {
                        if let avatarUrl = authStore.currentUser?.avatarUrl,
                           let url = URL(string: avatarUrl) {
                            CubbyToolbarAvatarButtonLabel {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(CubbyTheme.paper.opacity(0.82))
                                }
                            }
                        } else {
                            CubbyToolbarAvatarButtonLabel {
                                Image(systemName: authStore.isAuthenticated ? "person.circle.fill" : "person.circle")
                                    .font(.title3)
                                    .foregroundStyle(CubbyTheme.paper.opacity(0.82))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Account")
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
            .sheet(isPresented: $showBulkMoveSheet) {
                if let home = selectedHomeForActions {
                    BulkItemMoveSheet(home: home, selectedCount: itemSelection.selectedCount) { locationId in
                        moveSelectedItems(to: locationId)
                    }
                }
            }
            .sheet(item: $deepLinkedItem) { item in
                let latestItem = itemForDeepLink(homeId: item.homeId, itemId: item.id) ?? item
                ItemEditView(item: latestItem, homeStore: homeStore, homeId: latestItem.homeId)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .overlay {
                if tutorialController.isPresented {
                    FirstRunTutorialOverlay(homeStore: homeStore)
                        .environmentObject(tutorialController)
                        .transition(.opacity)
                }
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { homeStore.errorMessage != nil },
                set: { if !$0 { homeStore.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(homeStore.errorMessage ?? "")
            }
            .alert("Delete \(itemSelection.selectedCount) items?", isPresented: $showBulkDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    deleteSelectedItems()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will move the selected items to the trash.")
            }
            .task {
                await homeStore.loadHomes()
                openPendingDeepLinkIfPossible(reportMissing: true)
                tutorialController.presentAfterInitialLoad(hasExistingHomes: !homeStore.homeDetails.isEmpty)
            }
            .onReceive(deepLinkStore.$pendingItemLink) { _ in
                openPendingDeepLinkIfPossible()
            }
            .onReceive(homeStore.$homeDetails) { homes in
                collapseStore.prune(validNodes: validCollapsibleNodes(in: homes))
                itemSelection.prune(validItemIds: Set(homes.flatMap(\.items).map(\.id)))
                openPendingDeepLinkIfPossible()
            }
            .onReceive(itemComposer.$isPresented) { isPresented in
                guard isPresented else { return }
                hierarchyComposer.dismiss()
                dismissSearchInput()
            }
            .onReceive(hierarchyComposer.$isPresented) { isPresented in
                guard isPresented else { return }
                itemComposer.dismiss()
                dismissSearchInput()
            }
        }
        .environmentObject(itemSelection)
        .environmentObject(itemComposer)
        .environmentObject(hierarchyComposer)
        .preferredColorScheme(.light)
    }

    private func dismissSearchInput() {
        guard isSearchInputPresented || isSearchFocused else { return }
        isSearchFocused = false
        isSearchInputPresented = false
    }

    private func activateSearchInput() {
        guard shouldShowSearchControls else { return }
        isSearchInputPresented = true
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func submitComposedItem() {
        guard itemComposer.canSubmit else { return }
        let name = itemComposer.submittedName
        let homeId = itemComposer.homeId
        let locationId = itemComposer.locationId
        itemComposer.dismiss()
        homeStore.createItem(homeId: homeId, name: name, locationId: locationId)
    }

    private func presentHomeComposer() {
        dismissSearchInput()
        itemComposer.dismiss()
        hierarchyComposer.presentHome()
    }

    private func submitComposedHierarchy() {
        guard hierarchyComposer.canSubmit, let target = hierarchyComposer.target else { return }
        let name = hierarchyComposer.submittedName
        hierarchyComposer.dismiss()

        switch target {
        case .home:
            homeStore.createHome(name: name)
        case .location(let homeId, let parentId, let type):
            homeStore.createLocation(homeId: homeId, name: name, parentId: parentId, type: type.rawValue)
        }
    }

    private var selectedHomeForActions: HomeDetail? {
        guard let homeId = itemSelection.selectedHomeId else { return nil }
        return homeStore.homeDetails.first { $0.id == homeId }
    }

    private var selectedItemsForActions: [Item] {
        guard let home = selectedHomeForActions else { return [] }
        let selectedIds = Set(itemSelection.selectedItemIds)
        return home.items.filter { selectedIds.contains($0.id) }
    }

    private func openPendingDeepLinkIfPossible(reportMissing: Bool = false) {
        guard let link = deepLinkStore.pendingItemLink else { return }

        guard let context = deepLinkContext(homeId: link.homeId, itemId: link.itemId) else {
            if reportMissing && !homeStore.isLoading {
                homeStore.errorMessage = "Could not open that item. Make sure you are signed in to an account that can access it."
                deepLinkStore.clear(link)
            }
            return
        }

        prepareHierarchyForDeepLink(to: context.item, in: context.home)
        deepLinkScrollTargetID = ItemDeepLink.itemAnchorID(context.item.id)
        deepLinkStore.clear(link)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            deepLinkedItem = itemForDeepLink(homeId: context.item.homeId, itemId: context.item.id) ?? context.item
        }
    }

    private func itemForDeepLink(homeId: String, itemId: String) -> Item? {
        deepLinkContext(homeId: homeId, itemId: itemId)?.item
    }

    private func deepLinkContext(homeId: String, itemId: String) -> (home: HomeDetail, item: Item)? {
        guard let home = homeStore.homeDetails.first(where: { $0.id == homeId }),
              let item = home.items.first(where: { $0.id == itemId }) else {
            return nil
        }
        return (home, item)
    }

    private func prepareHierarchyForDeepLink(to item: Item, in home: HomeDetail) {
        searchText = ""
        showFlaggedOnly = false
        isSearchFocused = false
        isSearchInputPresented = false
        itemSelection.clearSelection()
        itemComposer.dismiss()
        hierarchyComposer.dismiss()

        collapseStore.setCollapsed(false, for: .home(home.id))

        var currentLocationId = item.locationId
        while let locationId = currentLocationId,
              let location = home.locations.first(where: { $0.id == locationId }) {
            collapseStore.setCollapsed(false, for: .location(locationId))
            currentLocationId = location.parentId
        }
    }

    private func scrollToDeepLinkedItem(_ targetID: String?, proxy: ScrollViewProxy) {
        guard let targetID else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.26)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
            deepLinkScrollTargetID = nil
        }
    }

    private var shouldUnflagSelection: Bool {
        let selectedItems = selectedItemsForActions
        return !selectedItems.isEmpty && selectedItems.allSatisfy(\.isFlagged)
    }

    private func moveSelectedItems(to locationId: String?) {
        guard let homeId = itemSelection.selectedHomeId,
              itemSelection.selectedCount > 0 else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            homeStore.moveItems(homeId: homeId, itemIds: itemSelection.selectedItemIds, toLocation: locationId)
            itemSelection.clearSelection()
        }
    }

    private func setSelectedItemsFlagged() {
        guard let homeId = itemSelection.selectedHomeId,
              itemSelection.selectedCount > 0 else { return }

        let shouldFlag = !shouldUnflagSelection
        withAnimation(.easeInOut(duration: 0.18)) {
            homeStore.setItemsFlagged(homeId: homeId, itemIds: itemSelection.selectedItemIds, isFlagged: shouldFlag)
            itemSelection.clearSelection()
        }
    }

    private func requestDeleteSelectedItems() {
        guard itemSelection.selectedCount > 0 else { return }
        if itemSelection.selectedCount > 1 {
            showBulkDeleteConfirm = true
        } else {
            deleteSelectedItems()
        }
    }

    private func deleteSelectedItems() {
        guard let homeId = itemSelection.selectedHomeId,
              itemSelection.selectedCount > 0 else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            homeStore.deleteItems(homeId: homeId, itemIds: itemSelection.selectedItemIds)
            itemSelection.clearSelection()
        }
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

    private var shouldShowSearchControls: Bool {
        !itemSelection.isSelecting && !itemComposer.isPresented && !hierarchyComposer.isPresented
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

private struct CubbyToolbarTextButtonLabel: View {
    let title: String

    var body: some View {
        let shape = Capsule(style: .continuous)

        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(CubbyTheme.paper.opacity(0.76))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 15)
            .frame(width: 78, height: 38)
            .background {
                ZStack {
                    shape.fill(CubbyTheme.navigationWoodGradient)
                    WoodgrainOverlay(opacity: 0.08)
                        .clipShape(shape)
                    shape.fill(Color.white.opacity(0.03))
                }
            }
            .overlay(shape.stroke(CubbyTheme.paper.opacity(0.07), lineWidth: 0.75))
            .contentShape(shape)
    }
}

private struct CubbyToolbarAvatarButtonLabel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = Circle()

        content
            .frame(width: 28, height: 28)
            .clipShape(shape)
            .frame(width: 38, height: 38)
            .background {
                ZStack {
                    shape.fill(CubbyTheme.navigationWoodGradient)
                    WoodgrainOverlay(opacity: 0.08)
                        .clipShape(shape)
                    shape.fill(Color.white.opacity(0.03))
                }
            }
            .overlay(shape.stroke(CubbyTheme.paper.opacity(0.07), lineWidth: 0.75))
            .contentShape(shape)
    }
}

private struct SelectionActionBar: View {
    let selectedCount: Int
    let canMove: Bool
    let isUnflagAction: Bool
    let onMove: () -> Void
    let onFlag: () -> Void
    let onDelete: () -> Void

    private var hasSelection: Bool {
        selectedCount > 0
    }

    private var selectionText: String {
        selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(selectionText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(hasSelection ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(minWidth: 68, alignment: .leading)

            Spacer(minLength: 0)

            SelectionActionButton(
                title: "Move",
                systemImage: "folder",
                tint: .blue,
                isEnabled: hasSelection && canMove,
                action: onMove
            )

            SelectionActionButton(
                title: isUnflagAction ? "Unflag" : "Flag",
                systemImage: isUnflagAction ? "flag.slash" : "flag.fill",
                tint: CubbyTheme.amber,
                isEnabled: hasSelection,
                action: onFlag
            )

            SelectionActionButton(
                title: "Delete",
                systemImage: "trash",
                tint: .red,
                isEnabled: hasSelection,
                action: onDelete
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .selectionActionBarSurface()
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.18), value: selectedCount)
    }
}

private struct SelectionActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .frame(height: 18)

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: 52, height: 48)
            .selectionActionButtonSurface(tint: tint, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

private struct SelectionActionBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(CubbyTheme.paper.opacity(0.22), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.75))
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.16), radius: 16, y: 6)
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay(shape.stroke(CubbyTheme.floorBorder, lineWidth: 0.75))
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.12), radius: 12, y: 5)
        }
    }
}

private struct SelectionActionButtonSurfaceModifier: ViewModifier {
    let tint: Color
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(isEnabled ? tint : Color.secondary)
                .background(isEnabled ? tint.opacity(0.12) : CubbyTheme.paper.opacity(0.18), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(isEnabled ? tint.opacity(0.22) : Color.white.opacity(0.10), lineWidth: 0.75))
                .opacity(isEnabled ? 1 : 0.48)
        } else {
            content
                .foregroundStyle(isEnabled ? tint : Color.secondary)
                .background(isEnabled ? tint.opacity(0.12) : CubbyTheme.paper, in: shape)
                .overlay(shape.stroke(isEnabled ? tint.opacity(0.28) : Color(.separator).opacity(0.14), lineWidth: 0.75))
                .opacity(isEnabled ? 1 : 0.48)
        }
    }
}

private struct BulkItemMoveSheet: View {
    let home: HomeDetail
    let selectedCount: Int
    let onMove: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    private var title: String {
        selectedCount == 1 ? "Move Item" : "Move Items"
    }

    var body: some View {
        NavigationStack(path: $path) {
            BulkItemMoveLevel(home: home, parentId: nil, onMove: onMove, dismissSheet: { dismiss() })
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        CubbyNavigationBrandTitle(title: title)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        DismissButton()
                    }
                }
                .navigationDestination(for: String.self) { locId in
                    let loc = home.locations.first(where: { $0.id == locId })
                    BulkItemMoveLevel(home: home, parentId: locId, onMove: onMove, dismissSheet: { dismiss() })
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .cubbyNavigationTitle(loc?.name ?? "")
                }
        }
        .cubbyNavigationBarChrome()
    }
}

private struct BulkItemMoveLevel: View {
    let home: HomeDetail
    let parentId: String?
    let onMove: (String?) -> Void
    let dismissSheet: () -> Void

    private var children: [Location] {
        home.locations
            .filter { $0.parentId == parentId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                Button {
                    move(to: parentId)
                } label: {
                    HStack {
                        Label(parentId == nil ? "Move to \(home.name)" : "Move here", systemImage: parentId == nil ? (home.icon ?? "house.fill") : "checkmark.circle")
                        Spacer()
                    }
                }
                .foregroundStyle(.primary)
            }

            if !children.isEmpty {
                Section {
                    ForEach(children) { loc in
                        let hasChildren = home.locations.contains { $0.parentId == loc.id }
                        if hasChildren {
                            NavigationLink(value: loc.id) {
                                Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                            }
                        } else {
                            Button {
                                move(to: loc.id)
                            } label: {
                                HStack {
                                    Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                                    Spacer()
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func move(to locationId: String?) {
        onMove(locationId)
        dismissSheet()
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Cancel") {
            dismiss()
        }
    }
}

private struct AddComposerBar: View {
    let placeholder: String
    @Binding var text: String
    let canSubmit: Bool
    let submitAccessibilityLabel: String
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit {
                    if canSubmit {
                        onSubmit()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .padding(.horizontal, 14)
                .itemComposerFieldSurface()

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Cancel adding item")

            Button(action: onSubmit) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSubmit ? CubbyTheme.green : .secondary)
            .disabled(!canSubmit)
            .accessibilityLabel(submitAccessibilityLabel)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .itemComposerBarSurface()
        .onAppear {
            isFocused = true
        }
    }
}

private struct HierarchyAddChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CubbyTheme.green.opacity(0.78))

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .hierarchyAddChipSurface()
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
}

private struct HierarchyAddChipSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(CubbyTheme.green.opacity(0.075), in: shape)
                .overlay(shape.stroke(CubbyTheme.green.opacity(0.18), lineWidth: 0.5))
        } else {
            content
                .background(CubbyTheme.green.opacity(0.08), in: shape)
                .overlay(shape.stroke(CubbyTheme.green.opacity(0.20), lineWidth: 0.5))
        }
    }
}

private struct BottomSearchControls: View {
    @Binding var searchText: String
    @Binding var showFlaggedOnly: Bool
    let isSearchPresented: Bool
    @FocusState.Binding var isSearchFocused: Bool
    let onActivateSearch: () -> Void
    let onSubmitSearch: () -> Void

    var body: some View {
        HStack(spacing: isSearchPresented ? 0 : 10) {
            if !isSearchPresented {
                BottomFlagFilterButton(isOn: $showFlaggedOnly)
            }

            searchField
            .frame(maxWidth: .infinity)
            .frame(height: isSearchPresented ? 52 : 48)
            .padding(.horizontal, isSearchPresented ? 15 : 13)
            .bottomSearchFieldSurface(isFocused: isSearchPresented)
        }
        .padding(.horizontal, isSearchPresented ? 10 : 14)
        .padding(.top, isSearchPresented ? 10 : 8)
        .padding(.bottom, isSearchPresented ? 10 : 8)
    }

    @ViewBuilder
    private var searchField: some View {
        if isSearchPresented {
            HStack(spacing: 8) {
                searchIcon

                TextField("Search stuff...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit {
                        onSubmitSearch()
                    }

                clearSearchButton
            }
        } else {
            HStack(spacing: 8) {
                Button {
                    onActivateSearch()
                } label: {
                    HStack(spacing: 8) {
                        searchIcon

                        Text(searchText.isEmpty ? "Search stuff..." : searchText)
                            .lineLimit(1)
                            .foregroundStyle(searchText.isEmpty ? .secondary : .primary)

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Search stuff...")
                .accessibilityAddTraits(.isButton)

                clearSearchButton
            }
        }
    }

    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var clearSearchButton: some View {
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
        .foregroundStyle(isOn ? CubbyTheme.amber : .secondary)
        .bottomFlagFilterSurface(isOn: isOn)
        .accessibilityLabel(isOn ? "Showing flagged items" : "Show flagged items")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct ItemComposerBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = Rectangle()

        if #available(iOS 26.0, *) {
            content
                .background(CubbyTheme.paper.opacity(0.24), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(CubbyTheme.paper.opacity(0.96), in: shape)
        }
    }
}

private struct ItemComposerFieldSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(CubbyTheme.paper.opacity(0.30), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.75))
        } else {
            content
                .background(CubbyTheme.paper, in: shape)
                .overlay(shape.stroke(CubbyTheme.floorBorder.opacity(0.72), lineWidth: 0.75))
        }
    }
}

private struct BottomSearchFieldSurfaceModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        if #available(iOS 26.0, *) {
            if isFocused {
                content
                    .background(CubbyTheme.paper.opacity(0.30), in: shape)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.36), lineWidth: 0.75))
                    .shadow(color: CubbyTheme.shelfShadow.opacity(0.18), radius: 18, y: 6)
            } else {
                content
                    .background(CubbyTheme.paper.opacity(0.22), in: shape)
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.75))
                    .shadow(color: CubbyTheme.shelfShadow.opacity(0.12), radius: 12, y: 6)
            }
        } else {
            content
                .background(CubbyTheme.paper.opacity(0.96), in: shape)
                .overlay(shape.stroke(CubbyTheme.floorBorder.opacity(isFocused ? 1 : 0.72), lineWidth: 0.75))
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.12), radius: 12, y: 5)
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
                    .background(CubbyTheme.amber.opacity(0.14), in: shape)
                    .glassEffect(.regular.tint(CubbyTheme.amber).interactive(), in: shape)
                    .overlay(shape.stroke(CubbyTheme.amber.opacity(0.28), lineWidth: 0.75))
                    .shadow(color: CubbyTheme.amber.opacity(0.18), radius: 12, y: 5)
            } else {
                content
                    .background(CubbyTheme.paper.opacity(0.22), in: shape)
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.20), lineWidth: 0.75))
                    .shadow(color: CubbyTheme.shelfShadow.opacity(0.12), radius: 12, y: 5)
            }
        } else {
            content
                .background(isOn ? CubbyTheme.amber.opacity(0.14) : CubbyTheme.paper, in: shape)
                .overlay(shape.stroke(isOn ? CubbyTheme.amber.opacity(0.32) : CubbyTheme.floorBorder.opacity(0.72), lineWidth: 0.75))
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.10), radius: 10, y: 4)
        }
    }
}

private extension View {
    func selectionActionBarSurface() -> some View {
        modifier(SelectionActionBarSurfaceModifier())
    }

    func selectionActionButtonSurface(tint: Color, isEnabled: Bool) -> some View {
        modifier(SelectionActionButtonSurfaceModifier(tint: tint, isEnabled: isEnabled))
    }

    func itemComposerBarSurface() -> some View {
        modifier(ItemComposerBarSurfaceModifier())
    }

    func itemComposerFieldSurface() -> some View {
        modifier(ItemComposerFieldSurfaceModifier())
    }

    func bottomSearchFieldSurface(isFocused: Bool) -> some View {
        modifier(BottomSearchFieldSurfaceModifier(isFocused: isFocused))
    }

    func bottomFlagFilterSurface(isOn: Bool) -> some View {
        modifier(BottomFlagFilterSurfaceModifier(isOn: isOn))
    }

    func hierarchyAddChipSurface() -> some View {
        modifier(HierarchyAddChipSurfaceModifier())
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
                Text("CubbyLog")
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
                .background(CubbyTheme.paper.opacity(0.24), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.12), radius: 12, y: 5)
        } else {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(CubbyTheme.paper.opacity(0.96), in: shape)
                .overlay(shape.stroke(CubbyTheme.floorBorder.opacity(0.72), lineWidth: 0.5))
                .shadow(color: CubbyTheme.shelfShadow.opacity(0.10), radius: 10, y: 4)
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
            Image(systemName: "cabinet.fill")
                .font(.system(size: 64))
                .foregroundStyle(CubbyTheme.green)
            
            Text("Welcome to CubbyLog")
                .font(.title.bold())
            
            Text("Track your stuff across rooms and containers")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            Button("Create Your First Home", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(CubbyTheme.green)
            
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

struct FirstRunTutorialOverlay: View {
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
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 360)

                footer
            }
            .padding(18)
            .frame(maxWidth: 560, alignment: .leading)
            .tutorialCoachCardSurface()
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .sheet(item: $editingItem) { item in
            let latestItem = latestItem(withId: item.id) ?? item
            ItemEditView(item: latestItem, homeStore: homeStore, homeId: latestItem.homeId)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Step \(stepIndex + 1) of \(FirstRunTutorialStep.allCases.count)", systemImage: step.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    tutorialController.complete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Skip tutorial")
            }

            ProgressView(value: Double(stepIndex + 1), total: Double(FirstRunTutorialStep.allCases.count))
                .tint(.accentColor)

            Text(step.title)
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 14) {
                Text("CubbyLog is a map for the things you swear you put somewhere obvious. You can organize your stuff into a hierarchy of homes, floors, rooms, and containers.")
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
                    detail: "Floors, rooms, and containers are available when you want more structure."
                )
                TutorialFeatureRow(
                    systemImage: "tag",
                    title: "Items",
                    detail: "Add the things you want to find, document, or keep organized."
                )
            }

        case .home:
            VStack(alignment: .leading, spacing: 16) {
                Text("Create your first Home. It will appear in the hierarchy behind this tutorial.")
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
                Text("Floors, rooms, and containers are optional. You can add them later from the Home's menu, and items can stay directly in the Home until you need more organization.")
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
                Text("Add an item to the Home. The item chip will appear in the actual Home behind this card.")
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
                Text("Open the real item details sheet to see what is editable: name, icon, quantity, notes, dates, serial and model numbers, value, location, and custom properties.")
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
                Text("When this tutorial is gone, the things you see behind it can be dragged and dropped to reorder or move them where they belong.")
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
                    detail: "Use Select, choose multiple items, then move, flag, or delete them from the bottom controls."
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
        .padding(.top, 2)
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

private struct TutorialCoachCardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(Color(.systemBackground).opacity(0.20), in: shape)
                .glassEffect(.regular.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.24), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.22), radius: 24, y: 10)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color(.separator).opacity(0.20), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
        }
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
    func tutorialCoachCardSurface() -> some View {
        modifier(TutorialCoachCardSurfaceModifier())
    }

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
