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

// MARK: - Flowing item chips

struct ItemChipsView: View {
    let items: [Item]
    @ObservedObject var homeStore: HomeStore
    var homeId: String = ""
    let locationId: String?
    var onAddItem: (() -> Void)? = nil

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

        let destination = adjustedDestination(for: dragged, insertionIndex: insertionIndex)

        withAnimation(.easeInOut(duration: 0.18)) {
            if items.contains(where: { $0.id == dragged.id }) {
                homeStore.reorderItem(homeId: homeId, itemId: dragged.id, toIndex: destination)
            } else {
                homeStore.moveItem(homeId: homeId, itemId: dragged.id, toLocation: locationId)
                homeStore.reorderItem(homeId: homeId, itemId: dragged.id, toIndex: insertionIndex)
            }
        }

        return true
    }

    private func adjustedDestination(for dragged: DraggedItem, insertionIndex: Int) -> Int {
        guard let sourceIndex = items.firstIndex(where: { $0.id == dragged.id }) else {
            return insertionIndex
        }

        return sourceIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
    }
}

private struct AddItemChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.72))

                Text("Add item")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
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
                .background(Color.accentColor.opacity(0.045), in: shape)
                .overlay(shape.stroke(Color.accentColor.opacity(0.14), lineWidth: 0.5))
        } else {
            content
                .background(Color.accentColor.opacity(0.06), in: shape)
                .overlay(shape.stroke(Color.accentColor.opacity(0.16), lineWidth: 0.5))
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
                    .fill(Color.accentColor.opacity(isTargeted ? 0.16 : 0))
                    .frame(width: 12, height: 32)

                Capsule()
                    .fill(Color.accentColor.opacity(isTargeted ? 1 : 0))
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
    @State private var showEdit = false

    private var showUnsyncedOutline: Bool {
        authStore.isAuthenticated && item.needsSync
    }

    var body: some View {
        HStack(spacing: 4) {
            if item.isFlagged {
                Image(systemName: "flag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Flagged")
            }

            Image(systemName: item.icon ?? "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.icon != nil ? .primary : Color.accentColor.opacity(0.28))

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)

            if item.quantity > 1 {
                Text("\u{00d7}\(item.quantity)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .itemChipSurface(showUnsyncedOutline: showUnsyncedOutline)
        .contentShape(Rectangle())
        .onTapGesture { showEdit = true }
        .draggable(DraggedItem(id: item.id, name: item.name))
        .sheet(isPresented: $showEdit) {
            ItemEditView(item: item, homeStore: homeStore, homeId: homeId)
        }
    }
}

private struct ItemChipSurfaceModifier: ViewModifier {
    let showUnsyncedOutline: Bool

    private var strokeStyle: StrokeStyle {
        showUnsyncedOutline ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 0.5)
    }

    private var strokeColor: Color {
        showUnsyncedOutline ? .orange : Color(.separator).opacity(0.18)
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .background(Color(.systemBackground).opacity(0.52), in: shape)
                .overlay(shape.stroke(strokeColor, style: strokeStyle))
        } else {
            content
                .background(Color(.systemBackground).opacity(0.72), in: shape)
                .overlay(shape.stroke(strokeColor, style: strokeStyle))
        }
    }
}

private extension View {
    func itemChipSurface(showUnsyncedOutline: Bool) -> some View {
        modifier(ItemChipSurfaceModifier(showUnsyncedOutline: showUnsyncedOutline))
    }
}
