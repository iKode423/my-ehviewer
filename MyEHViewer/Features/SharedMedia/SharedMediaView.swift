import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Manages persistent images and videos received from other applications.
struct SharedMediaView: View {
    @EnvironmentObject private var store: SharedMediaStore
    @AppStorage("SharedMedia.layoutMode") private var layoutModeRaw = CollectionLayoutMode.grid.rawValue
    @State private var filter = SharedMediaFilter.all
    @State private var mediaFilterText = ""
    @State private var randomItems: [SharedMediaDisplayItem]?
    @State private var archiveURL: URL?
    @State private var showsArchiveExporter = false
    @State private var showsArchiveImporter = false
    @State private var transferAlert: SharedMediaTransferAlert?
    @State private var editingRecord: SharedMediaRecord?
    @State private var noteText = ""
    private static let scrollTopID = "shared-media-scroll-top"

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    filterControls
                    Divider()
                    mediaContent
                }

                if !filteredItems.isEmpty {
                    Button {
                        showRandomItems(scrollProxy: scrollProxy)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 4, y: 2)
                    }
                    .accessibilityLabel(AppCopy.sharedMediaRandomMedia)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                }
            }
        }
        .navigationTitle(AppCopy.sharedMediaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .overlay {
            if store.isImporting || store.isTransferringArchive {
                ProgressView(AppCopy.sharedMediaProcessing)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 10)
            }
        }
        .task { await store.importIncomingAndRefresh() }
        .onChange(of: filter) { _, _ in randomItems = nil }
        .sheet(isPresented: $showsArchiveExporter, onDismiss: clearTemporaryArchive) {
            if let archiveURL {
                SharedMediaDocumentExporter(urls: [archiveURL])
            }
        }
        .fileImporter(
            isPresented: $showsArchiveImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false,
            onCompletion: importArchive
        )
        .alert(item: $transferAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppCopy.commonOK))
            )
        }
        .alert(AppCopy.sharedMediaEditNote, isPresented: noteAlertBinding) {
            TextField(AppCopy.sharedMediaNotePlaceholder, text: $noteText)
            Button(AppCopy.commonClear) { noteText = "" }
            Button(AppCopy.sharedMediaSaveNote) { saveNote() }
            Button(AppCopy.commonClose, role: .cancel) {}
        }
    }

    private var listContent: some View {
        List(displayedItems) { item in
            destinationLink(for: item) {
                switch item {
                case .gallery(let gallery):
                    SharedMediaGalleryListRow(gallery: gallery)
                case .media(let record):
                    SharedMediaListRow(record: record)
                }
            }
            .contextMenu { itemActions(for: item) }
        }
        .listStyle(.plain)
        .refreshable { await resetRandomModeAndRefresh() }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Color.clear
                    .frame(height: 0)
                    .id(Self.scrollTopID)

                ForEach(layoutRows) { row in
                    switch row {
                    case .tiles(let items):
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                destinationLink(for: item) {
                                    switch item {
                                    case .gallery(let gallery):
                                        SharedMediaGalleryGridCard(gallery: gallery)
                                    case .media(let record):
                                        SharedMediaGridCard(record: record)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu { itemActions(for: item) }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }

                            if items.count == 1 {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    case .video(let record):
                        destinationLink(for: .media(record)) {
                            SharedMediaVideoRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { mediaActions(for: record) }
                    }
                }
            }
            .padding(12)
            .padding(.bottom, filteredItems.isEmpty ? 0 : 64)
        }
        .refreshable { await resetRandomModeAndRefresh() }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if displayedItems.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    mediaFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AppCopy.sharedMediaEmptyTitle
                        : AppCopy.sharedMediaNoMatchingTitle,
                    systemImage: "square.and.arrow.down",
                    description: Text(
                        mediaFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppCopy.sharedMediaEmptyMessage
                            : AppCopy.sharedMediaNoMatchingMessage
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            }
            .refreshable { await resetRandomModeAndRefresh() }
        } else if usesGridLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var filterControls: some View {
        VStack(spacing: 8) {
            Picker(AppCopy.sharedMediaFilterTitle, selection: $filter) {
                ForEach(SharedMediaFilter.allCases) { filter in
                    Text(filterTitle(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            ClearableSearchTextField(
                title: AppCopy.sharedMediaFilterPlaceholder,
                text: $mediaFilterText,
                submitLabel: .done
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if randomItems == nil, filter != .videos, filter != .favoriteVideos {
                Button {
                    layoutModeRaw = (layoutMode == .list ? CollectionLayoutMode.grid : .list).rawValue
                } label: {
                    Image(systemName: layoutMode == .list ? "square.grid.2x2" : "list.bullet")
                }
                .accessibilityLabel(AppCopy.sharedMediaLayoutTitle)
            }

            Menu {
                Button { exportArchive() } label: {
                    Label(AppCopy.sharedMediaExportArchive, systemImage: "square.and.arrow.up")
                }
                Button { showsArchiveImporter = true } label: {
                    Label(AppCopy.sharedMediaImportArchive, systemImage: "square.and.arrow.down")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(AppCopy.sharedMediaMoreActions)
        }
    }

    @ViewBuilder
    private func destinationLink<Label: View>(
        for item: SharedMediaDisplayItem,
        @ViewBuilder label: () -> Label
    ) -> some View {
        switch item {
        case .gallery(let gallery):
            NavigationLink {
                SharedMediaGalleryView(galleryID: gallery.id)
            } label: {
                label()
            }
        case .media(let record):
            if record.kind == .image {
                NavigationLink {
                    SharedImageReaderView(
                        records: readerRecords(for: record),
                        initialRecordID: record.id
                    )
                } label: {
                    label()
                }
            } else {
                NavigationLink {
                    SharedVideoPlayerView(recordID: record.id)
                } label: {
                    label()
                }
            }
        }
    }

    @ViewBuilder
    private func itemActions(for item: SharedMediaDisplayItem) -> some View {
        switch item {
        case .gallery(let gallery):
            Button(role: .destructive) {
                store.delete(gallery)
            } label: {
                Label(AppCopy.sharedMediaDeleteGallery, systemImage: "trash")
            }
        case .media(let record):
            mediaActions(for: record)
        }
    }

    @ViewBuilder
    private func mediaActions(for record: SharedMediaRecord) -> some View {
        Button {
            store.toggleFavorite(record)
        } label: {
            Label(
                record.isFavorite ? AppCopy.sharedMediaUnfavorite : AppCopy.sharedMediaFavorite,
                systemImage: record.isFavorite ? "heart.slash" : "heart"
            )
        }

        if record.kind == .video, record.isFavorite {
            Button { store.moveFavoriteToFront(record) } label: {
                Label(AppCopy.libraryMoveImageFavoriteToFront, systemImage: "arrow.up.to.line")
            }
            Button { store.moveFavorite(record, direction: -1) } label: {
                Label(AppCopy.libraryMoveImageFavoriteUp, systemImage: "arrow.up")
            }
            Button { store.moveFavorite(record, direction: 1) } label: {
                Label(AppCopy.libraryMoveImageFavoriteDown, systemImage: "arrow.down")
            }
        }

        Button {
            editingRecord = record
            noteText = record.note ?? ""
        } label: {
            Label(AppCopy.sharedMediaEditNote, systemImage: "note.text")
        }

        ShareLink(item: store.fileURL(for: record)) {
            Label(AppCopy.sharedMediaShareAgain, systemImage: "square.and.arrow.up")
        }

        Button(role: .destructive) {
            store.delete(record)
        } label: {
            Label(AppCopy.sharedMediaDelete, systemImage: "trash")
        }
    }

    private var filteredItems: [SharedMediaDisplayItem] {
        let sourceItems: [SharedMediaDisplayItem]
        switch filter {
        case .all:
            let galleryMemberIDs = Set(store.galleries.flatMap(\.memberIDs))
            sourceItems = (
                store.galleries.map(SharedMediaDisplayItem.gallery)
                    + store.records
                        .filter { !galleryMemberIDs.contains($0.id) }
                        .map(SharedMediaDisplayItem.media)
            ).sorted { $0.importedAt > $1.importedAt }
        case .images:
            sourceItems = store.imageRecords.map(SharedMediaDisplayItem.media)
        case .videos:
            sourceItems = store.videoRecords.map(SharedMediaDisplayItem.media)
        case .favoriteVideos:
            sourceItems = store.favoriteVideos.map(SharedMediaDisplayItem.media)
        }

        let trimmedFilterText = mediaFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilterText.isEmpty else { return sourceItems }
        return sourceItems.filter { item in
            switch item {
            case .gallery(let gallery):
                return gallery.title.localizedCaseInsensitiveContains(trimmedFilterText)
                    || store.records(in: gallery).contains { record in
                        record.originalFilename.localizedCaseInsensitiveContains(trimmedFilterText)
                            || (record.note?.localizedCaseInsensitiveContains(trimmedFilterText) ?? false)
                    }
            case .media(let record):
                return record.originalFilename.localizedCaseInsensitiveContains(trimmedFilterText)
                    || (record.note?.localizedCaseInsensitiveContains(trimmedFilterText) ?? false)
            }
        }
    }

    private var displayedItems: [SharedMediaDisplayItem] {
        guard let randomItems else { return filteredItems }
        return randomItems.filter { randomItem in
            filteredItems.contains(where: { $0.id == randomItem.id })
        }
    }

    /// Groups images into pairs while keeping every video on its own row.
    private var layoutRows: [SharedMediaLayoutRow] {
        var rows: [SharedMediaLayoutRow] = []
        var pendingTiles: [SharedMediaDisplayItem] = []

        func flushTiles() {
            guard !pendingTiles.isEmpty else { return }
            rows.append(.tiles(pendingTiles))
            pendingTiles = []
        }

        for item in displayedItems {
            if case .media(let record) = item, record.kind == .video {
                flushTiles()
                rows.append(.video(record))
            } else {
                pendingTiles.append(item)
                if pendingTiles.count == 2 {
                    flushTiles()
                }
            }
        }
        flushTiles()
        return rows
    }

    /// Enters random mode and scrolls after the grid replaces the current layout.
    private func showRandomItems(scrollProxy: ScrollViewProxy) {
        randomItems = Array(filteredItems.shuffled().prefix(10))
        Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(Self.scrollTopID, anchor: .top)
        }
    }

    /// Leaves random mode before synchronizing new shared files.
    private func resetRandomModeAndRefresh() async {
        randomItems = nil
        await store.importIncomingAndRefresh()
    }

    private var usesGridLayout: Bool {
        randomItems != nil
            || filter == .videos
            || filter == .favoriteVideos
            || layoutMode == .grid
    }

    private var layoutMode: CollectionLayoutMode {
        CollectionLayoutMode(rawValue: layoutModeRaw) ?? .grid
    }

    private var noteAlertBinding: Binding<Bool> {
        Binding {
            editingRecord != nil
        } set: { isPresented in
            if !isPresented { editingRecord = nil }
        }
    }

    /// Returns images from the selected share batch in import order.
    private func readerRecords(for record: SharedMediaRecord) -> [SharedMediaRecord] {
        if let gallery = store.galleries(containing: record).first {
            let galleryImages = store.records(in: gallery).filter { $0.kind == .image }
            if !galleryImages.isEmpty { return galleryImages }
        }
        let batchRecords = store.imageRecords
            .filter { $0.batchID == record.batchID }
            .sorted { $0.importedAt < $1.importedAt }
        return batchRecords.isEmpty ? store.imageRecords : batchRecords
    }

    /// Returns the localized filter label.
    private func filterTitle(_ filter: SharedMediaFilter) -> String {
        switch filter {
        case .all: AppCopy.sharedMediaFilterAll
        case .images: AppCopy.sharedMediaFilterImages
        case .videos: AppCopy.sharedMediaFilterVideos
        case .favoriteVideos: AppCopy.sharedMediaFilterFavoriteVideos
        }
    }

    /// Persists the note edited in the compact alert.
    private func saveNote() {
        guard let editingRecord else { return }
        store.setNote(noteText, for: editingRecord)
        self.editingRecord = nil
    }

    /// Creates the ZIP on a utility task before opening the document exporter.
    private func exportArchive() {
        Task {
            do {
                archiveURL = try await store.createArchive()
                showsArchiveExporter = true
            } catch {
                transferAlert = SharedMediaTransferAlert(
                    title: AppCopy.sharedMediaExportFailed,
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Imports one security-scoped ZIP selected from Files.
    private func importArchive(_ result: Result<[URL], Error>) {
        Task {
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                try await store.importArchive(from: url)
                await store.importIncomingAndRefresh()
                transferAlert = SharedMediaTransferAlert(
                    title: AppCopy.sharedMediaImportSucceeded,
                    message: AppCopy.sharedMediaImportSucceededMessage
                )
            } catch {
                transferAlert = SharedMediaTransferAlert(
                    title: AppCopy.sharedMediaImportFailed,
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Removes a generated ZIP after the system exporter closes.
    private func clearTemporaryArchive() {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent())
        self.archiveURL = nil
    }
}

/// Represents one top-level entry in the shared media screen.
private enum SharedMediaDisplayItem: Identifiable, Hashable {
    case gallery(SharedMediaGalleryRecord)
    case media(SharedMediaRecord)

    var id: String {
        switch self {
        case .gallery(let gallery): "gallery-\(gallery.id.uuidString)"
        case .media(let record): "media-\(record.id.uuidString)"
        }
    }

    var importedAt: Date {
        switch self {
        case .gallery(let gallery): gallery.importedAt
        case .media(let record): record.importedAt
        }
    }
}

/// Describes one visual row containing either two images or one video.
private enum SharedMediaLayoutRow: Identifiable {
    case tiles([SharedMediaDisplayItem])
    case video(SharedMediaRecord)

    var id: String {
        switch self {
        case .tiles(let items):
            return "tiles-\(items.map(\.id).joined(separator: "-"))"
        case .video(let record):
            return "video-\(record.id.uuidString)"
        }
    }
}

/// Displays one folder gallery as a compact list row.
private struct SharedMediaGalleryListRow: View {
    @EnvironmentObject private var store: SharedMediaStore
    let gallery: SharedMediaGalleryRecord

    var body: some View {
        HStack(spacing: 12) {
            galleryCover
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            SharedMediaGalleryDetails(gallery: gallery)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var galleryCover: some View {
        if let coverRecord = store.records.first(where: { $0.id == gallery.coverMediaID }) {
            SharedMediaThumbnail(record: coverRecord)
        } else {
            Color.secondary.opacity(0.12)
                .overlay { Image(systemName: "photo.on.rectangle.angled") }
        }
    }
}

/// Displays one folder gallery as a stable square grid card.
private struct SharedMediaGalleryGridCard: View {
    @EnvironmentObject private var store: SharedMediaStore
    let gallery: SharedMediaGalleryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                galleryCover
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .aspectRatio(1, contentMode: .fit)

            SharedMediaGalleryDetails(gallery: gallery)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var galleryCover: some View {
        if let coverRecord = store.records.first(where: { $0.id == gallery.coverMediaID }) {
            SharedMediaThumbnail(record: coverRecord)
        } else {
            Color.secondary.opacity(0.12)
                .overlay { Image(systemName: "photo.on.rectangle.angled") }
        }
    }
}

/// Displays local gallery title and member count.
private struct SharedMediaGalleryDetails: View {
    let gallery: SharedMediaGalleryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "photo.on.rectangle.angled")
                Text(gallery.title)
                    .lineLimit(2)
            }
            .font(.subheadline.weight(.semibold))

            Text("\(gallery.memberIDs.count) \(AppCopy.sharedMediaGalleryItems)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Displays one shared media row with thumbnail and storage details.
private struct SharedMediaListRow: View {
    let record: SharedMediaRecord

    var body: some View {
        HStack(spacing: 12) {
            SharedMediaThumbnail(record: record)
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            SharedMediaCardDetails(record: record)
        }
        .padding(.vertical, 4)
    }
}

/// Displays one adaptive shared media grid card.
private struct SharedMediaGridCard: View {
    let record: SharedMediaRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                SharedMediaThumbnail(record: record)
                    .frame(width: proxy.size.width, height: proxy.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .aspectRatio(1, contentMode: .fit)

            SharedMediaCardDetails(record: record)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}


/// Displays one video as a full-width row with a stable widescreen preview.
private struct SharedMediaVideoRow: View {
    let record: SharedMediaRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                SharedMediaThumbnail(record: record)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            SharedMediaCardDetails(record: record)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Displays shared metadata consistently in list and grid layouts.
private struct SharedMediaCardDetails: View {
    let record: SharedMediaRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: record.kind == .image ? "photo" : "video")
                Text(record.displayName)
                    .lineLimit(2)
            }
            .font(.subheadline.weight(.semibold))

            HStack {
                if let duration = record.duration, record.kind == .video {
                    Text(duration.formattedDuration)
                }
                Text(ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                if record.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Displays one shared folder as an ordered mixed-media gallery.
private struct SharedMediaGalleryView: View {
    @EnvironmentObject private var store: SharedMediaStore
    let galleryID: UUID
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
        count: 3
    )

    var body: some View {
        Group {
            if let gallery {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(records) { record in
                            destinationLink(for: record) {
                                VStack(alignment: .leading, spacing: 5) {
                                    GeometryReader { proxy in
                                        SharedMediaThumbnail(record: record)
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                    }
                                    .aspectRatio(0.72, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))

                                    Text(record.displayName)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
                .navigationTitle(gallery.title)
            } else {
                ContentUnavailableView(AppCopy.sharedMediaGallery, systemImage: "photo.on.rectangle.angled")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gallery: SharedMediaGalleryRecord? {
        store.galleries.first { $0.id == galleryID }
    }

    private var records: [SharedMediaRecord] {
        guard let gallery else { return [] }
        return store.records(in: gallery)
    }

    private var imageRecords: [SharedMediaRecord] {
        records.filter { $0.kind == .image }
    }

    @ViewBuilder
    private func destinationLink<Label: View>(
        for record: SharedMediaRecord,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if record.kind == .image {
            NavigationLink {
                SharedImageReaderView(records: imageRecords, initialRecordID: record.id)
            } label: {
                label()
            }
        } else {
            NavigationLink {
                SharedVideoPlayerView(recordID: record.id)
            } label: {
                label()
            }
        }
    }
}

/// Generates a local image or video thumbnail without loading full media into SwiftUI.
struct SharedMediaThumbnail: View {
    @EnvironmentObject private var store: SharedMediaStore
    let record: SharedMediaRecord
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: record.kind == .image ? "photo" : "video")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if record.kind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
        }
        .clipped()
        .task(id: record.id) {
            image = await Self.thumbnail(for: store.fileURL(for: record))
        }
    }

    /// Requests a system thumbnail suitable for images and videos.
    private static func thumbnail(for url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 420, height: 420),
                scale: UIScreen.main.scale,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }
}

/// Exports a generated ZIP through the system document picker without loading it into memory.
private struct SharedMediaDocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]

    /// Creates a copy-based Files exporter for one generated archive.
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    }

    /// Keeps the document picker immutable while presented.
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

/// Stores one archive transfer result for presentation.
private struct SharedMediaTransferAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension Double {
    /// Formats media duration as minutes and seconds.
    var formattedDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
