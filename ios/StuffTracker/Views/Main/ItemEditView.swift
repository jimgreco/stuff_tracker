import SwiftUI

struct ItemEditView: View {
    let item: Item
    @ObservedObject var homeStore: HomeStore
    let homeId: String
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var quantity: Int
    @State private var tags: String          // comma-separated
    @State private var purchaseDate: Date?
    @State private var hasPurchaseDate: Bool
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
        _tags = State(initialValue: item.tags.joined(separator: ", "))
        _selectedLocationId = State(initialValue: item.locationId)
        _selectedIcon = State(initialValue: item.icon ?? "")
        let pd = item.purchaseDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        _purchaseDate = State(initialValue: pd)
        _hasPurchaseDate = State(initialValue: pd != nil)
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
                    LocationPicker(
                        selectedId: $selectedLocationId,
                        home: home
                    )
                }

                Section("Optional") {
                    TextField("Tags (comma-separated)", text: $tags)

                    Toggle("Purchase date", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Date", selection: Binding(
                            get: { purchaseDate ?? Date() },
                            set: { purchaseDate = $0 }
                        ), displayedComponents: .date)
                    }
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
        let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let dateStr = hasPurchaseDate ? purchaseDate.map { ISO8601DateFormatter().string(from: $0) } : nil
        let body = APIClient.ItemBody(
            name: name,
            locationId: selectedLocationId,
            icon: selectedIcon.isEmpty ? nil : selectedIcon,
            notes: notes.isEmpty ? nil : notes,
            quantity: quantity,
            tags: parsedTags,
            photoUrl: item.photoUrl,
            purchaseDate: dateStr ?? nil
        )
        Task {
            await homeStore.updateItem(homeId: homeId, itemId: item.id, body: body)
            dismiss()
        }
    }
}

// MARK: - Location picker

struct LocationPicker: View {
    @Binding var selectedId: String?
    let home: HomeDetail?

    var body: some View {
        Picker("Location", selection: $selectedId) {
            Text("Home (no specific location)").tag(String?.none)
            if let home {
                ForEach(home.locations.sorted { $0.sortOrder < $1.sortOrder }) { loc in
                    Text(locationLabel(loc, in: home.locations))
                        .tag(Optional(loc.id))
                }
            }
        }
        .pickerStyle(.navigationLink)
    }

    private func locationLabel(_ loc: Location, in locations: [Location]) -> String {
        var parts = [loc.name]
        var current = loc
        while let parentId = current.parentId,
              let parent = locations.first(where: { $0.id == parentId }) {
            parts.insert(parent.name, at: 0)
            current = parent
        }
        return parts.joined(separator: " › ")
    }
}
