import SwiftUI

/// Shows local data controls and reader-related preferences.
struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @StateObject private var imageCacheStore = ImageCacheStore.shared
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
            Label(String(format: AppCopy.settingsHistoryCount, String(libraryStore.history.count)), systemImage: "clock")
            Label(String(format: AppCopy.settingsFavoritesCount, String(libraryStore.favorites.count)), systemImage: "star")

            Button(role: .destructive) {
                showsClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearLocalData, systemImage: "trash")
            }
            .disabled(libraryStore.history.isEmpty && libraryStore.favorites.isEmpty)
            .confirmationDialog(
                AppCopy.settingsClearConfirmationTitle,
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsClearConfirm, role: .destructive) {
                    libraryStore.removeAll()
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
            .disabled(imageCacheStore.gallerySummaries.isEmpty)

            Button(role: .destructive) {
                showsImageCacheClearConfirmation = true
            } label: {
                Label(AppCopy.settingsClearImageCache, systemImage: "trash")
            }
            .disabled(imageCacheStore.snapshot.isEmpty)
            .confirmationDialog(
                AppCopy.settingsImageCacheClearTitle,
                isPresented: $showsImageCacheClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppCopy.settingsImageCacheClearConfirm, role: .destructive) {
                    imageCacheStore.clear()
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
        if imageCacheStore.snapshot.isEmpty {
            return AppCopy.settingsImageCacheEmpty
        }
        if imageCacheStore.snapshot.galleryCount > 0 {
            return String(
                format: AppCopy.settingsImageCacheGalleryUsageFormat,
                String(imageCacheStore.snapshot.galleryCount),
                imageCacheStore.snapshot.localizedByteCount
            )
        }
        return String(
            format: AppCopy.settingsImageCacheUsageFormat,
            String(imageCacheStore.snapshot.fileCount),
            imageCacheStore.snapshot.localizedByteCount
        )
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
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @StateObject private var downloadManager = GalleryDownloadManager.shared

    var body: some View {
        Group {
            if imageCacheStore.gallerySummaries.isEmpty {
                ContentUnavailableView(
                    AppCopy.cacheManagementEmptyTitle,
                    systemImage: "externaldrive",
                    description: Text(AppCopy.cacheManagementEmptyMessage)
                )
            } else {
                List {
                    cacheDownloadControls

                    ForEach(imageCacheStore.gallerySummaries) { summary in
                        NavigationLink {
                            GalleryDetailView(result: summary.searchResult)
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
                    downloadManager.startUnfinishedDownloads(from: imageCacheStore.gallerySummaries)
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
        let summaries = imageCacheStore.gallerySummaries
        for offset in offsets where summaries.indices.contains(offset) {
            imageCacheStore.clearGallery(summaries[offset].galleryIdentifier)
        }
    }

    /// Returns cached galleries that still have pages missing from the local cache.
    private var unfinishedSummaries: [CachedGallerySummary] {
        imageCacheStore.gallerySummaries.filter { summary in
            guard let totalPageCount = summary.totalPageCount else { return false }
            return !summary.isDownloadUnavailable && summary.cachedPageCount < totalPageCount
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(LibraryStore())
}
