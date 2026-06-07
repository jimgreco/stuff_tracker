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
                                    .frame(minHeight: 30)
                                    .cubbyWoodButtonSurface()
                            }
                            .buttonStyle(.plain)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("Recently Deleted (\(deleted.count))", systemImage: "trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }
}
