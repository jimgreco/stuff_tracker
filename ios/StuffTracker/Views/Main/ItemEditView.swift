import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import CryptoKit

private enum ItemEditError: LocalizedError {
    case signInRequired
    case cameraUnavailable
    case cameraCaptureFailed
    case photoProcessingFailed
    case invalidEstimatedValue

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Sign in before adding hosted photos or documents."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .cameraCaptureFailed:
            return "Could not save the captured photo."
        case .photoProcessingFailed:
            return "Could not prepare the selected photo."
        case .invalidEstimatedValue:
            return "Estimated value must be a valid dollar amount."
        }
    }
}

private struct PendingPhoto: Identifiable {
    let id = UUID()
    var data: Data
    var fileName: String
    var contentType: String
}

private struct PendingDocument: Identifiable {
    let id = UUID()
    var data: Data
    var name: String
    var contentType: String
}

private struct EditablePhotoAttachment: Identifiable {
    let id: String
    var remoteURL: String?
    var pendingPhoto: PendingPhoto?

    init(remoteURL: String) {
        self.id = UUID().uuidString
        self.remoteURL = remoteURL
        self.pendingPhoto = nil
    }

    init(pendingPhoto: PendingPhoto) {
        self.id = pendingPhoto.id.uuidString
        self.remoteURL = nil
        self.pendingPhoto = pendingPhoto
    }
}

private struct EditableDocumentAttachment: Identifiable {
    let id: String
    var document: ItemDocument?
    var pendingDocument: PendingDocument?

    init(document: ItemDocument) {
        self.id = UUID().uuidString
        self.document = document
        self.pendingDocument = nil
    }

    init(pendingDocument: PendingDocument) {
        self.id = pendingDocument.id.uuidString
        self.document = nil
        self.pendingDocument = pendingDocument
    }
}

private enum ReorderDropPlacement {
    case before
    case after
}

private struct ReorderInsertionLine: View {
    let isVisible: Bool
    let edge: VerticalEdge

    var body: some View {
        VStack(spacing: 0) {
            if edge == .bottom {
                Spacer(minLength: 0)
            }

            Capsule()
                .fill(isVisible ? CubbyTheme.green : Color.clear)
                .frame(height: 2)

            if edge == .top {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.12), value: isVisible)
    }
}

private struct ReorderRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ReorderRowFrameReporter: ViewModifier {
    let id: String
    @Binding var frames: [String: CGRect]

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ReorderRowFramePreferenceKey.self,
                        value: [id: proxy.frame(in: .global)]
                    )
                }
            }
            .onPreferenceChange(ReorderRowFramePreferenceKey.self) { values in
                if let frame = values[id], frames[id] != frame {
                    DispatchQueue.main.async {
                        frames[id] = frame
                    }
                }
            }
    }
}

private struct RemovableEditorRow<Content: View>: View {
    private let accessibilityLabel: String
    private let onDelete: () -> Void
    private let content: Content

