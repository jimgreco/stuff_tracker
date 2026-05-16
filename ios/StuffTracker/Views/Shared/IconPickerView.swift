import SwiftUI

private struct IconOption: Identifiable, Hashable {
    let name: String
    let terms: [String]

    var id: String { name }

    var searchText: String {
        ([name] + terms).joined(separator: " ").lowercased()
    }

    var label: String {
        let cleaned = name
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
        return cleaned
    }
}

private struct IconSection: Identifiable {
    let title: String
    let icons: [IconOption]

    var id: String { title }
}

private func icon(_ name: String, _ terms: String...) -> IconOption {
    IconOption(name: name, terms: terms)
}

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 12)]

    private let sections: [IconSection] = [
        IconSection(title: "Home", icons: [
            icon("house.fill", "home", "house"),
            icon("house", "home", "house"),
            icon("building.2.fill", "building", "apartment", "floor"),
            icon("building.2", "building", "apartment", "floor"),
            icon("building.fill", "building", "office"),
            icon("building.columns.fill", "bank", "formal", "columns"),
            icon("storefront.fill", "store", "shop"),
            icon("tent.fill", "camp", "camping"),
            icon("door.left.hand.closed", "door", "entry"),
            icon("door.sliding.left.hand.closed", "sliding", "door", "closet"),
            icon("stairs", "stairs", "floor"),
            icon("lock.fill", "lock", "secure"),
            icon("key.fill", "key", "keys"),
        ]),
        IconSection(title: "Rooms", icons: [
            icon("bed.double.fill", "bed", "bedroom"),
            icon("sofa.fill", "sofa", "couch", "living"),
            icon("chair.fill", "chair", "seat"),
            icon("chair.lounge.fill", "lounge", "chair"),
            icon("lamp.floor.fill", "lamp", "floor"),
            icon("lamp.desk.fill", "lamp", "desk"),
            icon("lightbulb.fill", "light", "bulb"),
            icon("fireplace.fill", "fireplace", "hearth"),
            icon("bathtub.fill", "bath", "bathtub"),
            icon("shower.fill", "shower", "bathroom"),
            icon("toilet.fill", "toilet", "bathroom"),
            icon("washer.fill", "washer", "laundry"),
            icon("dryer.fill", "dryer", "laundry"),
        ]),
        IconSection(title: "Kitchen", icons: [
            icon("fork.knife", "kitchen", "dining", "food"),
            icon("refrigerator.fill", "fridge", "refrigerator", "freezer"),
            icon("oven.fill", "oven", "stove"),
            icon("microwave.fill", "microwave"),
            icon("dishwasher.fill", "dishwasher"),
            icon("cup.and.saucer.fill", "coffee", "cup"),
            icon("mug.fill", "mug", "coffee"),
            icon("wineglass.fill", "wine", "glass"),
            icon("takeoutbag.and.cup.and.straw.fill", "takeout", "food", "drink"),
            icon("birthday.cake.fill", "cake", "party"),
            icon("cart.fill", "cart", "shopping"),
            icon("basket.fill", "basket", "shopping"),
        ]),
        IconSection(title: "Storage", icons: [
            icon("shippingbox.fill", "box", "bin", "package"),
            icon("archivebox.fill", "archive", "box"),
            icon("cabinet.fill", "cabinet", "closet"),
            icon("books.vertical.fill", "shelf", "bookshelf", "bookcase"),
            icon("rectangle.split.3x1.fill", "drawer", "drawers"),
            icon("tray.full.fill", "tray"),
            icon("tray.fill", "tray", "inbox"),
            icon("folder.fill", "folder"),
            icon("doc.fill", "document", "paper"),
            icon("externaldrive.fill", "drive", "storage"),
            icon("internaldrive.fill", "drive", "storage"),
            icon("bag.fill", "bag"),
            icon("backpack.fill", "backpack"),
            icon("suitcase.fill", "suitcase", "travel"),
            icon("briefcase.fill", "briefcase"),
        ]),
        IconSection(title: "Electronics", icons: [
            icon("laptopcomputer", "laptop", "computer"),
            icon("desktopcomputer", "desktop", "computer"),
            icon("display", "monitor", "screen"),
            icon("pc", "computer", "pc"),
            icon("keyboard", "keyboard"),
            icon("computermouse.fill", "mouse"),
            icon("printer.fill", "printer"),
            icon("scanner.fill", "scanner"),
            icon("wifi.router.fill", "router", "network"),
            icon("server.rack", "server", "rack"),
            icon("iphone", "phone"),
            icon("ipad", "tablet"),
            icon("applewatch", "watch"),
            icon("airpods", "earbuds"),
            icon("headphones", "headphones"),
            icon("tv.fill", "tv", "television"),
            icon("hifispeaker.fill", "speaker", "audio"),
            icon("camera.fill", "camera", "photo"),
            icon("gamecontroller.fill", "games", "controller"),
        ]),
        IconSection(title: "Tools", icons: [
            icon("hammer.fill", "hammer", "tool"),
            icon("wrench.fill", "wrench", "tool"),
            icon("screwdriver.fill", "screwdriver", "tool"),
            icon("wrench.and.screwdriver.fill", "tools", "repair"),
            icon("paintbrush.fill", "paint", "brush"),
            icon("paintpalette.fill", "paint", "art"),
            icon("scissors", "scissors"),
            icon("ruler.fill", "ruler", "measure"),
            icon("pencil", "pencil", "write"),
            icon("highlighter", "marker", "highlighter"),
            icon("paperclip", "paperclip"),
            icon("pin.fill", "pin"),
            icon("mappin", "pin", "map"),
        ]),
        IconSection(title: "Clothing", icons: [
            icon("tshirt.fill", "shirt", "clothes"),
            icon("shoe.fill", "shoe", "shoes"),
            icon("handbag.fill", "handbag", "purse"),
            icon("eyeglasses", "glasses"),
            icon("sunglasses.fill", "sunglasses"),
            icon("watch.analog", "watch"),
            icon("wand.and.stars", "beauty", "magic"),
            icon("comb.fill", "comb"),
        ]),
        IconSection(title: "Health", icons: [
            icon("cross.case.fill", "first aid", "medical"),
            icon("pills.fill", "pills", "medicine"),
            icon("stethoscope", "doctor", "medical"),
            icon("bandage.fill", "bandage"),
            icon("syringe.fill", "syringe"),
            icon("heart.fill", "heart", "health"),
            icon("staroflife.fill", "emergency", "medical"),
            icon("figure.mind.and.body", "wellness", "mind"),
        ]),
        IconSection(title: "Garage & Outdoors", icons: [
            icon("car.fill", "car", "garage"),
            icon("truck.box.fill", "truck"),
            icon("bicycle", "bike", "bicycle"),
            icon("scooter", "scooter"),
            icon("fuelpump.fill", "fuel", "gas"),
            icon("leaf.fill", "leaf", "garden"),
            icon("tree.fill", "tree", "yard"),
            icon("camera.macro", "plant", "macro"),
            icon("drop.fill", "water"),
            icon("snowflake", "snow", "winter"),
            icon("sun.max.fill", "sun", "summer"),
            icon("moon.fill", "moon", "night"),
            icon("flame.fill", "flame", "fire"),
        ]),
        IconSection(title: "Sports & Hobbies", icons: [
            icon("dumbbell.fill", "gym", "fitness", "weights"),
            icon("figure.pool.swim", "swim", "pool"),
            icon("soccerball", "soccer"),
            icon("basketball.fill", "basketball"),
            icon("football.fill", "football"),
            icon("baseball.fill", "baseball"),
            icon("tennis.racket", "tennis"),
            icon("skateboard.fill", "skateboard"),
            icon("guitars.fill", "guitar", "music"),
            icon("music.note", "music"),
            icon("book.fill", "book", "read"),
            icon("newspaper.fill", "newspaper"),
            icon("puzzlepiece.fill", "puzzle"),
        ]),
        IconSection(title: "Personal", icons: [
            icon("person.crop.circle.fill", "person", "profile"),
            icon("wallet.pass.fill", "wallet"),
            icon("creditcard.fill", "card", "credit"),
            icon("gift.fill", "gift"),
            icon("tag.fill", "tag", "label"),
            icon("bookmark.fill", "bookmark"),
            icon("envelope.fill", "mail", "letter"),
            icon("phone.fill", "phone"),
            icon("map.fill", "map"),
            icon("location.fill", "location"),
            icon("globe", "world", "global"),
            icon("calendar", "calendar"),
            icon("clock.fill", "clock", "time"),
        ]),
        IconSection(title: "General", icons: [
            icon("square.stack.3d.up.fill", "stack"),
            icon("cube.fill", "cube"),
            icon("cylinder.fill", "cylinder"),
            icon("circle.fill", "circle"),
            icon("square.fill", "square"),
            icon("triangle.fill", "triangle"),
            icon("diamond.fill", "diamond"),
            icon("star.fill", "star"),
            icon("flag.fill", "flag"),
            icon("bell.fill", "bell"),
            icon("checkmark.circle.fill", "check"),
            icon("questionmark.circle.fill", "question"),
            icon("exclamationmark.triangle.fill", "warning"),
        ]),
    ]

    private var visibleSections: [IconSection] {
        let tokens = searchText
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)

        guard !tokens.isEmpty else { return sections }

        return sections.compactMap { section in
            let matches = section.icons.filter { option in
                let haystack = "\(section.title.lowercased()) \(option.searchText)"
                return tokens.allSatisfy { haystack.contains($0) }
            }
            return matches.isEmpty ? nil : IconSection(title: section.title, icons: matches)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    noIconButton

                    ForEach(visibleSections) { section in
                        iconSection(section)
                    }

                    if visibleSections.isEmpty {
                        ContentUnavailableView(
                            "No Icons",
                            systemImage: "magnifyingglass",
                            description: Text("Try another name.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search icon names")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var noIconButton: some View {
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
    }

    private func iconSection(_ section: IconSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(section.icons) { option in
                    iconButton(option)
                }
            }
        }
    }

    private func iconButton(_ option: IconOption) -> some View {
        Button {
            selectedIcon = option.name
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: option.name)
                    .font(.title3)
                    .frame(height: 24)

                Text(option.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .padding(.horizontal, 4)
            .background(
                selectedIcon == option.name
                    ? Color.accentColor.opacity(0.2)
                    : Color(.tertiarySystemBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedIcon == option.name ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .tint(.primary)
        .accessibilityLabel(option.name)
    }
}
