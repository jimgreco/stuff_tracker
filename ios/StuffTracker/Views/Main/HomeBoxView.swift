import SwiftUI

// MARK: - Design tokens

private extension Color {
    static let homeBox      = Color(.secondarySystemGroupedBackground)
    static let floorBox     = Color(.tertiarySystemGroupedBackground)
    static let roomBox      = Color(.tertiarySystemGroupedBackground)
    static let containerBox = Color(.systemBackground).opacity(0.72)

    static let homeBorder      = Color(.separator).opacity(0.28)
    static let floorBorder     = Color(.separator).opacity(0.24)
    static let roomBorder      = Color(.separator).opacity(0.22)
    static let containerBorder = Color(.separator).opacity(0.18)
}

// MARK: - Default icons

private func defaultIcon(for type: Location.LocationType, name: String) -> String {
    switch type {
    case .floor: return "building.2"
    case .room: return "door.left.hand.closed"
    case .container: return defaultContainerIcon(name)
    }
}

private func defaultContainerIcon(_ name: String) -> String {
    let lower = name.lowercased()
    if lower.contains("drawer") { return "rectangle.split.3x1" }
    if lower.contains("shelf") || lower.contains("bookcase") { return "books.vertical" }
    if lower.contains("box") || lower.contains("bin") { return "shippingbox" }
    if lower.contains("closet") || lower.contains("wardrobe") { return "cabinet" }
    if lower.contains("fridge") || lower.contains("freezer") { return "refrigerator" }
    if lower.contains("desk") { return "desktopcomputer" }
    if lower.contains("cabinet") { return "cabinet" }
    if lower.contains("bag") || lower.contains("backpack") { return "bag" }
    return "square.stack.3d.up"
}

private func customIcon(_ icon: String?, fallback: String) -> String {
    guard let icon, !icon.isEmpty else { return fallback }
    return icon
}

// MARK: - Tree collapse state

enum CollapsibleTreeNode: Hashable {
    case home(String)
    case location(String)

    var storageKey: String {
        switch self {
        case .home(let id): return "home:\(id)"
        case .location(let id): return "location:\(id)"
        }
    }
}

final class HierarchyCollapseStore: ObservableObject {
    @Published private(set) var collapsedNodeKeys: Set<String>

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "collapsed_tree_node_ids_v1",
        legacyContainerKey: String = "collapsed_container_ids_v1"
    ) {
        self.defaults = defaults
        self.key = key

        let stored = Set(defaults.stringArray(forKey: key) ?? [])
        let migratedContainers = Set(
            (defaults.stringArray(forKey: legacyContainerKey) ?? []).map { CollapsibleTreeNode.location($0).storageKey }
        )
        self.collapsedNodeKeys = stored.union(migratedContainers)

        if !migratedContainers.isEmpty && stored != collapsedNodeKeys {
            persist()
        }
    }

    func isCollapsed(_ node: CollapsibleTreeNode) -> Bool {
        collapsedNodeKeys.contains(node.storageKey)
    }

    func toggle(_ node: CollapsibleTreeNode) {
        setCollapsed(!isCollapsed(node), for: node)
    }

    func setCollapsed(_ collapsed: Bool, for node: CollapsibleTreeNode) {
        let storageKey = node.storageKey
        guard !storageKey.isEmpty else { return }

        let changed: Bool
        if collapsed {
            changed = collapsedNodeKeys.insert(storageKey).inserted
        } else {
            changed = collapsedNodeKeys.remove(storageKey) != nil
        }

        if changed {
            persist()
        }
    }

    func prune(validNodes: Set<CollapsibleTreeNode>) {
        let validKeys = Set(validNodes.map(\.storageKey))
        let pruned = collapsedNodeKeys.intersection(validKeys)
        guard pruned != collapsedNodeKeys else { return }

        collapsedNodeKeys = pruned
        persist()
    }

    private func persist() {
        defaults.set(collapsedNodeKeys.sorted(), forKey: key)
    }
}

private struct CollapseToggleButton: View {
    let isCollapsed: Bool
    let isSearchActive: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                action()
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSearchActive)
        .opacity(isSearchActive ? 0.5 : 1)
        .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
    }
}

