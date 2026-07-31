import SwiftUI

struct TrashBinView: View {
    @ObservedObject var homeStore: HomeStore
    @State private var isExpanded = false

    var body: some View {
        let deleted = homeStore.deletedItems
        if !deleted.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 6) {
                    ForEach(deleted, id: \.item.id) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.item.icon ?? "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.item.name)
                                    .font(.callout)
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Text(entry.homeName)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button {
                                withAnimation {
                                    homeStore.restoreItem(itemId: entry.item.id)
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 44)
                                    .cubbyWoodButtonSurface()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(CubbyTheme.paper.opacity(0.88))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CubbyTheme.containerBorder, lineWidth: 0.75)
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("Recently Deleted (\(deleted.count))", systemImage: "trash")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(CubbyTheme.mutedInk)
            }
            .tint(CubbyTheme.green)
            .padding(14)
            .background(CubbyTheme.paper.opacity(0.74), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CubbyTheme.floorBorder.opacity(0.72), lineWidth: 0.75)
            }
        }
    }
}
