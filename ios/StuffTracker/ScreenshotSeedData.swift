#if DEBUG
import Foundation
import SwiftData

@MainActor
enum ScreenshotSeedData {
    static let launchArgument = "--app-store-screenshots"

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument) ||
        ProcessInfo.processInfo.environment["APP_STORE_SCREENSHOTS"] == "1"
    }

    static func prepareAuthenticationStateIfNeeded() {
        guard isEnabled else { return }

        APIClient.shared.clearAuthTokens()
        UserDefaults.standard.set(false, forKey: AuthStore.completedAuthenticationDefaultsKey)
    }

    static func installIfNeeded() {
        guard isEnabled, let context = LocalDataManager.shared.context else { return }

        resetLocalData(in: context)
        resetScreenshotPreferences()

        let home = LocalHome(
            id: "screenshot-home-maple-house",
            name: "Maple House",
            ownerId: "screenshot-user",
            role: "owner",
            icon: "house.fill",
            isFlagged: true,
            sortOrder: 0,
            needsSync: false
        )

        let mainFloor = LocalLocation(
            id: "screenshot-location-main-floor",
            homeId: home.id,
            name: "Main Floor",
            type: "floor",
            sortOrder: 0,
            icon: "stairs",
            needsSync: false
        )
        let kitchen = LocalLocation(
            id: "screenshot-location-kitchen",
            homeId: home.id,
            parentId: mainFloor.id,
            name: "Kitchen",
            type: "room",
            sortOrder: 0,
            icon: "fork.knife",
            needsSync: false
        )
        let office = LocalLocation(
            id: "screenshot-location-office",
            homeId: home.id,
            parentId: mainFloor.id,
            name: "Office",
            type: "room",
            sortOrder: 1,
            icon: "desktopcomputer",
            isFlagged: true,
            needsSync: false
        )
        let pantry = LocalLocation(
            id: "screenshot-location-pantry",
            homeId: home.id,
            parentId: kitchen.id,
            name: "Pantry Shelf",
            type: "container",
            sortOrder: 0,
            icon: "books.vertical",
            needsSync: false
        )
        let deskDrawer = LocalLocation(
            id: "screenshot-location-desk-drawer",
            homeId: home.id,
            parentId: office.id,
            name: "Desk Drawer",
            type: "container",
            sortOrder: 0,
            icon: "rectangle.split.3x1",
            needsSync: false
        )

        let garage = LocalLocation(
            id: "screenshot-location-garage",
            homeId: home.id,
            name: "Garage",
            type: "room",
            sortOrder: 1,
            icon: "car.fill",
            needsSync: false
        )
        let toolCabinet = LocalLocation(
            id: "screenshot-location-tool-cabinet",
            homeId: home.id,
            parentId: garage.id,
            name: "Tool Cabinet",
            type: "container",
            sortOrder: 0,
            icon: "cabinet",
            needsSync: false
        )

        let items = [
            LocalItem(
                id: "screenshot-item-passports",
                homeId: home.id,
                locationId: deskDrawer.id,
                name: "Passports",
                icon: "doc.text.fill",
                notes: "Renew before the summer trip.",
                quantity: 2,
                properties: [
                    ItemProperty(key: "Safe copy", value: "Cloud backup")
                ],
                warrantyExpiresDate: "2028-06-01",
                isFlagged: true,
                sortOrder: 0,
                createdBy: "screenshot-user",
                needsSync: false
            ),
            LocalItem(
                id: "screenshot-item-camera-bag",
                homeId: home.id,
                locationId: office.id,
                name: "Camera Bag",
                icon: "camera.fill",
                notes: "Body, travel lens, charger, and two SD cards.",
                quantity: 1,
                properties: [
                    ItemProperty(key: "Insurance", value: "Personal articles policy"),
                    ItemProperty(key: "Last checked", value: "May 2026")
                ],
                purchaseDate: "2024-09-14",
                serialNumber: "CAM-2048-ML",
                modelNumber: "TRVL-KIT",
                warrantyExpiresDate: "2027-09-14",
                estimatedValueCents: 185000,
                sortOrder: 1,
                createdBy: "screenshot-user",
                needsSync: false
            ),
            LocalItem(
                id: "screenshot-item-coffee-filters",
                homeId: home.id,
                locationId: pantry.id,
                name: "Coffee Filters",
                icon: "mug.fill",
                quantity: 3,
                sortOrder: 2,
                createdBy: "screenshot-user",
                needsSync: false
            ),
            LocalItem(
                id: "screenshot-item-miter-saw",
                homeId: home.id,
                locationId: toolCabinet.id,
                name: "Miter Saw",
                icon: "hammer.fill",
                notes: "Warranty card is in the manual sleeve.",
                serialNumber: "SAW-8115",
                warrantyExpiresDate: "2027-03-30",
                estimatedValueCents: 32900,
                isFlagged: true,
                sortOrder: 3,
                createdBy: "screenshot-user",
                needsSync: false
            ),
            LocalItem(
                id: "screenshot-item-bike-pump",
                homeId: home.id,
                locationId: garage.id,
                name: "Bike Pump",
                icon: "bicycle",
                quantity: 1,
                sortOrder: 4,
                createdBy: "screenshot-user",
                needsSync: false
            )
        ]

        context.insert(home)
        [mainFloor, kitchen, office, pantry, deskDrawer, garage, toolCabinet].forEach { location in
            context.insert(location)
            location.home = home
        }
        items.forEach { item in
            context.insert(item)
            item.home = home
        }

        try? context.save()
    }

    private static func resetLocalData(in context: ModelContext) {
        deleteAll(LocalItem.self, in: context)
        deleteAll(LocalLocation.self, in: context)
        deleteAll(LocalHome.self, in: context)
        deleteAll(SyncOperation.self, in: context)
        try? context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let descriptor = FetchDescriptor<T>()
        guard let records = try? context.fetch(descriptor) else { return }
        records.forEach { context.delete($0) }
    }

    private static func resetScreenshotPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: FirstRunTutorialController.completedDefaultsKey)
        defaults.removeObject(forKey: "collapsed_tree_node_ids_v1")
        defaults.removeObject(forKey: "collapsed_container_ids_v1")
    }
}
#endif
