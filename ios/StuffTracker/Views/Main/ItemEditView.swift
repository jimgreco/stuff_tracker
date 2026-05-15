import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum ItemEditError: LocalizedError {
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Sign in before adding hosted photos or documents."
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
                .fill(isVisible ? Color.accentColor : Color.clear)
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
    @State private var documentAttachments: [EditableDocumentAttachment]
    @State private var draggedDocumentAttachmentID: String?
    @State private var documentDropTargetID: String?
    @State private var documentDropPlacement: ReorderDropPlacement?
    @State private var documentFrames: [String: CGRect] = [:]
    @State private var showDocumentImporter = false
    @State private var attachmentError: String?

    init(item: Item, homeStore: HomeStore, homeId: String = "") {
        self.item = item
        self.homeStore = homeStore
        self.homeId = homeId
        _name = State(initialValue: item.name)
        _notes = State(initialValue: item.notes ?? "")
        _quantity = State(initialValue: item.quantity)
        _selectedLocationId = State(initialValue: item.locationId)
        _selectedIcon = State(initialValue: item.icon ?? "")
        _properties = State(initialValue: item.properties)
        _photoAttachments = State(initialValue: item.photoUrls.map { EditablePhotoAttachment(remoteURL: $0) })
        _documentAttachments = State(initialValue: item.documents.map { EditableDocumentAttachment(document: $0) })
    }

    private var home: HomeDetail? {
        homeStore.homeDetails.first(where: { $0.id == homeId })
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                locationSection
                propertiesSection
                photosSection
                documentsSection
                deleteSection
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon)
            }
            .fullScreenCover(item: $viewedPhotoAttachment) { attachment in
                PhotoAttachmentViewer(attachment: attachment)
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

            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        Section("Location") {
            LocationTreePicker(
                selectedId: $selectedLocationId,
                home: home
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
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    @ViewBuilder
    private func propertyRow(_ property: Binding<ItemProperty>) -> some View {
        let propertyID = property.wrappedValue.id
        let isDropTarget = propertyDropTargetID == propertyID

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    TextField("Key", text: property.key)
                        .textInputAutocapitalization(.words)

                    Button(role: .destructive) {
                        properties.removeAll { $0.id == propertyID }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                }

                TextField("Value", text: property.value, axis: .vertical)
                    .lineLimit(1...3)
            }
            .padding(.vertical, 2)
            .buttonStyle(.borderless)
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
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
    }

    @ViewBuilder
    private var photosSection: some View {
        Section("Photo") {
            if !photoAttachments.isEmpty {
                ForEach(photoAttachments) { attachment in
                    photoRow(attachment)
                }
            }

            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 20, matching: .images) {
                Label("Add Photos", systemImage: "photo")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    @ViewBuilder
    private func photoRow(_ attachment: EditablePhotoAttachment) -> some View {
        let attachmentID = attachment.id
        let isDropTarget = photoDropTargetID == attachmentID

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    viewedPhotoAttachment = attachment
                } label: {
                    PhotoAttachmentThumbnail(attachment: attachment)
                        .frame(width: 92, height: 92)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) {
                    photoAttachments.removeAll { $0.id == attachmentID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
            .padding(.leading, 24)
            .padding(.vertical, 4)
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
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 16))
    }

    @ViewBuilder
    private var documentsSection: some View {
        Section("Document") {
            ForEach($documentAttachments) { attachment in
                documentRow(attachment)
            }

            Button {
                showDocumentImporter = true
            } label: {
                Label("Add Documents", systemImage: "doc.badge.plus")
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    @ViewBuilder
    private func documentRow(_ attachment: Binding<EditableDocumentAttachment>) -> some View {
        let attachmentID = attachment.wrappedValue.id
        let contentType = attachment.wrappedValue.document?.contentType ?? attachment.wrappedValue.pendingDocument?.contentType
        let isDropTarget = documentDropTargetID == attachmentID

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

                Button(role: .destructive) {
                    documentAttachments.removeAll { $0.id == attachmentID }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 1)
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
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
                photoAttachments.append(
                    EditablePhotoAttachment(
                        pendingPhoto: PendingPhoto(
                            data: data,
                            fileName: "item-photo.\(type.preferredFilenameExtension ?? "jpg")",
                            contentType: type.preferredMIMEType ?? "image/jpeg"
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
                            homeId: homeId,
                            kind: .photo,
                            fileName: photo.fileName,
                            contentType: photo.contentType,
                            data: photo.data
                        )
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
                            homeId: homeId,
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
                    locationId: selectedLocationId,
                    icon: selectedIcon.isEmpty ? nil : selectedIcon,
                    notes: notes.isEmpty ? nil : notes,
                    quantity: quantity,
                    properties: normalizedProperties,
                    photoUrls: nextPhotoUrls,
                    documents: nextDocuments,
                    purchaseDate: item.purchaseDate
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

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .tint(.secondary)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .failure:
                Label("Photo unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            @unknown default:
                EmptyView()
            }
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
