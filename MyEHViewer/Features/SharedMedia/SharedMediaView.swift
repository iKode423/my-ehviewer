import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Manages persistent images and videos received from other applications.
struct SharedMediaView: View {
    @EnvironmentObject private var store: SharedMediaStore
    @AppStorage("SharedMedia.layoutMode") private var layoutModeRaw = CollectionLayoutMode.grid.rawValue
    @State private var filter = SharedMediaFilter.all
    @State private var mediaFilterText = ""
    @State private var randomRecords: [SharedMediaRecord]?
    @State private var archiveURL: URL?
    @State private var showsArchiveExporter = false
    @State private var showsArchiveImporter = false
    @State private var transferAlert: SharedMediaTransferAlert?
    @State private var editingRecord: SharedMediaRecord?
    @State private var noteText = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                filterControls
                Divider()
                mediaContent
            }

            if !filteredRecords.isEmpty {
                Button { showRandomRecords() } label: {
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
        .onChange(of: filter) { _, _ in randomRecords = nil }
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
        List(displayedRecords) { record in
            destinationLink(for: record) {
                SharedMediaListRow(record: record)
            }
            .contextMenu { mediaActions(for: record) }
        }
        .listStyle(.plain)
        .refreshable { await resetRandomModeAndRefresh() }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(layoutRows) { row in
                    switch row {
                    case .images(let records):
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(records) { record in
                                destinationLink(for: record) {
                                    SharedMediaGridCard(record: record)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { mediaActions(for: record) }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }

                            if records.count == 1 {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    case .video(let record):
                        destinationLink(for: record) {
                            SharedMediaVideoRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { mediaActions(for: record) }
                    }
                }
            }
            .padding(12)
            .padding(.bottom, filteredRecords.isEmpty ? 0 : 64)
        }
        .refreshable { await resetRandomModeAndRefresh() }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if displayedRecords.isEmpty {
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
            if randomRecords == nil, filter != .videos, filter != .favoriteVideos {
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
        for record: SharedMediaRecord,
        @ViewBuilder label: () -> Label
    ) -> some View {
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

    private var filteredRecords: [SharedMediaRecord] {
        let sourceRecords: [SharedMediaRecord]
        switch filter {
        case .all: sourceRecords = store.records.sorted { $0.importedAt > $1.importedAt }
        case .images: sourceRecords = store.imageRecords
        case .videos: sourceRecords = store.videoRecords
        case .favoriteVideos: sourceRecords = store.favoriteVideos
        }

        let trimmedFilterText = mediaFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilterText.isEmpty else { return sourceRecords }
        return sourceRecords.filter { record in
            record.originalFilename.localizedCaseInsensitiveContains(trimmedFilterText)
                || (record.note?.localizedCaseInsensitiveContains(trimmedFilterText) ?? false)
        }
    }

    private var displayedRecords: [SharedMediaRecord] {
        guard let randomRecords else { return filteredRecords }
        return randomRecords.filter { randomRecord in
            filteredRecords.contains(where: { $0.id == randomRecord.id })
        }
    }

    /// Groups images into pairs while keeping every video on its own row.
    private var layoutRows: [SharedMediaLayoutRow] {
        var rows: [SharedMediaLayoutRow] = []
        var pendingImages: [SharedMediaRecord] = []

        func flushImages() {
            guard !pendingImages.isEmpty else { return }
            rows.append(.images(pendingImages))
            pendingImages = []
        }

        for record in displayedRecords {
            if record.kind == .video {
                flushImages()
                rows.append(.video(record))
            } else {
                pendingImages.append(record)
                if pendingImages.count == 2 {
                    flushImages()
                }
            }
        }
        flushImages()
        return rows
    }

    /// Enters random mode with up to ten records from the active filter.
    private func showRandomRecords() {
        randomRecords = Array(filteredRecords.shuffled().prefix(10))
    }

    /// Leaves random mode before synchronizing new shared files.
    private func resetRandomModeAndRefresh() async {
        randomRecords = nil
        await store.importIncomingAndRefresh()
    }

    private var usesGridLayout: Bool {
        randomRecords != nil
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


/// Describes one visual row containing either two images or one video.
private enum SharedMediaLayoutRow: Identifiable {
    case images([SharedMediaRecord])
    case video(SharedMediaRecord)

    var id: String {
        switch self {
        case .images(let records):
            return "images-\(records.map { $0.id.uuidString }.joined(separator: "-"))"
        case .video(let record):
            return "video-\(record.id.uuidString)"
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
