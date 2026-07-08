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
                    cacheDownloadControls

                    ForEach(currentSiteGallerySummaries) { summary in
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
        .navigationTitle(AppCopy.cacheManagementTitle)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            imageCacheStore.refresh()
        }
    }

    /// Shows the bulk download action and current aggregate download status.
    private var cacheDownloadControls: some View {
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
            .disabled(downloadManager.aggregateProgress == nil && unfinishedSummaries.isEmpty)

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
            Text(summary.title)
                .font(.headline)
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
        let summaries = currentSiteGallerySummaries
        for offset in offsets where summaries.indices.contains(offset) {
            imageCacheStore.clearGallery(summaries[offset].galleryIdentifier)
        }
    }

    /// Returns cached galleries that still have pages missing from the local cache.
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

/// Opens cached galleries without requiring the remote detail page to load first.
private struct CachedGalleryEntryView: View {
    let summary: CachedGallerySummary
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore

    var body: some View {
        List {
            Section {
                Button {
                    openCachedReader()
                } label: {
                    Label(cachedReaderButtonTitle, systemImage: "book")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cachedPageLinks.isEmpty)

                NavigationLink {
                    GalleryDetailView(result: summary.searchResult)
                } label: {
                    Label(AppCopy.galleryTitle, systemImage: "info.circle")
                }
            } footer: {
                Text(summary.progressText)
            }
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    /// Chooses whether the cached reader starts from history or the first cached page.
    private var cachedReaderButtonTitle: String {
        cachedResumeURL == nil ? AppCopy.galleryReadFromStart : AppCopy.galleryContinueReading
    }

    /// Returns the cached page links sorted by page number.
    private var cachedPageLinks: [EHGalleryPageLink] {
        summary.pageRecords.map { record in
            EHGalleryPageLink(
                pageNumber: record.pageNumber,
                pageURL: record.pageURL,
                thumbnailURL: record.thumbnailURL
            )
        }
    }

    /// Returns the last read page URL only when it is still cached.
    private var cachedResumeURL: URL? {
        let cachedPageURLs = Set(cachedPageLinks.map(\.pageURL))
        return libraryStore.record(for: summary.galleryIdentifier)?.lastReadPageURL.flatMap { cachedPageURLs.contains($0) ? $0 : nil }
    }

    /// Opens the reader with only locally cached page links.
    private func openCachedReader() {
        guard let startURL = cachedResumeURL ?? cachedPageLinks.first?.pageURL else { return }
        appNavigationStore.openReader(
            initialPageURL: startURL,
            pageLinks: cachedPageLinks,
            totalPageCount: summary.totalPageCount
        )
    }
}

#Preview {
    SettingsView()
        .environmentObject(LibraryStore())
}
