import SwiftUI

struct PendingChangesView: View {
    let homeStore: HomeStore
    private let local = LocalDataManager.shared

    var body: some View {
        List {
            let pendingHomes = local.fetchHomes().filter { $0.needsSync }
            let pendingLocations = local.fetchPendingLocations()
            let pendingItems = local.fetchPendingItems()
            let deletedHomes = local.fetchDeletedHomes()
            let deletedLocations = local.fetchDeletedLocations()
            let deletedItems = local.fetchDeletedItems()

            if !pendingHomes.isEmpty {
                Section("Homes") {
                    ForEach(pendingHomes, id: \.id) { home in
                        Label(home.name, systemImage: "house.fill")
                    }
                }
            }

            if !pendingLocations.isEmpty {
                Section("Locations") {
                    ForEach(pendingLocations, id: \.id) { loc in
                        HStack {
                            Label(loc.name, systemImage: locationIcon(for: loc.type))
                            Spacer()
                            Text(loc.type.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !pendingItems.isEmpty {
                Section("Items") {
                    ForEach(pendingItems, id: \.id) { item in
                        Label(item.name, systemImage: item.icon ?? "circle.fill")
                    }
                }
            }

            let totalDeleted = deletedHomes.count + deletedLocations.count + deletedItems.count
            if totalDeleted > 0 {
                Section("Pending Deletes") {
                    ForEach(deletedHomes, id: \.id) { home in
                        Label(home.name, systemImage: "house.fill")
                            .foregroundStyle(.red)
                    }
                    ForEach(deletedLocations, id: \.id) { loc in
                        Label(loc.name, systemImage: locationIcon(for: loc.type))
                            .foregroundStyle(.red)
                    }
                    ForEach(deletedItems, id: \.id) { item in
                        Label(item.name, systemImage: item.icon ?? "circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Pending Changes")
        .navigationBarTitleDisplayMode(.inline)
        .cubbyNavigationBarChrome()
    }

    private func locationIcon(for type: String) -> String {
        switch type {
        case "floor": return "building.2"
        case "room": return "door.left.hand.closed"
        default: return "square.stack.3d.up"
        }
    }
}
