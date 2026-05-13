import SwiftUI

struct ItemEditView: View {
    let item: Item
    @ObservedObject var homeStore: HomeStore
    let homeId: String
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var quantity: Int
    @State private var selectedLocationId: String?
    @State private var isSaving = false
    @State private var selectedIcon: String
    @State private var showIconPicker = false

    init(item: Item, homeStore: HomeStore, homeId: String = "") {
        self.item = item
        self.homeStore = homeStore
        self.homeId = homeId
        _name = State(initialValue: item.name)
        _notes = State(initialValue: item.notes ?? "")
        _quantity = State(initialValue: item.quantity)
        _selectedLocationId = State(initialValue: item.locationId)
        _selectedIcon = State(initialValue: item.icon ?? "")
    }

    private var home: HomeDetail? {
        homeStore.homeDetails.first(where: { $0.id == homeId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)

                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedIcon.isEmpty {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: selectedIcon)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }

                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    LocationTreePicker(
                        selectedId: $selectedLocationId,
                        home: home
                    )
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        Task {
                            await homeStore.deleteItem(homeId: homeId, itemId: item.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
        }
    }

    private func save() {
        isSaving = true
        let body = APIClient.ItemBody(
            name: name,
            locationId: selectedLocationId,
            icon: selectedIcon.isEmpty ? nil : selectedIcon,
            notes: notes.isEmpty ? nil : notes,
            quantity: quantity,
            tags: item.tags,
            photoUrl: item.photoUrl,
            purchaseDate: item.purchaseDate
        )
        Task {
            await homeStore.updateItem(homeId: homeId, itemId: item.id, body: body)
            dismiss()
        }
    }
}

// MARK: - Tree-based location picker

enum LocationTreePresentation {
    static func selectedLabel(home: HomeDetail?, selectedId: String?) -> String {
        guard let home else { return "None" }
        guard let locId = selectedId,
              let loc = home.locations.first(where: { $0.id == locId }) else {
            return home.name
        }

        var parts = [loc.name]
        var current = loc
        while let parentId = current.parentId,
              let parent = home.locations.first(where: { $0.id == parentId }) {
            parts.insert(parent.name, at: 0)
            current = parent
        }
        return parts.joined(separator: " › ")
    }

    static func initialNavigationPath(home: HomeDetail, selectedId: String?) -> [String] {
        guard let locId = selectedId else { return [] }

        var ancestors: [String] = []
        var currentId: String? = locId
        while let id = currentId,
              let loc = home.locations.first(where: { $0.id == id }) {
            ancestors.insert(id, at: 0)
            currentId = loc.parentId
        }

        if !ancestors.isEmpty {
            ancestors.removeLast()
        }
        return ancestors
    }

    static func icon(for loc: Location) -> String {
        if let icon = loc.icon { return icon }
        switch loc.type {
        case .floor: return "building.2"
        case .room: return "door.left.hand.closed"
        case .container: return "square.stack.3d.up"
        }
    }
}

struct LocationTreePicker: View {
    @Binding var selectedId: String?
    let home: HomeDetail?
    @State private var showPicker = false

    private var selectedLabel: String {
        LocationTreePresentation.selectedLabel(home: home, selectedId: selectedId)
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Text("Location")
                    .foregroundStyle(.primary)
                Spacer()
                Text(selectedLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showPicker) {
            if let home {
                LocationTreeSheet(
                    home: home,
                    selectedId: $selectedId,
                    dismiss: { showPicker = false }
                )
            }
        }
    }
}

private struct LocationTreeSheet: View {
    let home: HomeDetail
    @Binding var selectedId: String?
    let dismiss: () -> Void
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            LocationTreeLevel(
                home: home,
                parentId: nil,
                selectedId: $selectedId,
                dismiss: dismiss
            )
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { locId in
                let loc = home.locations.first(where: { $0.id == locId })
                LocationTreeLevel(
                    home: home,
                    parentId: locId,
                    selectedId: $selectedId,
                    dismiss: dismiss
                )
                .navigationTitle(loc?.name ?? "")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            path = LocationTreePresentation.initialNavigationPath(home: home, selectedId: selectedId)
        }
    }
}

private struct LocationTreeLevel: View {
    let home: HomeDetail
    let parentId: String?
    @Binding var selectedId: String?
    let dismiss: () -> Void

    private var children: [Location] {
        home.locations
            .filter { $0.parentId == parentId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var currentName: String {
        if let parentId, let loc = home.locations.first(where: { $0.id == parentId }) {
            return loc.name
        }
        return home.name
    }

    var body: some View {
        List {
            // Option to select current level
            Button {
                selectedId = parentId
                dismiss()
            } label: {
                HStack {
                    Label(
                        parentId == nil ? "\(home.name) (top level)" : "Place here",
                        systemImage: parentId == nil ? (home.icon ?? "house.fill") : "checkmark.circle"
                    )
                    Spacer()
                    if selectedId == parentId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .foregroundStyle(.primary)

            if !children.isEmpty {
                Section {
                    ForEach(children) { loc in
                        let locChildren = home.locations.filter { $0.parentId == loc.id }
                        if locChildren.isEmpty {
                            // Leaf node - just select
                            Button {
                                selectedId = loc.id
                                dismiss()
                            } label: {
                                HStack {
                                    Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                                    Spacer()
                                    if selectedId == loc.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        } else {
                            // Has children - navigate deeper
                            NavigationLink(value: loc.id) {
                                HStack {
                                    Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                                    Spacer()
                                    if selectedId == loc.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
