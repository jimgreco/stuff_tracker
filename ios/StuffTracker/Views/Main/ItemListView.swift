import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTTypes for drag-and-drop

extension UTType {
    static let draggedItem = UTType(exportedAs: "com.stufftracker.draggeditem", conformingTo: .data)
    static let draggedLocation = UTType(exportedAs: "com.stufftracker.draggedlocation", conformingTo: .data)
    static let draggedHome = UTType(exportedAs: "com.stufftracker.draggedhome", conformingTo: .data)
}

// MARK: - Transferable for drag-and-drop

struct DraggedItem: Transferable, Codable {
    let id: String
    let name: String
    let homeId: String?
    let itemIds: [String]

    init(id: String, name: String, homeId: String? = nil, itemIds: [String]? = nil) {
        self.id = id
        self.name = name
        self.homeId = homeId

        let rawIds = itemIds ?? [id]
        var seen = Set<String>()
        let uniqueIds = rawIds.filter { seen.insert($0).inserted }
        self.itemIds = uniqueIds.isEmpty ? [id] : uniqueIds
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggedItem)
    }
}

struct DraggedLocation: Transferable, Codable {
    let id: String
    let homeId: String
    let parentId: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggedLocation)
    }
}

struct DraggedHome: Transferable, Codable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggedHome)
    }
}

@MainActor
final class ItemSelectionController: ObservableObject {
    @Published private(set) var isSelecting = false
    @Published private(set) var selectedItemIds: [String] = []
    @Published private(set) var selectedHomeId: String?

    var selectedCount: Int {
        selectedItemIds.count
    }

    func startSelecting() {
        isSelecting = true
        selectedItemIds = []
        selectedHomeId = nil
    }

    func clearSelection() {
        isSelecting = false
        selectedItemIds = []
        selectedHomeId = nil
    }

    func toggle(itemId: String, homeId: String) {
        guard isSelecting else { return }

        if selectedItemIds.contains(itemId) {
            selectedItemIds.removeAll { $0 == itemId }
            if selectedItemIds.isEmpty {
                selectedHomeId = nil
            }
            return
        }

        if let selectedHomeId, selectedHomeId != homeId {
            selectedItemIds = [itemId]
            self.selectedHomeId = homeId
            return
        }

        selectedHomeId = homeId
        selectedItemIds.append(itemId)
    }

    func isSelected(_ itemId: String) -> Bool {
        isSelecting && selectedItemIds.contains(itemId)
    }

    func dragItemIds(for itemId: String, homeId: String) -> [String] {
        guard isSelecting,
              selectedHomeId == homeId,
              selectedItemIds.contains(itemId),
              !selectedItemIds.isEmpty else {
            return [itemId]
        }

        return selectedItemIds
    }

    func prune(validItemIds: Set<String>) {
        selectedItemIds = selectedItemIds.filter { validItemIds.contains($0) }
        if selectedItemIds.isEmpty {
            selectedHomeId = nil
        }
    }
}

// MARK: - Flowing item chips

struct ItemChipsView: View {
    let items: [Item]
    @ObservedObject var homeStore: HomeStore
    var homeId: String = ""
    let locationId: String?
    var onAddItem: (() -> Void)? = nil
    @EnvironmentObject private var itemSelection: ItemSelectionController

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemChip(item: item, homeStore: homeStore, homeId: homeId)
                    .dropDestination(for: DraggedItem.self) { dropped, _ in
                        guard let dragged = dropped.first, dragged.id != item.id else { return false }
                        return dropItem(dragged, at: index)
                    }
                    .overlay(alignment: .leading) {
                        ItemInsertionDropZone(edge: .leading, insertionIndex: index) { dragged, insertionIndex in
                            dropItem(dragged, at: insertionIndex)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        ItemInsertionDropZone(edge: .trailing, insertionIndex: index + 1) { dragged, insertionIndex in
                            dropItem(dragged, at: insertionIndex)
                        }
                    }
            }

            if let onAddItem {
                AddItemChip(action: onAddItem)
            }
        }
    }

    private func dropItem(_ dragged: DraggedItem, at insertionIndex: Int) -> Bool {
        guard !homeId.isEmpty else { return false }

        let movingIds = dragged.itemIds
        let destination = adjustedDestination(for: movingIds, insertionIndex: insertionIndex)

        withAnimation(.easeInOut(duration: 0.18)) {
            if dragged.homeId == nil || dragged.homeId == homeId,
               movingIds.count == 1,
               let itemId = movingIds.first,
               items.contains(where: { $0.id == itemId }) {
                homeStore.reorderItem(homeId: homeId, itemId: itemId, toIndex: destination)
            } else {
                homeStore.moveItems(homeId: homeId, itemIds: movingIds, toLocation: locationId, atIndex: destination, fromHomeId: dragged.homeId)
            }
        }
        itemSelection.clearSelection()

        return true
    }

    private func adjustedDestination(for movingIds: [String], insertionIndex: Int) -> Int {
        let movingSet = Set(movingIds)
        let movedBeforeDestination = items
            .prefix(insertionIndex)
            .filter { movingSet.contains($0.id) }
            .count

        return insertionIndex - movedBeforeDestination
    }
}

private struct AddItemChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))

                Text("Add item")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .addItemChipSurface()
        .contentShape(Rectangle())
        .accessibilityLabel("Add item")
    }
}

