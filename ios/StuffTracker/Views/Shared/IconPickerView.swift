import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    private let icons: [(String, [String])] = [
        ("Items", [
            "laptopcomputer", "iphone", "headphones", "keyboard",
            "printer.fill", "camera.fill", "guitars.fill", "paintbrush.fill",
            "wrench.fill", "hammer.fill", "scissors", "pencil",
            "book.fill", "newspaper.fill", "envelope.fill", "creditcard.fill",
            "cup.and.saucer.fill", "mug.fill", "wineglass.fill",
            "tshirt.fill", "shoe.fill", "eyeglasses",
            "lamp.desk.fill", "lightbulb.fill", "fan.fill",
            "pill.fill", "cross.case.fill", "pawprint.fill",
            "gift.fill", "key.fill", "lock.fill",
        ]),
        ("Buildings", [
            "house.fill", "house", "building.2", "building", "building.columns",
        ]),
        ("Rooms", [
            "door.left.hand.closed", "bed.double.fill", "bathtub.fill",
            "fork.knife", "tv.fill", "washer.fill", "refrigerator.fill",
            "fireplace.fill", "chair.lounge.fill", "toilet.fill",
        ]),
        ("Storage", [
            "shippingbox.fill", "archivebox.fill", "cabinet.fill",
            "books.vertical.fill", "rectangle.split.3x1.fill",
            "bag.fill", "suitcase.fill", "tray.full.fill",
        ]),
        ("Areas", [
            "car.fill", "bicycle", "leaf.fill", "tree.fill",
            "tent.fill", "figure.pool.swim",
            "dumbbell.fill", "gamecontroller.fill",
        ]),
        ("General", [
            "square.stack.3d.up.fill", "cube.fill", "cylinder.fill",
            "circle.fill", "triangle.fill", "star.fill",
            "heart.fill", "flag.fill", "tag.fill",
            "folder.fill", "tray.fill", "externaldrive.fill",
        ]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // "None" option to remove icon
                    Button {
                        selectedIcon = ""
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                                .font(.title3)
                            Text("No icon")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            selectedIcon.isEmpty
                                ? Color.accentColor.opacity(0.2)
                                : Color(.tertiarySystemBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .tint(.primary)

                    ForEach(icons, id: \.0) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.0)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(section.1, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.title2)
                                            .frame(width: 44, height: 44)
                                            .background(
                                                selectedIcon == icon
                                                    ? Color.accentColor.opacity(0.2)
                                                    : Color(.tertiarySystemBackground)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedIcon == icon ? Color.accentColor : .clear, lineWidth: 2)
                                            )
                                    }
                                    .tint(.primary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