// MARK: - Descendant counting

private func descendantCount(of locationId: String, in home: HomeDetail) -> (locations: Int, items: Int) {
    let directChildren = home.children(of: locationId)
    let directItems = home.items(in: locationId).count
    var totalLocs = directChildren.count
    var totalItems = directItems
    for child in directChildren {
        let sub = descendantCount(of: child.id, in: home)
        totalLocs += sub.locations
        totalItems += sub.items
    }
    return (totalLocs, totalItems)
}

private func collapsedSummary(
    locationCount: Int,
    itemCount: Int,
    locationSingular: String,
    locationPlural: String
) -> String {
    let locationText = locationCount == 1 ? "1 \(locationSingular)" : "\(locationCount) \(locationPlural)"
    let itemText = itemCount == 1 ? "1 item" : "\(itemCount) items"

    switch (locationCount, itemCount) {
    case (0, 0):
        return "Empty"
    case (0, _):
        return itemText
    case (_, 0):
        return locationText
    default:
        return "\(locationText), \(itemText)"
    }
}

// MARK: - Drop zone between homes for reorder

struct HomeDropZone: View {
    let insertionIndex: Int
    @ObservedObject var homeStore: HomeStore
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: isTargeted ? 4 : 2)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .dropDestination(for: DraggedHome.self) { items, _ in
                guard let dragged = items.first else { return false }
                homeStore.reorderHome(dragged.id, toIndex: insertionIndex)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Drop zone between locations for reorder/re-parent

private struct LocationDropZone: View {
    let homeId: String
    let parentId: String?
    let insertionIndex: Int
    @ObservedObject var homeStore: HomeStore
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: isTargeted ? 4 : 1)
            .padding(.horizontal, 8)
            .padding(.vertical, isTargeted ? 4 : 2)
            .contentShape(Rectangle())
            .dropDestination(for: DraggedLocation.self) { items, _ in
                guard let dragged = items.first else { return false }
                if dragged.homeId == homeId && dragged.parentId == parentId {
                    homeStore.reorderLocation(homeId: homeId, locationId: dragged.id, toIndex: insertionIndex)
                } else if dragged.homeId == homeId {
                    homeStore.moveLocationToParent(homeId: homeId, locationId: dragged.id, newParentId: parentId, atIndex: insertionIndex)
                } else {
                    homeStore.moveLocationAcrossHomes(fromHomeId: dragged.homeId, locationId: dragged.id, toHomeId: homeId, newParentId: parentId, atIndex: insertionIndex)
                }
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Inline rename header

private struct RenameableHeader: View {
    let name: String
    let icon: String
    let font: Font
    @Binding var isRenaming: Bool
    @Binding var renameName: String
    let onCommit: (String) -> Void

    var body: some View {
        if isRenaming {
            HStack(spacing: 6) {
                Image(systemName: icon)
                TextField("Name", text: $renameName, onCommit: {
                    let trimmed = renameName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onCommit(trimmed) }
                    isRenaming = false
                })
                .font(font)
                .textFieldStyle(.roundedBorder)

                Button {
                    isRenaming = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label(name, systemImage: icon)
                .font(font)
        }
    }
}

// MARK: - Breadcrumb path builder

private func breadcrumbPath(for locationId: String?, homeName: String, locations: [Location]) -> [String] {
    var path = [homeName]
    guard let locId = locationId else { return path }

    // Walk up from location to root
    var ancestors: [String] = []
    var currentId: String? = locId
    while let id = currentId, let loc = locations.first(where: { $0.id == id }) {
        ancestors.append(loc.name)
        currentId = loc.parentId
    }
    path.append(contentsOf: ancestors.reversed())
    return path
}

// MARK: - Home box (outermost)

struct HomeBoxView: View {
    let home: HomeDetail
    @ObservedObject var homeStore: HomeStore
    @ObservedObject var collapseStore: HierarchyCollapseStore
    let isSearchActive: Bool
    @State private var isAddingFloor = false
    @State private var isAddingRoom = false
    @State private var isAddingItem = false
    @State private var newName = ""
    @State private var newItemName = ""
    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var renameName = ""
    @State private var showIconPicker = false
    @State private var selectedIcon = ""
    @State private var showDeleteConfirm = false

    private var currentIcon: String {
        customIcon(home.icon, fallback: "house.fill")
    }

    private var hasDescendants: Bool {
        !home.locations.isEmpty || !home.items.isEmpty
    }

    private var collapseNode: CollapsibleTreeNode {
        .home(home.id)
    }

    private var isCollapsed: Bool {
        !isSearchActive && collapseStore.isCollapsed(collapseNode)
    }

    private var collapsedSummaryText: String {
        collapsedSummary(
            locationCount: home.locations.count,
            itemCount: home.items.count,
            locationSingular: "location",
            locationPlural: "locations"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                CollapseToggleButton(
                    isCollapsed: isCollapsed,
                    isSearchActive: isSearchActive,
                    title: home.name
                ) {
                    collapseStore.toggle(collapseNode)
                }

                RenameableHeader(
                    name: home.name,
                    icon: currentIcon,
                    font: .title3.bold(),
                    isRenaming: $isRenaming,
                    renameName: $renameName
                ) { newName in
                    Task { await homeStore.renameHome(home.id, name: newName) }
                }
                .draggable(DraggedHome(id: home.id))
                Spacer()
                if isCollapsed {
                    Text(collapsedSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isRenaming {
                    Menu {
                        Button { renameName = home.name; isRenaming = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button { selectedIcon = currentIcon; showIconPicker = true } label: {
                            Label("Change Icon", systemImage: "star.square")
                        }
                        Divider()
                        Button {
                            collapseStore.setCollapsed(false, for: collapseNode)
                            newName = ""
                            isAddingFloor = true
                        } label: {
                            Label("Add Floor", systemImage: "plus")
                        }
                        Button {
                            collapseStore.setCollapsed(false, for: collapseNode)
                            newName = ""
                            isAddingRoom = true
                        } label: {
                            Label("Add Room", systemImage: "plus")
                        }
                        Divider()
                        Button(role: .destructive) {
                            if hasDescendants { showDeleteConfirm = true }
                            else { Task { await homeStore.deleteHome(home.id) } }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if !isCollapsed {
                Divider().padding(.horizontal, 14)

                // Child locations
                LocationDropZone(homeId: home.id, parentId: nil, insertionIndex: 0, homeStore: homeStore)
                ForEach(Array(home.topLevelLocations.enumerated()), id: \.element.id) { index, location in
                    switch location.type {
                    case .floor:
                        FloorBoxView(
                            floor: location,
                            home: home,
                            homeStore: homeStore,
                            collapseStore: collapseStore,
                            isSearchActive: isSearchActive
                        )
                            .padding(.horizontal, 10)
                    case .room:
                        RoomBoxView(
                            room: location,
                            home: home,
                            homeStore: homeStore,
                            collapseStore: collapseStore,
                            isSearchActive: isSearchActive
                        )
                            .padding(.horizontal, 10)
                    case .container:
                        ContainerBoxView(
                            container: location,
                            home: home,
                            homeStore: homeStore,
                            collapseStore: collapseStore,
                            isSearchActive: isSearchActive
                        )
                            .padding(.horizontal, 10)
                    }
                    LocationDropZone(homeId: home.id, parentId: nil, insertionIndex: index + 1, homeStore: homeStore)
                }

                // Items after containers
                let homeItems = home.items(in: nil)
                ItemChipsView(items: homeItems, homeStore: homeStore, homeId: home.id, locationId: nil) {
                    newItemName = ""
                    isAddingItem = true
                }
                .padding(.horizontal, 14)

                // Inline add fields
                if isAddingFloor {
                    InlineAddField(placeholder: "Floor name", text: $newName) {
                        let name = newName
                        newName = ""; isAddingFloor = false
                        Task { await homeStore.createLocation(homeId: home.id, name: name, parentId: nil, type: "floor") }
                    } onCancel: { newName = ""; isAddingFloor = false }
                    .padding(.horizontal, 14).padding(.top, 8)
                }
                if isAddingRoom {
                    InlineAddField(placeholder: "Room name", text: $newName) {
                        let name = newName
                        newName = ""; isAddingRoom = false
                        Task { await homeStore.createLocation(homeId: home.id, name: name, parentId: nil, type: "room") }
                    } onCancel: { newName = ""; isAddingRoom = false }
                    .padding(.horizontal, 14).padding(.top, 8)
                }
                if isAddingItem {
                    InlineAddField(placeholder: "Item name", text: $newItemName) {
                        let name = newItemName
                        newItemName = ""; isAddingItem = false
                        Task { await homeStore.createItem(homeId: homeId, name: name, locationId: nil) }
                    } onCancel: { newItemName = ""; isAddingItem = false }
                    .padding(.horizontal, 14).padding(.top, 8)
                }
            }
        }
        .padding(.bottom, 10)
        .background(
            GeometryReader { geo in
                Color.homeBox
                    .preference(key: BreadcrumbPreferenceKey.self, value: [
                        BreadcrumbAnchor(path: [home.name], minY: geo.frame(in: .named("scroll")).minY)
                    ])
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isDropTargeted ? Color.accentColor : Color.homeBorder, lineWidth: isDropTargeted ? 2 : 0.75)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 14, y: 4)
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            Task { await homeStore.moveItem(homeId: home.id, itemId: dragged.id, toLocation: nil) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
                .onDisappear {
                    if !selectedIcon.isEmpty && selectedIcon != currentIcon {
                        homeStore.updateHomeIcon(home.id, icon: selectedIcon)
                    }
                }
        }
        .alert("Delete \(home.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await homeStore.deleteHome(home.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all rooms, containers, and items inside this home.")
        }
    }

    private var homeId: String { home.id }
}

// MARK: - Floor box

struct FloorBoxView: View {
    let floor: Location
    let home: HomeDetail
    @ObservedObject var homeStore: HomeStore
    @ObservedObject var collapseStore: HierarchyCollapseStore
    let isSearchActive: Bool
    @State private var isAddingRoom = false
    @State private var isAddingItem = false
    @State private var newName = ""
    @State private var newItemName = ""
    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var renameName = ""
    @State private var showIconPicker = false
    @State private var selectedIcon = ""
    @State private var showDeleteConfirm = false

    private var currentIcon: String {
        customIcon(floor.icon, fallback: defaultIcon(for: .floor, name: floor.name))
    }

    private var hasDescendants: Bool {
        let d = descendantCount(of: floor.id, in: home)
        return d.locations > 0 || d.items > 0
    }

    private var collapseNode: CollapsibleTreeNode {
        .location(floor.id)
    }

    private var isCollapsed: Bool {
        !isSearchActive && collapseStore.isCollapsed(collapseNode)
    }

    private var collapsedSummaryText: String {
        let d = descendantCount(of: floor.id, in: home)
        return collapsedSummary(
            locationCount: d.locations,
            itemCount: d.items,
            locationSingular: "location",
            locationPlural: "locations"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                CollapseToggleButton(
                    isCollapsed: isCollapsed,
                    isSearchActive: isSearchActive,
                    title: floor.name
                ) {
                    collapseStore.toggle(collapseNode)
                }

                RenameableHeader(
                    name: floor.name, icon: currentIcon, font: .headline,
                    isRenaming: $isRenaming, renameName: $renameName
                ) { newName in
                    Task { await homeStore.renameLocation(homeId: home.id, locationId: floor.id, name: newName) }
                }
                .draggable(DraggedLocation(id: floor.id, homeId: home.id, parentId: floor.parentId))
                Spacer()
                if isCollapsed {
                    Text(collapsedSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isRenaming {
                    Menu {
                        Button { renameName = floor.name; isRenaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button { selectedIcon = currentIcon; showIconPicker = true } label: { Label("Change Icon", systemImage: "star.square") }
                        Divider()
                        Button {
                            collapseStore.setCollapsed(false, for: collapseNode)
                            newName = ""
                            isAddingRoom = true
                        } label: { Label("Add Room", systemImage: "plus") }
                        Divider()
                        Button { homeStore.sortItemsByName(homeId: home.id, locationId: floor.id) } label: { Label("Order items by name", systemImage: "textformat.abc") }
                        Button { homeStore.sortChildLocationsByName(homeId: home.id, parentId: floor.id) } label: { Label("Order rooms by name", systemImage: "arrow.up.arrow.down") }
                        Divider()
                        Button(role: .destructive) {
                            if hasDescendants { showDeleteConfirm = true }
                            else { Task { await homeStore.deleteLocation(homeId: home.id, locationId: floor.id) } }
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").font(.caption.bold()).foregroundStyle(.secondary).padding(6) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .dropDestination(for: DraggedLocation.self) { items, _ in
                guard let dragged = items.first, dragged.id != floor.id else { return false }
                if dragged.homeId == home.id {
                    homeStore.moveLocationToParent(homeId: home.id, locationId: dragged.id, newParentId: floor.id, atIndex: home.children(of: floor.id).count)
                } else {
                    homeStore.moveLocationAcrossHomes(fromHomeId: dragged.homeId, locationId: dragged.id, toHomeId: home.id, newParentId: floor.id, atIndex: home.children(of: floor.id).count)
                }
                return true
            }
            if !isCollapsed {
                Divider().padding(.horizontal, 12)

                // Child locations
                LocationDropZone(homeId: home.id, parentId: floor.id, insertionIndex: 0, homeStore: homeStore)
                ForEach(Array(home.children(of: floor.id).enumerated()), id: \.element.id) { index, child in
                    switch child.type {
                    case .room:
                        RoomBoxView(
                            room: child,
                            home: home,
                            homeStore: homeStore,
                            collapseStore: collapseStore,
                            isSearchActive: isSearchActive
                        )
                            .padding(.horizontal, 8)
                    default:
                        ContainerBoxView(
                            container: child,
                            home: home,
                            homeStore: homeStore,
                            collapseStore: collapseStore,
                            isSearchActive: isSearchActive
                        )
                            .padding(.horizontal, 8)
                    }
                    LocationDropZone(homeId: home.id, parentId: floor.id, insertionIndex: index + 1, homeStore: homeStore)
                }

                // Items after containers
                let floorItems = home.items(in: floor.id)
                ItemChipsView(items: floorItems, homeStore: homeStore, homeId: home.id, locationId: floor.id) {
                    newItemName = ""
                    isAddingItem = true
                }
                .padding(.horizontal, 12)

                if isAddingRoom {
                    InlineAddField(placeholder: "Room name", text: $newName) {
                        let name = newName; newName = ""; isAddingRoom = false
                        Task { await homeStore.createLocation(homeId: home.id, name: name, parentId: floor.id, type: "room") }
                    } onCancel: { newName = ""; isAddingRoom = false }
                    .padding(.horizontal, 12).padding(.top, 6)
                }
                if isAddingItem {
                    InlineAddField(placeholder: "Item name", text: $newItemName) {
                        let name = newItemName; newItemName = ""; isAddingItem = false
                        Task { await homeStore.createItem(homeId: home.id, name: name, locationId: floor.id) }
                    } onCancel: { newItemName = ""; isAddingItem = false }
                    .padding(.horizontal, 12).padding(.top, 6)
                }
            }
        }
        .padding(.bottom, 8)
        .background(
            GeometryReader { geo in
                Color.floorBox
                    .preference(key: BreadcrumbPreferenceKey.self, value: [
                        BreadcrumbAnchor(
                            path: breadcrumbPath(for: floor.id, homeName: home.name, locations: home.locations),
                            minY: geo.frame(in: .named("scroll")).minY
                        )
                    ])
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDropTargeted ? Color.accentColor : Color.floorBorder, lineWidth: isDropTargeted ? 2 : 0.75))
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            Task { await homeStore.moveItem(homeId: home.id, itemId: dragged.id, toLocation: floor.id) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
                .onDisappear {
                    if !selectedIcon.isEmpty && selectedIcon != currentIcon {
                        homeStore.updateLocationIcon(homeId: home.id, locationId: floor.id, icon: selectedIcon)
                    }
                }
        }
        .alert("Delete \(floor.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await homeStore.deleteLocation(homeId: home.id, locationId: floor.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let d = descendantCount(of: floor.id, in: home)
            Text("This will also delete \(d.locations) location(s) and \(d.items) item(s) inside.")
        }
    }
}

// MARK: - Room box

struct RoomBoxView: View {
    let room: Location
    let home: HomeDetail
    @ObservedObject var homeStore: HomeStore
    @ObservedObject var collapseStore: HierarchyCollapseStore
    let isSearchActive: Bool
    @State private var isAddingContainer = false
    @State private var isAddingItem = false
    @State private var newName = ""
    @State private var newItemName = ""
    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var renameName = ""
    @State private var showIconPicker = false
    @State private var selectedIcon = ""

    @State private var showDeleteConfirm = false

    private var currentIcon: String {
        customIcon(room.icon, fallback: defaultIcon(for: .room, name: room.name))
    }

    private var hasDescendants: Bool {
        let d = descendantCount(of: room.id, in: home)
        return d.locations > 0 || d.items > 0
    }

    private var collapseNode: CollapsibleTreeNode {
        .location(room.id)
    }

    private var isCollapsed: Bool {
        !isSearchActive && collapseStore.isCollapsed(collapseNode)
    }

    private var collapsedSummaryText: String {
        let d = descendantCount(of: room.id, in: home)
        return collapsedSummary(
            locationCount: d.locations,
            itemCount: d.items,
            locationSingular: "container",
            locationPlural: "containers"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                CollapseToggleButton(
                    isCollapsed: isCollapsed,
                    isSearchActive: isSearchActive,
                    title: room.name
                ) {
                    collapseStore.toggle(collapseNode)
                }

                RenameableHeader(
                    name: room.name, icon: currentIcon, font: .headline,
                    isRenaming: $isRenaming, renameName: $renameName
                ) { newName in
                    Task { await homeStore.renameLocation(homeId: home.id, locationId: room.id, name: newName) }
                }
                .draggable(DraggedLocation(id: room.id, homeId: home.id, parentId: room.parentId))
                Spacer()
                if isCollapsed {
                    Text(collapsedSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isRenaming {
                    Menu {
                        Button { renameName = room.name; isRenaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button { selectedIcon = currentIcon; showIconPicker = true } label: { Label("Change Icon", systemImage: "star.square") }
                        Divider()
                        Button {
                            collapseStore.setCollapsed(false, for: collapseNode)
                            newName = ""
                            isAddingContainer = true
                        } label: { Label("Add Container", systemImage: "plus") }
                        Divider()
                        Button { homeStore.sortItemsByName(homeId: home.id, locationId: room.id) } label: { Label("Order items by name", systemImage: "textformat.abc") }
                        Button { homeStore.sortChildLocationsByName(homeId: home.id, parentId: room.id) } label: { Label("Order containers by name", systemImage: "arrow.up.arrow.down") }
                        Divider()
                        Button(role: .destructive) {
                            if hasDescendants { showDeleteConfirm = true }
                            else { Task { await homeStore.deleteLocation(homeId: home.id, locationId: room.id) } }
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").font(.caption.bold()).foregroundStyle(.secondary).padding(6) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .dropDestination(for: DraggedLocation.self) { items, _ in
                guard let dragged = items.first, dragged.id != room.id else { return false }
                // Drop onto room header = move container into this room
                if dragged.homeId == home.id {
                    homeStore.moveLocationToParent(homeId: home.id, locationId: dragged.id, newParentId: room.id, atIndex: home.children(of: room.id).count)
                } else {
                    homeStore.moveLocationAcrossHomes(fromHomeId: dragged.homeId, locationId: dragged.id, toHomeId: home.id, newParentId: room.id, atIndex: home.children(of: room.id).count)
                }
                return true
            }
            if !isCollapsed {
                Divider().padding(.horizontal, 12)

                // Child containers
                LocationDropZone(homeId: home.id, parentId: room.id, insertionIndex: 0, homeStore: homeStore)
                ForEach(Array(home.children(of: room.id).enumerated()), id: \.element.id) { index, container in
                    ContainerBoxView(
                        container: container,
                        home: home,
                        homeStore: homeStore,
                        collapseStore: collapseStore,
                        isSearchActive: isSearchActive
                    )
                        .padding(.horizontal, 8)
                    LocationDropZone(homeId: home.id, parentId: room.id, insertionIndex: index + 1, homeStore: homeStore)
                }

                // Items after containers
                let roomItems = home.items(in: room.id)
                ItemChipsView(items: roomItems, homeStore: homeStore, homeId: home.id, locationId: room.id) {
                    newItemName = ""
                    isAddingItem = true
                }
                .padding(.horizontal, 12)

                if isAddingContainer {
                    InlineAddField(placeholder: "Container name", text: $newName) {
                        let name = newName; newName = ""; isAddingContainer = false
                        Task { await homeStore.createLocation(homeId: home.id, name: name, parentId: room.id, type: "container") }
                    } onCancel: { newName = ""; isAddingContainer = false }
                    .padding(.horizontal, 12).padding(.top, 6)
                }
                if isAddingItem {
                    InlineAddField(placeholder: "Item name", text: $newItemName) {
                        let name = newItemName; newItemName = ""; isAddingItem = false
                        Task { await homeStore.createItem(homeId: home.id, name: name, locationId: room.id) }
                    } onCancel: { newItemName = ""; isAddingItem = false }
                    .padding(.horizontal, 12).padding(.top, 6)
                }
            }
        }
        .padding(.bottom, 8)
        .background(
            GeometryReader { geo in
                Color.roomBox
                    .preference(key: BreadcrumbPreferenceKey.self, value: [
                        BreadcrumbAnchor(
                            path: breadcrumbPath(for: room.id, homeName: home.name, locations: home.locations),
                            minY: geo.frame(in: .named("scroll")).minY
                        )
                    ])
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDropTargeted ? Color.accentColor : Color.roomBorder, lineWidth: isDropTargeted ? 2 : 0.75))
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            Task { await homeStore.moveItem(homeId: home.id, itemId: dragged.id, toLocation: room.id) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
                .onDisappear {
                    if !selectedIcon.isEmpty && selectedIcon != currentIcon {
                        homeStore.updateLocationIcon(homeId: home.id, locationId: room.id, icon: selectedIcon)
                    }
                }
        }
        .alert("Delete \(room.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await homeStore.deleteLocation(homeId: home.id, locationId: room.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let d = descendantCount(of: room.id, in: home)
            Text("This will also delete \(d.locations) container(s) and \(d.items) item(s) inside.")
        }
    }
}

// MARK: - Container box (nestable)

struct ContainerBoxView: View {
    let container: Location
    let home: HomeDetail
    @ObservedObject var homeStore: HomeStore
    @ObservedObject var collapseStore: HierarchyCollapseStore
    let isSearchActive: Bool
    @State private var isAddingChild = false
    @State private var isAddingItem = false
    @State private var newName = ""
    @State private var newItemName = ""
    @State private var isDropTargeted = false
    @State private var isRenaming = false
    @State private var renameName = ""
    @State private var showIconPicker = false
    @State private var selectedIcon = ""

    @State private var showDeleteConfirm = false

    private var currentIcon: String {
        customIcon(container.icon, fallback: defaultIcon(for: .container, name: container.name))
    }

    private var hasDescendants: Bool {
        let d = descendantCount(of: container.id, in: home)
        return d.locations > 0 || d.items > 0
    }

    private var collapseNode: CollapsibleTreeNode {
        .location(container.id)
    }

    private var isCollapsed: Bool {
        !isSearchActive && collapseStore.isCollapsed(collapseNode)
    }

    private var collapsedSummaryText: String {
        let d = descendantCount(of: container.id, in: home)
        return collapsedSummary(
            locationCount: d.locations,
            itemCount: d.items,
            locationSingular: "container",
            locationPlural: "containers"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CollapseToggleButton(
                    isCollapsed: isCollapsed,
                    isSearchActive: isSearchActive,
                    title: container.name
                ) {
                    collapseStore.toggle(collapseNode)
                }

                RenameableHeader(
                    name: container.name, icon: currentIcon, font: .subheadline.bold(),
                    isRenaming: $isRenaming, renameName: $renameName
                ) { newName in
                    Task { await homeStore.renameLocation(homeId: home.id, locationId: container.id, name: newName) }
                }
                .draggable(DraggedLocation(id: container.id, homeId: home.id, parentId: container.parentId))
                Spacer()
                if isCollapsed {
                    Text(collapsedSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !isRenaming {
                    Menu {
                        Button { renameName = container.name; isRenaming = true } label: { Label("Rename", systemImage: "pencil") }
                        Button { selectedIcon = currentIcon; showIconPicker = true } label: { Label("Change Icon", systemImage: "star.square") }
                        Divider()
                        Button {
                            collapseStore.setCollapsed(false, for: collapseNode)
                            newName = ""
                            isAddingChild = true
                        } label: { Label("Add Container", systemImage: "plus") }
                        Divider()
                        Button { homeStore.sortItemsByName(homeId: home.id, locationId: container.id) } label: { Label("Order items by name", systemImage: "textformat.abc") }
                        Button { homeStore.sortChildLocationsByName(homeId: home.id, parentId: container.id) } label: { Label("Order containers by name", systemImage: "arrow.up.arrow.down") }
                        Divider()
                        Button(role: .destructive) {
                            if hasDescendants { showDeleteConfirm = true }
                            else { Task { await homeStore.deleteLocation(homeId: home.id, locationId: container.id) } }
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary).padding(6) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)

            if !isCollapsed {
                // Nested containers
                LocationDropZone(homeId: home.id, parentId: container.id, insertionIndex: 0, homeStore: homeStore)
                ForEach(Array(home.children(of: container.id).enumerated()), id: \.element.id) { index, child in
                    ContainerBoxView(
                        container: child,
                        home: home,
                        homeStore: homeStore,
                        collapseStore: collapseStore,
                        isSearchActive: isSearchActive
                    )
                        .padding(.horizontal, 6)
                    LocationDropZone(homeId: home.id, parentId: container.id, insertionIndex: index + 1, homeStore: homeStore)
                }

                // Items after containers
                let containerItems = home.items(in: container.id)
                ItemChipsView(items: containerItems, homeStore: homeStore, homeId: home.id, locationId: container.id) {
                    newItemName = ""
                    isAddingItem = true
                }
                .padding(.horizontal, 10)

                if isAddingChild {
                    InlineAddField(placeholder: "Container name", text: $newName) {
                        let name = newName; newName = ""; isAddingChild = false
                        Task { await homeStore.createLocation(homeId: home.id, name: name, parentId: container.id, type: "container") }
                    } onCancel: { newName = ""; isAddingChild = false }
                    .padding(.horizontal, 10).padding(.top, 4)
                }
                if isAddingItem {
                    InlineAddField(placeholder: "Item name", text: $newItemName) {
                        let name = newItemName; newItemName = ""; isAddingItem = false
                        Task { await homeStore.createItem(homeId: home.id, name: name, locationId: container.id) }
                    } onCancel: { newItemName = ""; isAddingItem = false }
                    .padding(.horizontal, 10).padding(.top, 4)
                }
            }
        }
        .padding(.bottom, 6)
        .background(
            GeometryReader { geo in
                Color.containerBox
                    .preference(key: BreadcrumbPreferenceKey.self, value: [
                        BreadcrumbAnchor(
                            path: breadcrumbPath(for: container.id, homeName: home.name, locations: home.locations),
                            minY: geo.frame(in: .named("scroll")).minY
                        )
                    ])
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDropTargeted ? Color.accentColor : Color.containerBorder, lineWidth: isDropTargeted ? 2 : 0.5))
        .dropDestination(for: DraggedItem.self) { items, _ in
            guard let dragged = items.first else { return false }
            Task { await homeStore.moveItem(homeId: home.id, itemId: dragged.id, toLocation: container.id) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
                .onDisappear {
                    if !selectedIcon.isEmpty && selectedIcon != currentIcon {
                        homeStore.updateLocationIcon(homeId: home.id, locationId: container.id, icon: selectedIcon)
                    }
                }
        }
        .alert("Delete \(container.name)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await homeStore.deleteLocation(homeId: home.id, locationId: container.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let d = descendantCount(of: container.id, in: home)
            Text("This will also delete \(d.locations) container(s) and \(d.items) item(s) inside.")
        }
    }
}