private struct AddItemChipSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .foregroundStyle(Color.white)
                .background { CubbyWoodButtonFill(shape: shape) }
                .overlay(shape.stroke(CubbyTheme.darkWoodBottom.opacity(0.85), lineWidth: 0.5))
        } else {
            content
                .foregroundStyle(Color.white)
                .background { CubbyWoodButtonFill(shape: shape) }
                .overlay(shape.stroke(CubbyTheme.darkWoodBottom.opacity(0.85), lineWidth: 0.5))
        }
    }
}

private extension View {
    func addItemChipSurface() -> some View {
        modifier(AddItemChipSurfaceModifier())
    }
}

private enum ItemInsertionEdge {
    case leading
    case trailing
}

private struct ItemInsertionDropZone: View {
    let edge: ItemInsertionEdge
    let insertionIndex: Int
    let onDrop: (DraggedItem, Int) -> Bool

    @State private var isTargeted = false

    private let hitWidth: CGFloat = 34
    private let hitHeight: CGFloat = 42
    private let insideOverlap: CGFloat = 6
    private let lineOutset: CGFloat = 3

    private var alignment: Alignment {
        edge == .leading ? .trailing : .leading
    }

    private var paddingEdge: Edge.Set {
        edge == .leading ? .trailing : .leading
    }

    private var xOffset: CGFloat {
        edge == .leading ? -(hitWidth - insideOverlap) : hitWidth - insideOverlap
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear

            ZStack {
                Capsule()
                    .fill(CubbyTheme.green.opacity(isTargeted ? 0.16 : 0))
                    .frame(width: 12, height: 32)

                Capsule()
                    .fill(CubbyTheme.green.opacity(isTargeted ? 1 : 0))
                    .frame(width: 3, height: 28)
            }
            .padding(paddingEdge, insideOverlap + lineOutset)
        }
        .frame(width: hitWidth, height: hitHeight)
        .contentShape(Rectangle())
        .offset(x: xOffset)
        .dropDestination(for: DraggedItem.self) { dropped, _ in
            guard let dragged = dropped.first else { return false }
            return onDrop(dragged, insertionIndex)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    init(spacing: CGFloat = 6) {
        horizontalSpacing = spacing
        verticalSpacing = spacing
    }

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + horizontalSpacing
            maxX = max(maxX, x - horizontalSpacing)
        }

        return ArrangeResult(
            positions: positions,
            sizes: sizes,
            size: CGSize(width: maxX, height: y + rowHeight)
        )
    }
}

// MARK: - Item chip

struct ItemChip: View {
    let item: Item
    @ObservedObject var homeStore: HomeStore
    var homeId: String = ""
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var itemSelection: ItemSelectionController
    @State private var showEdit = false

    private var showUnsyncedOutline: Bool {
        authStore.isAuthenticated && item.needsSync
    }

    private var isSelected: Bool {
        itemSelection.isSelected(item.id)
    }

    var body: some View {
        HStack(spacing: 4) {
            if item.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CubbyTheme.amber)
                    .accessibilityLabel("Flagged")
            }

            Image(systemName: item.icon ?? "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.icon != nil ? .primary : CubbyTheme.green.opacity(0.36))

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)

            if item.quantity > 1 {
                Text("\u{00d7}\(item.quantity)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CubbyTheme.green)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .id(ItemDeepLink.itemAnchorID(item.id))
        .itemChipSurface(showUnsyncedOutline: showUnsyncedOutline, isSelected: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            if itemSelection.isSelecting {
                itemSelection.toggle(itemId: item.id, homeId: homeId)
            } else {
                showEdit = true
            }
        }
        .draggable(
            DraggedItem(
                id: item.id,
                name: item.name,
                homeId: homeId,
                itemIds: itemSelection.dragItemIds(for: item.id, homeId: homeId)
            )
        )
        .sheet(isPresented: $showEdit) {
            ItemEditView(item: item, homeStore: homeStore, homeId: homeId)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ItemChipSurfaceModifier: ViewModifier {
    let showUnsyncedOutline: Bool
    let isSelected: Bool

    private var strokeStyle: StrokeStyle {
        showUnsyncedOutline && !isSelected ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: isSelected ? 1.25 : 0.5)
    }

    private var strokeColor: Color {
        if isSelected {
            return CubbyTheme.green
        }
        return showUnsyncedOutline ? CubbyTheme.amber : CubbyTheme.containerBorder
    }

    private var backgroundColor: Color {
        if isSelected {
            return CubbyTheme.green.opacity(0.16)
        }
        return CubbyTheme.paper.opacity(0.84)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(isSelected ? CubbyTheme.green.opacity(0.14) : CubbyTheme.paper.opacity(0.62), in: shape)
                .overlay(shape.stroke(strokeColor, style: strokeStyle))
        } else {
            content
                .background(backgroundColor, in: shape)
                .overlay(shape.stroke(strokeColor, style: strokeStyle))
        }
    }
}

private extension View {
    func itemChipSurface(showUnsyncedOutline: Bool, isSelected: Bool) -> some View {
        modifier(ItemChipSurfaceModifier(showUnsyncedOutline: showUnsyncedOutline, isSelected: isSelected))
    }
}
