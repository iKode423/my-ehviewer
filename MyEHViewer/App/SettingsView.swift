import Charts
import SwiftUI

/// Shows local data controls and reader-related preferences.
struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @AppStorage(ContentSite.storageKey) private var contentSiteRaw = ContentSite.eHentai.rawValue
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw = AppThemeMode.system.rawValue
    @AppStorage(AppAccentColor.storageKey) private var accentColorHex = AppAccentColor.defaultHex
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderZoomLevel.storageKey) private var zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    @State private var cookieInput = ""
    @State private var showsClearConfirmation = false
    @State private var showsCookieClearConfirmation = false
    @State private var showsImageCacheClearConfirmation = false
    @State private var showsNonGalleryImageCacheClearConfirmation = false
    @State private var accentRefreshID = UUID()

    var body: some View {
        NavigationStack {
            List {
                contentSiteSection
                appearanceSection
                readerPreferencesSection
                cachePolicySection
                imageCacheSection
                localDataSection
                siteAccessSection
            }
            .navigationTitle(AppCopy.settingsTitle)
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)
            .id(accentRefreshID)
            .onAppear {
                cookieInput = siteCookieStore.cookieHeader
                imageCacheStore.refresh()
            }
            .onChange(of: accentColorHex) { _, _ in
                accentRefreshID = UUID()
            }
        }
    }

    /// Shows app-wide appearance controls.
    private var contentSiteSection: some View {
        Section(AppCopy.settingsContentSiteTitle) {
            Picker(AppCopy.settingsContentSitePicker, selection: $contentSiteRaw) {
                ForEach(ContentSite.allCases) { site in
                    Text(site.title).tag(site.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)
        }
    }

    /// Shows app-wide appearance controls.
    private var appearanceSection: some View {
        Section(AppCopy.settingsAppearanceTitle) {
            Picker(AppCopy.settingsThemeMode, selection: $themeModeRaw) {
                ForEach(AppThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)

            ColorPicker(AppCopy.settingsAccentColor, selection: accentColorBinding, supportsOpacity: false)
                .accentColor(settingsAccentColor)
                .tint(settingsAccentColor)
        }
    }

    /// Resolves the current custom accent color for controls hosted by this settings stack.
    private var settingsAccentColor: Color {
        AppAccentColor.color(from: accentColorHex)
    }

    /// Bridges the persisted hex value into SwiftUI's color picker binding.
    private var accentColorBinding: Binding<Color> {
        Binding {
            settingsAccentColor
        } set: { color in
            accentColorHex = AppAccentColor.hex(from: color)
        }
    }

    /// Shows reader display preferences shared with ReaderView.
    private var readerPreferencesSection: some View {
        Section(AppCopy.settingsReaderPreferencesTitle) {
            Picker(AppCopy.readerDisplayMode, selection: $fitModeRaw) {
                ForEach(ReaderFitMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)

            Picker(AppCopy.readerZoomMode, selection: $zoomLevelRaw) {
                ForEach(ReaderZoomLevel.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)

            Picker(AppCopy.readerBackgroundMode, selection: $backgroundModeRaw) {
                ForEach(ReaderBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .accentColor(settingsAccentColor)
            .tint(settingsAccentColor)
        }
    }

    /// Shows account cookie controls used by network requests.
    private var siteAccessSection: some View {
        Section(AppCopy.settingsSiteAccessTitle) {
            Label(
                siteCookieStore.hasCookieHeader ? AppCopy.settingsCookieConfigured : AppCopy.settingsCookieMissing,
                systemImage: siteCookieStore.hasCookieHeader ? "checkmark.seal" : "exclamationmark.triangle"
            )

            SecureField(AppCopy.settingsCookieField, text: $cookieInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                siteCookieStore.saveCookieHeader(cookieInput)
                cookieInput = siteCookieStore.cookieHeader
            } label: {
                Label(AppCopy.settingsCookieSave, systemImage: "key")
            }
            .disabled(cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                showsCookieClearConfirmation = true
            } label: {
                Label(AppCopy.settingsCookieClear, systemImage: "trash")
            }
            .disabled(!siteCookieStore.hasCookieHeader)
            .confirmationDialog(
                AppCopy.settingsCookieClearTitle,
                isPresented: $showsCookieClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsCookieClearConfirm, role: .destructive) {
                    siteCookieStore.clearCookieHeader()
                    cookieInput = ""
                }
            }

            if let errorMessage = siteCookieStore.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    /// Shows local library counters and destructive cleanup controls.
    private var localDataSection: some View {
        Section(AppCopy.settingsLocalDataTitle) {
            Label(String(format: AppCopy.settingsHistoryCount, String(libraryStore.history(for: currentSite).count)), systemImage: "clock")
            Label(String(format: AppCopy.settingsFavoritesCount, String(libraryStore.favorites(for: currentSite).count)), systemImage: "star")

            NavigationLink {
                LocalStatisticsView()
                    .environmentObject(libraryStore)
            } label: {
                Label(AppCopy.settingsStatistics, systemImage: "chart.bar.xaxis")
            }

            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearLocalData, systemImage: "trash")
            }
            .disabled(libraryStore.history(for: currentSite).isEmpty && libraryStore.favorites(for: currentSite).isEmpty)
            .confirmationDialog(
                AppCopy.settingsClearConfirmationTitle,
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsClearConfirm, role: .destructive) {
                    libraryStore.removeAll(for: currentSite)
                }
            } message: {
                Text(AppCopy.settingsClearConfirmationMessage)
            }
        }
    }

    /// Shows image cache usage and cleanup controls.
    private var imageCacheSection: some View {
        Section(AppCopy.settingsImageCacheTitle) {
            Label(imageCacheUsageText, systemImage: "photo.stack")
                .foregroundStyle(.secondary)

            NavigationLink {
                ImageCacheManagementView()
            } label: {
                Label(AppCopy.settingsImageCacheManage, systemImage: "externaldrive")
            }
            .disabled(currentSiteGallerySummaries.isEmpty)

            Button(role: .destructive) {
                showsImageCacheClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearImageCache, systemImage: "trash")
            }
            .disabled(currentSiteGallerySummaries.isEmpty)
            .confirmationDialog(
                AppCopy.settingsImageCacheClearTitle,
                isPresented: $showsImageCacheClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsImageCacheClearConfirm, role: .destructive) {
                    for summary in currentSiteGallerySummaries {
                        imageCacheStore.clearGallery(summary.galleryIdentifier)
                    }
                }
            } message: {
                Text(AppCopy.settingsImageCacheClearMessage)
            }

            Button(role: .destructive) {
                showsNonGalleryImageCacheClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearNonGalleryImageCache, systemImage: "photo")
            }
            .disabled(!imageCacheStore.hasNonGalleryImageCache)
            .confirmationDialog(
                AppCopy.settingsNonGalleryImageCacheClearTitle,
                isPresented: $showsNonGalleryImageCacheClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsNonGalleryImageCacheClearConfirm, role: .destructive) {
                    imageCacheStore.clearNonGalleryImages()
                }
            } message: {
                Text(AppCopy.settingsNonGalleryImageCacheClearMessage)
            }
        }
    }

    private var imageCacheUsageText: String {
        let summaries = currentSiteGallerySummaries
        if summaries.isEmpty {
            return AppCopy.settingsImageCacheEmpty
        }
        let byteCount = summaries.reduce(Int64(0)) { $0 + $1.byteCount }
        return String(
            format: AppCopy.settingsImageCacheGalleryUsageFormat,
            String(summaries.count),
            ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        )
    }

    private var currentSite: ContentSite {
        ContentSite.resolved(rawValue: contentSiteRaw)
    }

    private var currentSiteGallerySummaries: [CachedGallerySummary] {
        imageCacheStore.gallerySummaries.filter { $0.galleryIdentifier.site == currentSite }
    }

    /// Explains the current remote-content cache policy.
    private var cachePolicySection: some View {
        Section(AppCopy.settingsCacheNoteTitle) {
            Label(AppCopy.settingsCacheNoteMessage, systemImage: "internaldrive")
                .foregroundStyle(.secondary)
        }
    }
}

