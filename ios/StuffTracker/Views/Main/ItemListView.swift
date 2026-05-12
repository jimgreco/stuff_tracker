import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTTypes for drag-and-drop

extension UTType {
    static let draggedItem = UTType(exportedAs: "com.stufftracker.draggeditem", conformingTo: .data)
    static let draggedLocation = UTType(exportedAs: "com.stufftracker.draggedlocation", conformingTo: .data)
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

// MARK: - Add-location action

struct AddLocationAction: Identifiable {
    let id = UUID()
    let label: String
    let action: () -> Void
}

// MARK: - Action buttons row (+ Add floor, + Add room, + Add item, etc.)

struct ActionButtonsRow: View {
    var addLocationActions: [AddLocationAction] = []
    var onAddItem: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(addLocationActions) { a in
                Button {
                    a.action()
                } label: {
                    Label(a.label, systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onAddItem()
            } label: {
                Label("Add item", systemImage: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Flowing item chips

struct ItemChipsView: View {
    let items: [Item]
    @ObservedObject var homeStore: HomeStore
    var homeId: String = ""
    let locationId: String?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ItemChip(item: item, homeStore: homeStore, homeId: homeId)
                    .dropDestination(for: DraggedItem.self) { dropped, _ in
                        guard let dragged = dropped.first, dragged.id != item.id else { return false }
                        homeStore.reorderItem(homeId: homeId, itemId: dragged.id, toIndex: index)
                        return true
                    }
            }
        }
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

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
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
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
            Image(systemName: item.icon ?? "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.icon != nil ? .primary : Color.accentColor.opacity(0.4))

            Text(item.name)
                .font(.callout)
                .lineLimit(1)

            if item.quantity > 1 {
                Text("\u{00d7}\(item.quantity)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    showUnsyncedOutline ? Color.orange : Color(.separator).opacity(0.4),
                    style: showUnsyncedOutline ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { showEdit = true }
        .draggable(DraggedItem(id: item.id, name: item.name))
        .sheet(isPresented: $showEdit) {
            ItemEditView(item: item, homeStore: homeStore, homeId: homeId)
        }
    }
}