    init(
        accessibilityLabel: String,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                withAnimation {
                    onDelete()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ItemEditView: View {
    let item: Item
    @ObservedObject var homeStore: HomeStore
    let homeId: String
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var notes: String
    @State private var quantity: Int
    @State private var purchaseDate: Date?
    @State private var serialNumber: String
    @State private var modelNumber: String
    @State private var warrantyExpiresDate: Date?
    @State private var estimatedValue: String
    @State private var isFlagged: Bool
    @State private var selectedHomeId: String
    @State private var selectedLocationId: String?
    @State private var isSaving = false
    @State private var selectedIcon: String
    @State private var showIconPicker = false
    @State private var properties: [ItemProperty]
    @State private var draggedPropertyID: String?
    @State private var propertyDropTargetID: String?
    @State private var propertyDropPlacement: ReorderDropPlacement?
    @State private var propertyFrames: [String: CGRect] = [:]
    @State private var photoAttachments: [EditablePhotoAttachment]
    @State private var draggedPhotoAttachmentID: String?
    @State private var photoDropTargetID: String?
    @State private var photoDropPlacement: ReorderDropPlacement?
    @State private var photoFrames: [String: CGRect] = [:]
    @State private var viewedPhotoAttachment: EditablePhotoAttachment?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var documentAttachments: [EditableDocumentAttachment]
    @State private var draggedDocumentAttachmentID: String?
    @State private var documentDropTargetID: String?
    @State private var documentDropPlacement: ReorderDropPlacement?
    @State private var documentFrames: [String: CGRect] = [:]
    @State private var showDocumentImporter = false
    @State private var attachmentError: String?

    private let editorListInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)
    private let editorActionInsets = EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20)

    init(item: Item, homeStore: HomeStore, homeId: String = "") {
        self.item = item
        self.homeStore = homeStore
        self.homeId = homeId
        _name = State(initialValue: item.name)
        _notes = State(initialValue: item.notes ?? "")
        _quantity = State(initialValue: item.quantity)
        _purchaseDate = State(initialValue: ItemDateCodec.parse(item.purchaseDate))
        _serialNumber = State(initialValue: item.serialNumber ?? "")
        _modelNumber = State(initialValue: item.modelNumber ?? "")
        _warrantyExpiresDate = State(initialValue: ItemDateCodec.parse(item.warrantyExpiresDate))
        _estimatedValue = State(initialValue: Self.formattedDollars(fromCents: item.estimatedValueCents))
        _isFlagged = State(initialValue: item.isFlagged)
        _selectedHomeId = State(initialValue: item.homeId.isEmpty ? homeId : item.homeId)
        _selectedLocationId = State(initialValue: item.locationId)
        _selectedIcon = State(initialValue: item.icon ?? "")
        _properties = State(initialValue: item.properties)
        _photoAttachments = State(initialValue: item.photoUrls.map { EditablePhotoAttachment(remoteURL: $0) })
        _documentAttachments = State(initialValue: item.documents.map { EditableDocumentAttachment(document: $0) })
    }

    private var home: HomeDetail? {
        homeStore.homeDetails.first(where: { $0.id == homeId })
    }

    private var selectedHome: HomeDetail? {
        homeStore.homeDetails.first(where: { $0.id == selectedHomeId })
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                    .cubbySheetRows()
                lifecycleSection
                    .cubbySheetRows()
                locationSection
                    .cubbySheetRows()
                propertiesSection
                    .cubbySheetRows()
                photosSection
                    .cubbySheetRows()
                documentsSection
                    .cubbySheetRows()
                deleteSection
                    .cubbySheetRows(prominence: 0.92)
            }
            .cubbySheetChrome()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: "Edit Item")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .fullScreenCover(item: $viewedPhotoAttachment) { attachment in
                PhotoAttachmentViewer(attachment: attachment)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView { result in
                    handleCameraCapture(result)
                }
            }
            .fileImporter(isPresented: $showDocumentImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                handleDocumentImport(result)
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadPhotos(newItems) }
            }
            .alert("Attachment Error", isPresented: Binding(
                get: { attachmentError != nil },
                set: { if !$0 { attachmentError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachmentError ?? "")
            }
        }
    }

    private var shareMenu: some View {
        Menu {
            if let deepLink = deepLinkForSharing {
                ShareLink(item: deepLink.url) {
                    Label("Share Item Link", systemImage: "link")
                }

                Divider()
            }

            ShareLink(item: shareText(.location)) {
                Label("Share Location", systemImage: "mappin.and.ellipse")
            }

            ShareLink(item: shareText(.details)) {
                Label("Share Details", systemImage: "doc.text")
            }

            ShareLink(item: shareText(.locationAndDetails)) {
                Label("Share Location and Details", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(normalizedText(name) == nil)
        .accessibilityLabel("Share item")
    }

    private func shareText(_ scope: ItemShareScope) -> String {
        ItemShareFormatter.text(for: itemForSharing, home: selectedHome, scope: scope)
    }

    private var deepLinkForSharing: ItemDeepLink? {
        let item = itemForSharing
        guard !item.homeId.isEmpty, !item.id.isEmpty else { return nil }
        return ItemDeepLink(homeId: item.homeId, itemId: item.id)
    }

    private var itemForSharing: Item {
        let estimatedCents: Int?
        if let value = Double(estimatedValue.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 {
            estimatedCents = Int((value * 100).rounded())
        } else {
            estimatedCents = item.estimatedValueCents
        }

        return Item(
            id: item.id,
            homeId: selectedHomeId,
            locationId: selectedLocationId,
            name: normalizedText(name) ?? item.name,
            icon: normalizedText(selectedIcon),
            notes: normalizedText(notes),
            quantity: quantity,
            properties: normalizedProperties,
            photoUrls: photoAttachments.compactMap(\.remoteURL),
            documents: documentAttachments.compactMap(\.document),
            purchaseDate: ItemDateCodec.string(from: purchaseDate),
            serialNumber: normalizedText(serialNumber),
            modelNumber: normalizedText(modelNumber),
            warrantyExpiresDate: ItemDateCodec.string(from: warrantyExpiresDate),
            estimatedValueCents: estimatedCents,
            isFlagged: isFlagged,
            sortOrder: item.sortOrder,
            createdBy: item.createdBy,
            needsSync: item.needsSync
        )
    }

    @ViewBuilder
    private var detailsSection: some View {
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

            Toggle(isOn: $isFlagged) {
                Label("Flagged", systemImage: "flag.fill")
            }
            .tint(CubbyTheme.amber)

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        Section("Lifecycle") {
            OptionalDatePickerRow(title: "Purchase Date", date: $purchaseDate)
            OptionalDatePickerRow(title: "Warranty Expires", date: $warrantyExpiresDate)

            TextField("Serial Number", text: $serialNumber)
                .textInputAutocapitalization(.characters)

            TextField("Model Number", text: $modelNumber)
                .textInputAutocapitalization(.characters)

            TextField("Estimated Value", text: $estimatedValue)
                .keyboardType(.decimalPad)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            LocationTreePicker(
                selectedHomeId: $selectedHomeId,
                selectedId: $selectedLocationId,
                homes: homeStore.homeDetails
            )
        }
    }

    @ViewBuilder
    private var propertiesSection: some View {
        Section("Properties") {
            ForEach($properties) { property in
                propertyRow(property)
            }

            Button {
                addProperty()
            } label: {
                Label("Add Property", systemImage: "plus.circle.fill")
            }
            .listRowInsets(editorActionInsets)
        }
    }

    @ViewBuilder
    private func propertyRow(_ property: Binding<ItemProperty>) -> some View {
        let propertyID = property.wrappedValue.id
        let isDropTarget = propertyDropTargetID == propertyID

        RemovableEditorRow(accessibilityLabel: "Remove Property") {
            properties.removeAll { $0.id == propertyID }
        } content: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Key", text: property.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textInputAutocapitalization(.words)

                    TextField("Value", text: property.value, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...3)
                }
                .padding(.vertical, 6)
                .opacity(draggedPropertyID == propertyID ? 0.5 : 1)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                ReorderInsertionLine(isVisible: isDropTarget && propertyDropPlacement == .before, edge: .top)
            }
            .overlay(alignment: .bottom) {
                ReorderInsertionLine(isVisible: isDropTarget && propertyDropPlacement == .after, edge: .bottom)
            }
            .modifier(ReorderRowFrameReporter(id: propertyID, frames: $propertyFrames))
            .simultaneousGesture(propertyReorderGesture(for: propertyID))
        }
        .listRowInsets(editorListInsets)
    }

    @ViewBuilder
    private var photosSection: some View {
        Section("Photos") {
            if !photoAttachments.isEmpty {
                ForEach(photoAttachments) { attachment in
                    photoRow(attachment)
                }
            }

            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 20, matching: .images) {
                Label("Choose Photos", systemImage: "photo.on.rectangle")
            }
            .listRowInsets(editorActionInsets)

            Button {
                if CameraCaptureView.isAvailable {
                    showCamera = true
                } else {
                    attachmentError = ItemEditError.cameraUnavailable.localizedDescription
                }
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
            }
            .disabled(!CameraCaptureView.isAvailable)
            .listRowInsets(editorActionInsets)
        }
    }

    @ViewBuilder
    private func photoRow(_ attachment: EditablePhotoAttachment) -> some View {
        let attachmentID = attachment.id
        let isDropTarget = photoDropTargetID == attachmentID

        RemovableEditorRow(accessibilityLabel: "Remove Photo") {
            photoAttachments.removeAll { $0.id == attachmentID }
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        viewedPhotoAttachment = attachment
                    } label: {
                        PhotoAttachmentThumbnail(attachment: attachment)
                            .frame(width: 92, height: 92)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.vertical, 6)
                .frame(minHeight: 104)
                .opacity(draggedPhotoAttachmentID == attachmentID ? 0.5 : 1)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                ReorderInsertionLine(isVisible: isDropTarget && photoDropPlacement == .before, edge: .top)
            }
            .overlay(alignment: .bottom) {
                ReorderInsertionLine(isVisible: isDropTarget && photoDropPlacement == .after, edge: .bottom)
            }
            .modifier(ReorderRowFrameReporter(id: attachmentID, frames: $photoFrames))
            .simultaneousGesture(photoReorderGesture(for: attachmentID))
        }
        .listRowInsets(editorListInsets)
    }

    @ViewBuilder
    private var documentsSection: some View {
        Section("Documents") {
            ForEach($documentAttachments) { attachment in
                documentRow(attachment)
            }

            Button {
                showDocumentImporter = true
            } label: {
                Label("Add Documents", systemImage: "doc.badge.plus")
            }
            .listRowInsets(editorActionInsets)
        }
    }

    @ViewBuilder
    private func documentRow(_ attachment: Binding<EditableDocumentAttachment>) -> some View {
        let attachmentID = attachment.wrappedValue.id
        let contentType = attachment.wrappedValue.document?.contentType ?? attachment.wrappedValue.pendingDocument?.contentType
        let isDropTarget = documentDropTargetID == attachmentID

        RemovableEditorRow(accessibilityLabel: "Remove Document") {
            documentAttachments.removeAll { $0.id == attachmentID }
        } content: {
            VStack(spacing: 0) {
                HStack {
                    DocumentAttachmentEditor(
                        name: Binding(
                            get: {
                                attachment.wrappedValue.document?.name ?? attachment.wrappedValue.pendingDocument?.name ?? ""
                            },
                            set: { newName in
                                var nextAttachment = attachment.wrappedValue
                                if nextAttachment.document != nil {
                                    nextAttachment.document?.name = newName
                                } else if nextAttachment.pendingDocument != nil {
                                    nextAttachment.pendingDocument?.name = newName
                                }
                                attachment.wrappedValue = nextAttachment
                            }
                        ),
                        contentType: contentType
                    )

                    Spacer()

                    if let document = attachment.wrappedValue.document, let url = URL(string: document.url) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
                .padding(.vertical, 6)
                .buttonStyle(.borderless)
                .opacity(draggedDocumentAttachmentID == attachmentID ? 0.5 : 1)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                ReorderInsertionLine(isVisible: isDropTarget && documentDropPlacement == .before, edge: .top)
            }
            .overlay(alignment: .bottom) {
                ReorderInsertionLine(isVisible: isDropTarget && documentDropPlacement == .after, edge: .bottom)
            }
            .modifier(ReorderRowFrameReporter(id: attachmentID, frames: $documentFrames))
            .simultaneousGesture(documentReorderGesture(for: attachmentID))
        }
        .listRowInsets(editorListInsets)
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button("Delete Item", role: .destructive) {
                Task {
                    homeStore.deleteItem(homeId: homeId, itemId: item.id)
                    dismiss()
                }
            }
        }
    }

    private var normalizedProperties: [ItemProperty] {
        properties.compactMap { property in
            let key = property.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return ItemProperty(
                id: property.id,
                key: key,
                value: property.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func normalizedText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedEstimatedValueCents() throws -> Int? {
        let trimmed = estimatedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value >= 0 else {
            throw ItemEditError.invalidEstimatedValue
        }
        return Int((value * 100).rounded())
    }

    private static func formattedDollars(fromCents cents: Int?) -> String {
        guard let cents else { return "" }
        return String(format: "%.2f", Double(cents) / 100)
    }

    private func addProperty() {
        properties.append(ItemProperty())
    }

    private func propertyReorderGesture(for id: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    draggedPropertyID = id
                case .second(true, let drag?):
                    if draggedPropertyID == nil {
                        draggedPropertyID = id
                    }
                    updateReorderTarget(
                        draggedID: draggedPropertyID,
                        locationY: drag.location.y,
                        frames: propertyFrames,
                        itemIDs: properties.map(\.id)
                    ) { targetID, placement in
                        propertyDropTargetID = targetID
                        propertyDropPlacement = placement
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                finishPropertyReorder()
            }
    }

    private func photoReorderGesture(for id: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    draggedPhotoAttachmentID = id
                case .second(true, let drag?):
                    if draggedPhotoAttachmentID == nil {
                        draggedPhotoAttachmentID = id
                    }
                    updateReorderTarget(
                        draggedID: draggedPhotoAttachmentID,
                        locationY: drag.location.y,
                        frames: photoFrames,
                        itemIDs: photoAttachments.map(\.id)
                    ) { targetID, placement in
                        photoDropTargetID = targetID
                        photoDropPlacement = placement
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                finishPhotoReorder()
            }
    }

    private func documentReorderGesture(for id: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    draggedDocumentAttachmentID = id
                case .second(true, let drag?):
                    if draggedDocumentAttachmentID == nil {
                        draggedDocumentAttachmentID = id
                    }
                    updateReorderTarget(
                        draggedID: draggedDocumentAttachmentID,
                        locationY: drag.location.y,
                        frames: documentFrames,
                        itemIDs: documentAttachments.map(\.id)
                    ) { targetID, placement in
                        documentDropTargetID = targetID
                        documentDropPlacement = placement
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                finishDocumentReorder()
            }
    }

    private func updateReorderTarget(
        draggedID: String?,
        locationY: CGFloat,
        frames: [String: CGRect],
        itemIDs: [String],
        update: (String?, ReorderDropPlacement?) -> Void
    ) {
        guard let draggedID else {
            update(nil, nil)
            return
        }

        let orderedFrames = itemIDs.compactMap { id -> (id: String, frame: CGRect)? in
            guard let frame = frames[id] else { return nil }
            return (id, frame)
        }

        guard let first = orderedFrames.first else {
            update(nil, nil)
            return
        }

        let target: (id: String, placement: ReorderDropPlacement)
        if locationY <= first.frame.midY {
            target = (first.id, .before)
        } else if let next = orderedFrames.first(where: { locationY < $0.frame.midY }) {
            target = (next.id, .before)
        } else if let last = orderedFrames.last {
            target = (last.id, .after)
        } else {
            update(nil, nil)
            return
        }

        if target.id == draggedID {
            update(nil, nil)
        } else {
            update(target.id, target.placement)
        }
    }

    private func finishPropertyReorder() {
        performReorder(
            items: &properties,
            draggedID: draggedPropertyID,
            targetID: propertyDropTargetID,
            placement: propertyDropPlacement
        )
        draggedPropertyID = nil
        propertyDropTargetID = nil
        propertyDropPlacement = nil
    }

    private func finishPhotoReorder() {
        performReorder(
            items: &photoAttachments,
            draggedID: draggedPhotoAttachmentID,
            targetID: photoDropTargetID,
            placement: photoDropPlacement
        )
        draggedPhotoAttachmentID = nil
        photoDropTargetID = nil
        photoDropPlacement = nil
    }

    private func finishDocumentReorder() {
        performReorder(
            items: &documentAttachments,
            draggedID: draggedDocumentAttachmentID,
            targetID: documentDropTargetID,
            placement: documentDropPlacement
        )
        draggedDocumentAttachmentID = nil
        documentDropTargetID = nil
        documentDropPlacement = nil
    }

    private func performReorder<Value: Identifiable>(
        items: inout [Value],
        draggedID: String?,
        targetID: String?,
        placement: ReorderDropPlacement?
    ) where Value.ID == String {
        guard let draggedID,
              let targetID,
              let placement,
              draggedID != targetID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let movedItem = items.remove(at: fromIndex)
        var insertionIndex = targetIndex

        if fromIndex < targetIndex {
            insertionIndex -= 1
        }

        if placement == .after {
            insertionIndex += 1
        }

        let boundedIndex = min(max(insertionIndex, 0), items.count)
        items.insert(movedItem, at: boundedIndex)
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                guard let image = UIImage(data: data) else {
                    throw ItemEditError.photoProcessingFailed
                }
                let sanitizedData = try sanitizedJPEGData(from: image)
                photoAttachments.append(
                    EditablePhotoAttachment(
                        pendingPhoto: PendingPhoto(
                            data: sanitizedData,
                            fileName: "item-photo-\(UUID().uuidString).jpg",
                            contentType: "image/jpeg"
                        )
                    )
                )
            } catch {
                attachmentError = error.localizedDescription
            }
        }
        selectedPhotoItems = []
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try url.resourceValues(forKeys: [.contentTypeKey])
                let type = values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
                documentAttachments.append(
                    EditableDocumentAttachment(
                        pendingDocument: PendingDocument(
                            data: try Data(contentsOf: url),
                            name: url.lastPathComponent,
                            contentType: type.preferredMIMEType ?? "application/octet-stream"
                        )
                    )
                )
            }
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    @MainActor
    private func handleCameraCapture(_ result: Result<UIImage, Error>) {
        do {
            let image = try result.get()
            let data = try sanitizedJPEGData(from: image, failure: .cameraCaptureFailed)

            photoAttachments.append(
                EditablePhotoAttachment(
                    pendingPhoto: PendingPhoto(
                        data: data,
                        fileName: "item-photo-\(UUID().uuidString).jpg",
                        contentType: "image/jpeg"
                    )
                )
            )
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func sanitizedJPEGData(
        from image: UIImage,
        failure: ItemEditError = .photoProcessingFailed
    ) throws -> Data {
        let pixelSize = CGSize(
            width: max(image.size.width * image.scale, 1),
            height: max(image.size.height * image.scale, 1)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }

        guard let data = renderedImage.jpegData(compressionQuality: 0.9) else {
            throw failure
        }
        return data
    }

    private func save() {
        isSaving = true
        attachmentError = nil
        let canUploadAttachments = homeStore.isAuthenticated
        Task {
            do {
                var nextPhotoUrls: [String] = []
                for attachment in photoAttachments {
                    if let remoteURL = attachment.remoteURL {
                        nextPhotoUrls.append(remoteURL)
                    } else if let photo = attachment.pendingPhoto {
                        guard canUploadAttachments else { throw ItemEditError.signInRequired }
                        let upload = try await APIClient.shared.uploadItemAttachment(
                            homeId: selectedHomeId,
                            kind: .photo,
                            fileName: photo.fileName,
                            contentType: photo.contentType,
                            data: photo.data
                        )
                        if let uploadedURL = URL(string: upload.fileUrl) {
                            await RemotePhotoCache.shared.store(photo.data, for: uploadedURL)
                        }
                        nextPhotoUrls.append(upload.fileUrl)
                    }
                }

                var nextDocuments: [ItemDocument] = []
                for attachment in documentAttachments {
                    if let document = attachment.document {
                        nextDocuments.append(document)
                    } else if let document = attachment.pendingDocument {
                        guard canUploadAttachments else { throw ItemEditError.signInRequired }
                        let upload = try await APIClient.shared.uploadItemAttachment(
                            homeId: selectedHomeId,
                            kind: .document,
                            fileName: document.name,
                            contentType: document.contentType,
                            data: document.data
                        )
                        nextDocuments.append(
                            ItemDocument(
                                id: upload.key,
                                url: upload.fileUrl,
                                name: document.name,
                                contentType: document.contentType
                            )
                        )
                    }
                }

                let body = APIClient.ItemBody(
                    name: name,
                    homeId: selectedHomeId,
                    locationId: selectedLocationId,
                    icon: selectedIcon.isEmpty ? nil : selectedIcon,
                    notes: notes.isEmpty ? nil : notes,
                    quantity: quantity,
                    properties: normalizedProperties,
                    photoUrls: nextPhotoUrls,
                    documents: nextDocuments,
                    purchaseDate: ItemDateCodec.string(from: purchaseDate),
                    serialNumber: normalizedText(serialNumber),
                    modelNumber: normalizedText(modelNumber),
                    warrantyExpiresDate: ItemDateCodec.string(from: warrantyExpiresDate),
                    estimatedValueCents: try normalizedEstimatedValueCents(),
                    isFlagged: isFlagged,
                    sortOrder: item.sortOrder
                )

                homeStore.updateItem(homeId: homeId, itemId: item.id, body: body)
                dismiss()
            } catch {
                attachmentError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct DocumentAttachmentEditor: View {
    @Binding var name: String
    let contentType: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                TextField("File name", text: $name)
                    .lineLimit(1)
                if let contentType, !contentType.isEmpty {
                    Text(contentType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "doc")
        }
    }
}

private struct PhotoAttachmentThumbnail: View {
    let attachment: EditablePhotoAttachment

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)

            if let remoteURL = attachment.remoteURL,
               let url = URL(string: remoteURL) {
                RemotePhotoImage(url: url, contentMode: .fill)
            } else if let pendingPhoto = attachment.pendingPhoto,
                      let image = UIImage(data: pendingPhoto.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PhotoAttachmentViewer: View {
    let attachment: EditablePhotoAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let remoteURL = attachment.remoteURL,
               let url = URL(string: remoteURL) {
                RemotePhotoImage(url: url, contentMode: .fit)
                    .padding()
            } else if let pendingPhoto = attachment.pendingPhoto,
                      let image = UIImage(data: pendingPhoto.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                Label("Photo unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white.secondary)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
    }
}

private struct RemotePhotoImage: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                Label("Photo unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .tint(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false

        do {
            let data = try await RemotePhotoCache.shared.data(for: url)
            guard let loadedImage = UIImage(data: data) else {
                throw RemotePhotoCacheError.invalidImageData
            }
            image = loadedImage
        } catch is CancellationError {
        } catch {
            didFail = true
        }
    }
}

private enum RemotePhotoCacheError: Error {
    case invalidImageData
    case requestFailed
}

private actor RemotePhotoCache {
    static let shared = RemotePhotoCache()

    private let memoryCache = NSCache<NSString, NSData>()
    private let cacheDirectory: URL
    private var inFlight: [String: Task<Data, Error>] = [:]

    init() {
        let baseDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = baseDirectory.appendingPathComponent("RemotePhotoCache", isDirectory: true)
    }

    func data(for url: URL) async throws -> Data {
        let key = Self.cacheKey(for: url)
        if let cachedData = memoryCache.object(forKey: key as NSString) {
            return cachedData as Data
        }

        if let diskData = try? Data(contentsOf: fileURL(forKey: key)), !diskData.isEmpty {
            memoryCache.setObject(diskData as NSData, forKey: key as NSString)
            return diskData
        }

        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            try await Self.fetchData(from: url)
        }
        inFlight[key] = task

        do {
            let data = try await task.value
            inFlight[key] = nil
            cache(data, forKey: key)
            return data
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func store(_ data: Data, for url: URL) {
        let key = Self.cacheKey(for: url)
        inFlight[key]?.cancel()
        inFlight[key] = nil
        cache(data, forKey: key)
    }

    private func cache(_ data: Data, forKey key: String) {
        guard !data.isEmpty else { return }
        memoryCache.setObject(data as NSData, forKey: key as NSString)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(forKey: key), options: .atomic)
    }

    private func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key, isDirectory: false)
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw RemotePhotoCacheError.requestFailed
        }
        return data
    }

    private static func cacheKey(for url: URL) -> String {
        let stableIdentity = stableIdentity(for: url)
        let digest = SHA256.hash(data: Data(stableIdentity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stableIdentity(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    let onComplete: (Result<UIImage, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onComplete: (Result<UIImage, Error>) -> Void
        private let dismiss: DismissAction

        init(onComplete: @escaping (Result<UIImage, Error>) -> Void, dismiss: DismissAction) {
            self.onComplete = onComplete
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onComplete(.success(image))
            } else {
                onComplete(.failure(ItemEditError.cameraCaptureFailed))
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private enum ItemDateCodec {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return formatter.date(from: value)
    }

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        return formatter.string(from: date)
    }
}

private struct OptionalDatePickerRow: View {
    let title: String
    @Binding var date: Date?

    private var selection: Binding<Date> {
        Binding(
            get: { date ?? Date() },
            set: { date = $0 }
        )
    }

    var body: some View {
        HStack {
            if date == nil {
                Text(title)
                Spacer()
            } else {
                DatePicker(title, selection: selection, displayedComponents: .date)
            }
            Button(date == nil ? "Add" : "Clear") {
                if date == nil {
                    date = Date()
                } else {
                    date = nil
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

enum ItemShareScope {
    case location
    case details
    case locationAndDetails
}

enum ItemShareFormatter {
    static func text(for item: Item, home: HomeDetail?, scope: ItemShareScope) -> String {
        var lines = [item.name]

        if scope.includesLocation {
            lines.append("Location: \(locationText(for: item, home: home))")
        }

        if scope.includesDetails {
            lines.append("Quantity: \(item.quantity)")
            append("Notes", item.notes, to: &lines)
            append("Serial Number", item.serialNumber, to: &lines)
            append("Model Number", item.modelNumber, to: &lines)
            append("Purchase Date", item.purchaseDate, to: &lines)
            append("Warranty Expires", item.warrantyExpiresDate, to: &lines)

            if let estimatedValue = formattedEstimatedValue(item.estimatedValueCents) {
                lines.append("Estimated Value: \(estimatedValue)")
            }

            for property in item.properties {
                let key = property.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }

                let value = property.value.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(value.isEmpty ? key : "\(key): \(value)")
            }

            if !item.documents.isEmpty {
                let documentNames = item.documents
                    .map(\.name)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if documentNames.isEmpty {
                    lines.append(item.documents.count == 1 ? "Documents: 1 file" : "Documents: \(item.documents.count) files")
                } else {
                    lines.append("Documents: \(documentNames.joined(separator: ", "))")
                }
            }

            if !item.photoUrls.isEmpty {
                lines.append(item.photoUrls.count == 1 ? "Photos: 1 photo" : "Photos: \(item.photoUrls.count) photos")
            }
        }

        if let link = appLink(for: item) {
            lines.append("Open in CubbyLog: \(link)")
        }

        return lines.joined(separator: "\n")
    }

    private static func append(_ label: String, _ value: String?, to lines: inout [String]) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        lines.append("\(label): \(value)")
    }

    private static func locationText(for item: Item, home: HomeDetail?) -> String {
        guard let home else { return "None" }
        let selectedLabel = LocationTreePresentation.selectedLabel(home: home, selectedId: item.locationId)
        return selectedLabel == home.name ? home.name : "\(home.name) › \(selectedLabel)"
    }

    private static func formattedEstimatedValue(_ cents: Int?) -> String? {
        guard let cents else { return nil }
        return String(format: "$%.2f", Double(cents) / 100)
    }

    private static func appLink(for item: Item) -> String? {
        guard !item.homeId.isEmpty, !item.id.isEmpty else { return nil }
        return ItemDeepLink(homeId: item.homeId, itemId: item.id).url.absoluteString
    }
}

private extension ItemShareScope {
    var includesLocation: Bool {
        self == .location || self == .locationAndDetails
    }

    var includesDetails: Bool {
        self == .details || self == .locationAndDetails
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
    @Binding var selectedHomeId: String
    @Binding var selectedId: String?
    let homes: [HomeDetail]
    @State private var showPicker = false

    private var selectedHome: HomeDetail? {
        homes.first(where: { $0.id == selectedHomeId })
    }

    private var selectedLabel: String {
        guard let selectedHome else { return "None" }
        let label = LocationTreePresentation.selectedLabel(home: selectedHome, selectedId: selectedId)
        return homes.count > 1 && selectedId != nil ? "\(selectedHome.name) › \(label)" : label
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
            LocationTreeSheet(
                homes: homes,
                selectedHomeId: $selectedHomeId,
                selectedId: $selectedId,
                dismiss: { showPicker = false }
            )
        }
    }
}

private enum LocationTreeRoute: Hashable {
    case home(String)
    case location(homeId: String, locationId: String)
}

private struct LocationTreeSheet: View {
    let homes: [HomeDetail]
    @Binding var selectedHomeId: String
    @Binding var selectedId: String?
    let dismiss: () -> Void
    @State private var path: [LocationTreeRoute] = []

    private var selectedHome: HomeDetail? {
        homes.first(where: { $0.id == selectedHomeId }) ?? homes.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            LocationHomeLevel(
                homes: homes,
                selectedHomeId: $selectedHomeId,
                selectedId: $selectedId,
                dismiss: dismiss
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    CubbyNavigationBrandTitle(title: "Select Location")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: LocationTreeRoute.self) { route in
                switch route {
                case .home(let homeId):
                    let home = homes.first(where: { $0.id == homeId })
                    LocationTreeLevel(
                        home: home,
                        selectedHomeId: $selectedHomeId,
                        parentId: nil,
                        selectedId: $selectedId,
                        dismiss: dismiss
                    )
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .cubbyNavigationTitle(home?.name ?? "")
                case .location(let homeId, let locId):
                    let home = homes.first(where: { $0.id == homeId })
                    let loc = home?.locations.first(where: { $0.id == locId })
                    LocationTreeLevel(
                        home: home,
                        selectedHomeId: $selectedHomeId,
                        parentId: locId,
                        selectedId: $selectedId,
                        dismiss: dismiss
                    )
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .cubbyNavigationTitle(loc?.name ?? "")
                }
            }
        }
        .cubbyNavigationBarChrome()
        .onAppear {
            guard let home = selectedHome else { return }
            path = [.home(home.id)] + LocationTreePresentation
                .initialNavigationPath(home: home, selectedId: selectedId)
                .map { .location(homeId: home.id, locationId: $0) }
        }
    }
}

private struct LocationHomeLevel: View {
    let homes: [HomeDetail]
    @Binding var selectedHomeId: String
    @Binding var selectedId: String?
    let dismiss: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(homes, id: \.id) { home in
                    NavigationLink(value: LocationTreeRoute.home(home.id)) {
                        HStack {
                            Label(home.name, systemImage: home.icon ?? "house.fill")
                            Spacer()
                            if selectedHomeId == home.id && selectedId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(CubbyTheme.green)
                            }
                        }
                    }
                }
            }
            .cubbySheetRows()
        }
        .cubbySheetChrome()
    }
}

private struct LocationTreeLevel: View {
    let home: HomeDetail?
    @Binding var selectedHomeId: String
    let parentId: String?
    @Binding var selectedId: String?
    let dismiss: () -> Void

    private var children: [Location] {
        guard let home else { return [] }
        return home.locations
            .filter { $0.parentId == parentId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var currentName: String {
        guard let home else { return "" }
        if let parentId, let loc = home.locations.first(where: { $0.id == parentId }) {
            return loc.name
        }
        return home.name
    }

    var body: some View {
        List {
            // Option to select current level
            Button {
                guard let home else { return }
                selectedHomeId = home.id
                selectedId = parentId
                dismiss()
            } label: {
                HStack {
                    Label(
                        parentId == nil ? "\(currentName) (top level)" : "Place here",
                        systemImage: parentId == nil ? (home?.icon ?? "house.fill") : "checkmark.circle"
                    )
                    Spacer()
                    if selectedHomeId == home?.id && selectedId == parentId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(CubbyTheme.green)
                    }
                }
            }
            .foregroundStyle(.primary)
            .cubbySheetRows()

            if !children.isEmpty {
                Section {
                    ForEach(children) { loc in
                        let locChildren = home?.locations.filter { $0.parentId == loc.id } ?? []
                        if locChildren.isEmpty {
                            // Leaf node - just select
                            Button {
                                if let home {
                                    selectedHomeId = home.id
                                }
                                selectedId = loc.id
                                dismiss()
                            } label: {
                                HStack {
                                    Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                                    Spacer()
                                    if selectedHomeId == home?.id && selectedId == loc.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(CubbyTheme.green)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        } else {
                            // Has children - navigate deeper
                            NavigationLink(value: LocationTreeRoute.location(homeId: home?.id ?? "", locationId: loc.id)) {
                                HStack {
                                    Label(loc.name, systemImage: LocationTreePresentation.icon(for: loc))
                                    Spacer()
                                    if selectedHomeId == home?.id && selectedId == loc.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(CubbyTheme.green)
                                    }
                                }
                            }
                        }
                    }
                }
                .cubbySheetRows()
            }
        }
        .cubbySheetChrome()
    }
}