/// Lists cached galleries and opens their detail pages.
private struct ImageCacheManagementView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @StateObject private var downloadManager = GalleryDownloadManager.shared
    @AppStorage(ContentSite.storageKey) private var contentSiteRaw = ContentSite.eHentai.rawValue
    @State private var galleryFilterText = ""

    var body: some View {
        Group {
            if currentSiteGallerySummaries.isEmpty {
                ContentUnavailableView(
                    AppCopy.cacheManagementEmptyTitle,
                    systemImage: "externaldrive",
                    description: Text(AppCopy.cacheManagementEmptyMessage)
                )
            } else {
                List {
                    Section {
                        ClearableSearchTextField(
                            title: AppCopy.cacheManagementFilterPlaceholder,
                            text: $galleryFilterText,
                            submitLabel: .done
                        )
                    }

                    cacheDownloadControls

                    if filteredGallerySummaries.isEmpty {
                        ContentUnavailableView.search(text: galleryFilterText)
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredGallerySummaries) { summary in
                            NavigationLink {
                                CachedGalleryEntryView(summary: summary)
                                    .environmentObject(libraryStore)
                            } label: {
                                cachedGalleryRow(summary)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    imageCacheStore.clearGallery(summary.galleryIdentifier)
                                } label: {
                                    Label(AppCopy.cacheManagementDeleteGallery, systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: deleteCachedGalleries)
                    }
                }
            }
        }
        .navigationTitle(AppCopy.cacheManagementTitle)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            imageCacheStore.refresh()
        }
    }

    /// Shows the bulk download action and current aggregate download status.
    @ViewBuilder
    private var cacheDownloadControls: some View {
        if downloadManager.aggregateProgress != nil || !unfinishedSummaries.isEmpty {
            Section {
                Button {
                    if downloadManager.aggregateProgress == nil {
                        downloadManager.startUnfinishedDownloads(from: currentSiteGallerySummaries)
                    } else {
                        downloadManager.pauseAllDownloads()
                    }
                } label: {
                    Label(cacheDownloadButtonTitle, systemImage: cacheDownloadButtonSystemImage)
                        .frame(minHeight: 44, alignment: .leading)
                }

                if let aggregateProgress = downloadManager.aggregateProgress {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(AppCopy.cacheManagementProgressTitle, systemImage: "speedometer")
                            .font(.headline)

                        ProgressView(value: aggregateProgress.progressFraction)
                            .tint(.accentColor)

                        HStack {
                            Text(aggregateProgress.progressText)
                            Spacer()
                            Text(aggregateProgress.speedText)
                                .monospacedDigit()
                        }
                        .font(.subheadline)

                        HStack(spacing: 12) {
                            Label(aggregateProgress.activeDownloadText, systemImage: "arrow.down")
                            if aggregateProgress.queuedDownloadCount > 0 {
                                Label(aggregateProgress.queuedDownloadText, systemImage: "clock")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    /// Returns the bulk download button title for the current queue state.
    private var cacheDownloadButtonTitle: String {
        downloadManager.aggregateProgress == nil ? AppCopy.cacheManagementStartUnfinished : AppCopy.cacheManagementPauseAllDownloads
    }

    /// Returns the bulk download button icon for the current queue state.
    private var cacheDownloadButtonSystemImage: String {
        downloadManager.aggregateProgress == nil ? "arrow.down.circle" : "pause.circle"
    }

    /// Renders one cached gallery summary row.
    private func cachedGalleryRow(_ summary: CachedGallerySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GalleryTitleText(
                title: summary.title,
                note: summary.note,
                titleFont: .headline,
                originalTitleFont: .caption
            )
                .lineLimit(2)

            HStack {
                Label(summary.progressText, systemImage: "checkmark.circle")
                Spacer()
                Text(summary.localizedByteCount)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if summary.isDownloadUnavailable {
                Label(AppCopy.cacheManagementUnavailable, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    /// Removes cached data for galleries selected from the management list.
    private func deleteCachedGalleries(at offsets: IndexSet) {
        let summaries = filteredGallerySummaries
        for offset in offsets where summaries.indices.contains(offset) {
            imageCacheStore.clearGallery(summaries[offset].galleryIdentifier)
        }
    }

    /// Returns cached galleries that still have pages missing from the local cache.
    private var filteredGallerySummaries: [CachedGallerySummary] {
        let trimmedFilterText = galleryFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilterText.isEmpty else {
            return currentSiteGallerySummaries
        }
        return currentSiteGallerySummaries.filter { summary in
            summary.title.localizedCaseInsensitiveContains(trimmedFilterText)
                || (summary.note?.localizedCaseInsensitiveContains(trimmedFilterText) ?? false)
        }
    }

    private var unfinishedSummaries: [CachedGallerySummary] {
        currentSiteGallerySummaries.filter { summary in
            guard let totalPageCount = summary.totalPageCount else { return false }
            return !summary.isDownloadUnavailable && summary.cachedPageCount < totalPageCount
        }
    }

    private var currentSite: ContentSite {
        ContentSite.resolved(rawValue: contentSiteRaw)
    }

    private var currentSiteGallerySummaries: [CachedGallerySummary] {
        imageCacheStore.gallerySummaries.filter { $0.galleryIdentifier.site == currentSite }
    }
}

private struct CachedGalleryNoteField: View {
    let summary: CachedGallerySummary
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @State private var noteText: String
    @State private var isEditing = false
    @FocusState private var noteFieldIsFocused: Bool

    /// Creates an inline editor for one cached gallery note.
    init(summary: CachedGallerySummary) {
        self.summary = summary
        _noteText = State(initialValue: summary.note ?? "")
    }

    var body: some View {
        Group {
            if isEditing {
                editor
            } else {
                collapsedNote
            }
        }
        .accessibilityLabel(AppCopy.cacheManagementNoteField)
        .onChange(of: summary.note) { _, note in
            guard !isEditing else { return }
            noteText = note ?? ""
        }
    }

    private var collapsedNote: some View {
        Button {
            noteText = imageCacheStore.note(for: summary.galleryIdentifier) ?? summary.note ?? ""
            isEditing = true
            DispatchQueue.main.async {
                noteFieldIsFocused = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)

                Text(displayedNoteText)
                    .font(.subheadline)
                    .foregroundStyle(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var editor: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)

            TextField(AppCopy.cacheManagementNotePlaceholder, text: $noteText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.subheadline)
                .submitLabel(.done)
                .focused($noteFieldIsFocused)
                .onSubmit {
                    saveNoteAndCollapse()
                }

            if !noteText.isEmpty {
                Button {
                    noteText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                saveNoteAndCollapse()
            } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onChange(of: noteFieldIsFocused) { oldValue, newValue in
            if oldValue && !newValue {
                saveNoteAndCollapse()
            }
        }
    }

    private var displayedNoteText: String {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNote.isEmpty ? AppCopy.cacheManagementNotePlaceholder : trimmedNote
    }

    /// Saves the note once editing finishes to avoid refreshing the cache index on each keystroke.
    private func saveNoteAndCollapse() {
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedNote = imageCacheStore.note(for: summary.galleryIdentifier) ?? ""
        if trimmedNote != storedNote {
            imageCacheStore.setGalleryNote(trimmedNote, for: summary.galleryIdentifier)
        }
        noteText = trimmedNote
        isEditing = false
        noteFieldIsFocused = false
    }
}

/// Opens cached galleries without requiring the remote detail page to load first.
private struct CachedGalleryEntryView: View {
    let summary: CachedGallerySummary
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @StateObject private var imageCacheStore = ImageCacheStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cacheSummaryHeader

                CachedGalleryNoteField(summary: summary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(displayPageNumbers, id: \.self) { pageNumber in
                        cachedPageTile(pageNumber: pageNumber, record: cachedPageRecordByNumber[pageNumber])
                    }
                }
            }
            .padding()
        }
        .navigationTitle(currentNote ?? summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                NavigationLink {
                    GalleryDetailView(result: summary.searchResult)
                } label: {
                    Label(AppCopy.cacheManagementOpenGallery, systemImage: "info.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let cachedResumeURL {
                    Button {
                        openCachedReader(from: cachedResumeURL)
                    } label: {
                        Label(cachedResumeButtonTitle, systemImage: "book")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    /// Reads the latest note so edits on this page update the title immediately.
    private var currentNote: String? {
        imageCacheStore.note(for: summary.galleryIdentifier) ?? summary.note
    }

    /// Shows cache progress and storage usage for the opened gallery.
    private var cacheSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            GalleryTitleText(
                title: summary.title,
                note: currentNote,
                titleFont: .title3.weight(.semibold),
                originalTitleFont: .subheadline
            )
            .lineLimit(3)

            Text(summary.progressText)
                .font(.headline)

            Text(summary.localizedByteCount)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns every known page number so missing pages can render as placeholders.
    private var displayPageNumbers: [Int] {
        let highestCachedPage = summary.pageRecords.map(\.pageNumber).max() ?? 0
        let highestKnownPage = max(summary.totalPageCount ?? 0, highestCachedPage)
        guard highestKnownPage > 0 else { return [] }
        return Array(1...highestKnownPage)
    }

    /// Maps cached records by page number for fast grid rendering.
    private var cachedPageRecordByNumber: [Int: CachedImagePageRecord] {
        Dictionary(uniqueKeysWithValues: summary.pageRecords.map { ($0.pageNumber, $0) })
    }

    /// Returns the last read page URL only when that page is already cached.
    private var cachedResumeURL: URL? {
        let cachedPageURLs = Set(cachedPageLinks.map(\.pageURL))
        return libraryStore.record(for: summary.galleryIdentifier)?.lastReadPageURL.flatMap { cachedPageURLs.contains($0) ? $0 : nil }
    }

    /// Builds the continue-reading button title with the remembered page number.
    private var cachedResumeButtonTitle: String {
        if let lastReadPage = libraryStore.record(for: summary.galleryIdentifier)?.lastReadPage {
            return String(format: AppCopy.galleryContinueReadingPage, String(lastReadPage))
        }
        return AppCopy.galleryContinueReading
    }

    /// Shows one page preview or a missing-page placeholder.
    @ViewBuilder
    private func cachedPageTile(pageNumber: Int, record: CachedImagePageRecord?) -> some View {
        if let record {
            Button {
                openCachedReader(from: record.pageURL)
            } label: {
                cachedPageTileContent(pageNumber: pageNumber, cachedImageURL: cachedImageURL(for: record))
            }
            .buttonStyle(.plain)
        } else {
            cachedPagePlaceholder(pageNumber: pageNumber)
        }
    }

    /// Builds the shared visual shell for one cached page preview.
    private func cachedPageTileContent(pageNumber: Int, cachedImageURL: URL?) -> some View {
        VStack(spacing: 6) {
            CachedRemoteImageView(url: cachedImageURL, contentMode: .fill, animationMode: .staticPreview, decodeMaxPixelSize: 420) {
                ProgressView()
            } failure: {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fit)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .clipped()

            Text(String(format: AppCopy.galleryOpenPage, String(pageNumber)))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Shows a stable tile for a page that is known but not downloaded.
    private func cachedPagePlaceholder(pageNumber: Int) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.title3)
                Text(AppCopy.cacheManagementMissingPage)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.72, contentMode: .fit)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(String(format: AppCopy.galleryOpenPage, String(pageNumber)))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Returns the remote URL whose bytes are already present in the local image cache.
    private func cachedImageURL(for record: CachedImagePageRecord) -> URL? {
        imageCacheStore.cachedImageURL(for: summary.galleryIdentifier, pageNumber: record.pageNumber)
    }

    /// Returns cached page links sorted by page number for reader navigation.
    private var cachedPageLinks: [EHGalleryPageLink] {
        summary.pageRecords.map { record in
            EHGalleryPageLink(
                pageNumber: record.pageNumber,
                pageURL: record.pageURL,
                thumbnailURL: record.thumbnailURL
            )
        }
    }

    /// Opens the reader with locally cached page links from the selected page.
    private func openCachedReader(from startURL: URL) {
        appNavigationStore.openReader(
            initialPageURL: startURL,
            pageLinks: cachedPageLinks,
            totalPageCount: summary.totalPageCount
        )
    }
}

/// Shows local library, cache, and search statistics.
private struct LocalStatisticsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var imageCacheStore = ImageCacheStore.shared

    private var snapshot: LocalStatisticsSnapshot {
        LocalStatisticsSnapshot(
            records: libraryStore.records,
            favoriteCount: libraryStore.favorites.count,
            cacheSummaries: imageCacheStore.gallerySummaries
        )
    }

    var body: some View {
        let snapshot = snapshot

        List {
            if snapshot.isEmpty {
                ContentUnavailableView(
                    AppCopy.statisticsNoDataTitle,
                    systemImage: "chart.bar.xaxis",
                    description: Text(AppCopy.statisticsNoDataMessage)
                )
            } else {
                Section(AppCopy.statisticsOverviewTitle) {
                    overviewChart(for: snapshot)
                        .frame(height: 180)
                        .padding(.vertical, 6)
                }

                if !snapshot.cachedPageDistribution.isEmpty {
                    Section(AppCopy.statisticsCachedPageDistributionTitle) {
                        cachedPageDistributionChart(for: snapshot.cachedPageDistribution)
                            .frame(height: 180)
                            .padding(.vertical, 6)
                    }
                }

                Section(AppCopy.statisticsCacheTitle) {
                    statisticsValueRow(title: AppCopy.statisticsCachedBytes, value: snapshot.localizedCacheByteCount)

                    if snapshot.knownCachedPageTotal > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                String(
                                    format: AppCopy.statisticsCacheCompletionFormat,
                                    String(snapshot.cachedPageCount),
                                    String(snapshot.knownCachedPageTotal)
                                )
                            )
                            .font(.subheadline.weight(.semibold))

                            ProgressView(value: snapshot.cacheCompletionFraction)
                                .tint(.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                }

                rankedSection(
                    title: AppCopy.statisticsFavoriteCharactersTitle,
                    items: snapshot.topCharacters,
                    emptyMessage: AppCopy.statisticsNoCharacters
                )

                rankedSection(
                    title: AppCopy.statisticsTopAuthorsTitle,
                    items: snapshot.topAuthors,
                    emptyMessage: AppCopy.statisticsNoAuthors
                )

                rankedSection(
                    title: AppCopy.statisticsTopGroupsTitle,
                    items: snapshot.topGroups,
                    emptyMessage: AppCopy.statisticsNoGroups
                )

                rankedSection(
                    title: AppCopy.statisticsTopTagsTitle,
                    items: snapshot.topTags,
                    emptyMessage: AppCopy.statisticsNoTags
                )

                rankedSection(
                    title: AppCopy.statisticsTopCategoriesTitle,
                    items: snapshot.topCategories,
                    emptyMessage: AppCopy.statisticsNoCategories
                )
            }
        }
        .navigationTitle(AppCopy.statisticsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            imageCacheStore.refresh()
        }
    }

    /// Shows the high-level local data counters as a compact bar chart.
    private func overviewChart(for snapshot: LocalStatisticsSnapshot) -> some View {
        Chart(snapshot.overviewItems) { item in
            BarMark(
                x: .value(AppCopy.statisticsOverviewTitle, item.value),
                y: .value(AppCopy.statisticsOverviewTitle, item.title)
            )
            .foregroundStyle(item.color)
            .annotation(position: .trailing) {
                Text(String(item.value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
    }

    /// Shows one key-value row inside the statistics list.
    private func statisticsValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// Shows cached gallery page-count buckets as a compact bar chart.
    private func cachedPageDistributionChart(for items: [StatisticRankedItem]) -> some View {
        Chart(items) { item in
            BarMark(
                x: .value(AppCopy.statisticsCachedGalleries, item.count),
                y: .value(AppCopy.statisticsCachedPageDistributionTitle, item.title)
            )
            .foregroundStyle(.teal)
            .annotation(position: .trailing) {
                Text(String(item.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
    }

    /// Shows ranked local metadata with progress bars.
    @ViewBuilder
    private func rankedSection(title: String, items: [StatisticRankedItem], emptyMessage: String) -> some View {
        Section(title) {
            if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.title)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(item.count))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)

                        ProgressView(value: item.fraction)
                            .tint(.accentColor)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

}

/// Stores one overview chart item.
private struct StatisticOverviewItem: Identifiable {
    let title: String
    let value: Int
    let color: Color

    var id: String { title }
}

/// Stores one ranked metadata row.
private struct StatisticRankedItem: Identifiable {
    let title: String
    let count: Int
    let maximumCount: Int

    var id: String { title }

    var fraction: Double {
        guard maximumCount > 0 else { return 0 }
        return Double(count) / Double(maximumCount)
    }
}

/// Calculates local statistics from persisted app data.
private struct LocalStatisticsSnapshot {
    let historyCount: Int
    let favoriteCount: Int
    let cachedGalleryCount: Int
    let cachedPageCount: Int
    let knownCachedPageTotal: Int
    let cacheByteCount: Int64
    let cachedPageDistribution: [StatisticRankedItem]
    let topCharacters: [StatisticRankedItem]
    let topAuthors: [StatisticRankedItem]
    let topGroups: [StatisticRankedItem]
    let topTags: [StatisticRankedItem]
    let topCategories: [StatisticRankedItem]

    /// Builds a snapshot from current stores without mutating them.
    init(
        records: [LibraryGalleryRecord],
        favoriteCount: Int,
        cacheSummaries: [CachedGallerySummary]
    ) {
        historyCount = records.count
        self.favoriteCount = favoriteCount
        cachedGalleryCount = cacheSummaries.count
        cachedPageCount = cacheSummaries.reduce(0) { $0 + $1.cachedPageCount }
        knownCachedPageTotal = cacheSummaries.reduce(0) { $0 + ($1.totalPageCount ?? $1.cachedPageCount) }
        cacheByteCount = cacheSummaries.reduce(Int64(0)) { $0 + $1.byteCount }
        cachedPageDistribution = Self.cachedPageDistribution(from: cacheSummaries)

        let tags = records.flatMap { $0.tags }
        topCharacters = Self.rankedItems(from: Self.tagNames(in: tags, namespace: "character"), limit: 10)
        topAuthors = Self.rankedItems(from: records.compactMap { Self.normalized($0.uploader) })
        topGroups = Self.rankedItems(from: Self.tagNames(in: tags, namespace: "group"), limit: 10)
        topTags = Self.rankedItems(from: records.flatMap { $0.tags.map(\.displayName).compactMap { Self.normalized($0) } })
        topCategories = Self.rankedItems(from: records.compactMap { record in
            Self.normalized(EHGalleryCategory.displayName(forSiteLabel: record.category))
        })
    }

    var isEmpty: Bool {
        historyCount == 0 &&
            favoriteCount == 0 &&
            cachedGalleryCount == 0 &&
            cachedPageCount == 0
    }

    var overviewItems: [StatisticOverviewItem] {
        [
            StatisticOverviewItem(title: AppCopy.statisticsHistoryGalleries, value: historyCount, color: .blue),
            StatisticOverviewItem(title: AppCopy.statisticsFavoriteGalleries, value: favoriteCount, color: .yellow),
            StatisticOverviewItem(title: AppCopy.statisticsCachedGalleries, value: cachedGalleryCount, color: .green),
            StatisticOverviewItem(title: AppCopy.statisticsCachedPages, value: cachedPageCount, color: .purple)
        ]
        .filter { $0.value > 0 }
    }

    var localizedCacheByteCount: String {
        ByteCountFormatter.string(fromByteCount: cacheByteCount, countStyle: .file)
    }

    var cacheCompletionFraction: Double {
        guard knownCachedPageTotal > 0 else { return 0 }
        return min(1, Double(cachedPageCount) / Double(knownCachedPageTotal))
    }

    /// Builds top metadata rows sorted by frequency.
    private static func rankedItems(from values: [String], limit: Int = 8) -> [StatisticRankedItem] {
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        let maximumCount = counts.values.max() ?? 0
        return counts
            .map { StatisticRankedItem(title: $0.key, count: $0.value, maximumCount: maximumCount) }
            .sorted {
                if $0.count == $1.count {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Builds page-count buckets for cached galleries.
    private static func cachedPageDistribution(from summaries: [CachedGallerySummary]) -> [StatisticRankedItem] {
        let pageCounts = summaries
            .map { $0.totalPageCount ?? $0.cachedPageCount }
            .filter { $0 > 0 }

        guard !pageCounts.isEmpty else { return [] }

        let buckets: [(title: String, contains: (Int) -> Bool)] = [
            ("1-20 页", { $0 <= 20 }),
            ("21-50 页", { 21...50 ~= $0 }),
            ("51-100 页", { 51...100 ~= $0 }),
            ("101-200 页", { 101...200 ~= $0 }),
            ("201+ 页", { $0 >= 201 })
        ]
        let bucketCounts = buckets.map { bucket in
            (title: bucket.title, count: pageCounts.filter(bucket.contains).count)
        }
        let maximumCount = bucketCounts.map(\.count).max() ?? 0

        return bucketCounts
            .filter { $0.count > 0 }
            .map { StatisticRankedItem(title: $0.title, count: $0.count, maximumCount: maximumCount) }
    }

    /// Extracts normalized tag names for a single namespace.
    private static func tagNames(in tags: [EHTag], namespace: String) -> [String] {
        tags
            .filter { $0.namespace.caseInsensitiveCompare(namespace) == .orderedSame }
            .compactMap { Self.normalized($0.name) }
    }

    /// Trims empty values so charts do not show meaningless rows.
    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    SettingsView()
        .environmentObject(LibraryStore())
}
