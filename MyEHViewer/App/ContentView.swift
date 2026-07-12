import SwiftUI
import UIKit

/// Hosts the root tab navigation and global full-screen routes.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var sharedMediaStore = SharedMediaStore()
    @StateObject private var appNavigationStore = AppNavigationStore()
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw = AppThemeMode.system.rawValue
    @AppStorage(AppAccentColor.storageKey) private var accentColorHex = AppAccentColor.defaultHex

    var body: some View {
        TabView(selection: $appNavigationStore.selectedTab) {
            NavigationStack {
                DiscoveryView()
            }
                .tabItem {
                    Label(AppCopy.discoveryTitle, systemImage: "sparkles.rectangle.stack")
                }
                .tag(ContentTab.discovery)

            NavigationStack {
                LibraryView()
            }
                .tabItem {
                    Label(AppCopy.libraryTitle, systemImage: "books.vertical")
                }
                .tag(ContentTab.library)

            NavigationStack {
                FavoriteImagesView()
            }
                .tabItem {
                    Label(AppCopy.libraryImageFavorites, systemImage: "heart")
                }
                .tag(ContentTab.imageFavorites)

            NavigationStack {
                SharedMediaView()
            }
                .tabItem {
                    Label(AppCopy.sharedMediaTitle, systemImage: "square.and.arrow.down")
                }
                .tag(ContentTab.sharedMedia)

            SettingsView()
                .tabItem {
                    Label(AppCopy.settingsTitle, systemImage: "gearshape")
                }
                .tag(ContentTab.settings)
        }
        .environmentObject(libraryStore)
        .environmentObject(sharedMediaStore)
        .environmentObject(appNavigationStore)
        .environmentObject(siteCookieStore)
        .preferredColorScheme(preferredColorScheme)
        .accentColor(accentColor)
        .tint(accentColor)
        .fullScreenCover(isPresented: readerPresentationBinding) {
            readerPresentation
        }
        .fullScreenCover(isPresented: searchPresentationBinding) {
            searchPresentation
        }
        .onAppear {
            applyUIKitAccentColor(accentColor)
        }
        .onChange(of: accentColorHex) { _, _ in
            applyUIKitAccentColor(accentColor)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await sharedMediaStore.importIncomingAndRefresh() }
        }
        .task {
            await Task.yield()
            await ImageCacheStore.shared.refreshIfNeededAsync(minimumInterval: 0)
        }
    }

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var accentColor: Color {
        AppAccentColor.color(from: accentColorHex)
    }

    /// Bridges global search state into a dismissible full-screen route.
    private var searchPresentationBinding: Binding<Bool> {
        Binding {
            appNavigationStore.isSearchPresented
        } set: { isPresented in
            if !isPresented {
                appNavigationStore.closeSearch()
            }
        }
    }

    /// Presents search above the active tab so callers keep their original context.
    private var searchPresentation: some View {
        SearchView(onClose: appNavigationStore.closeSearch)
            .environmentObject(appNavigationStore)
            .environmentObject(libraryStore)
            .environmentObject(sharedMediaStore)
            .preferredColorScheme(preferredColorScheme)
            .accentColor(accentColor)
            .tint(accentColor)
            .fullScreenCover(isPresented: searchReaderPresentationBinding) {
                readerPresentation
            }
    }

    /// Presents readers from the search layer so nested search results remain visible underneath.
    private var searchReaderPresentationBinding: Binding<Bool> {
        Binding {
            appNavigationStore.isSearchReaderPresented
        } set: { isPresented in
            if !isPresented {
                appNavigationStore.closeReader()
            }
        }
    }

    /// Applies the SwiftUI accent to UIKit-backed controls that cache the window tint.
    private func applyUIKitAccentColor(_ color: Color) {
        let uiColor = UIColor(color)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { window in
                window.tintColor = uiColor
            }
    }

    /// Bridges the optional reader route into a dismissible full-screen cover.
    private var readerPresentationBinding: Binding<Bool> {
        Binding {
            appNavigationStore.isRootReaderPresented
        } set: { isPresented in
            if !isPresented {
                appNavigationStore.closeReader()
            }
        }
    }

    /// Presents the active reader session above the tab hierarchy.
    @ViewBuilder
    private var readerPresentation: some View {
        if let route = appNavigationStore.readerRoute {
            NavigationStack {
                ReaderView(
                    initialPageURL: route.initialPageURL,
                    pageLinks: route.pageLinks,
                    totalPageCount: route.totalPageCount,
                    onClose: {
                        appNavigationStore.closeReader()
                    }
                )
                .id(route.id)
            }
            .environmentObject(libraryStore)
            .environmentObject(appNavigationStore)
            .preferredColorScheme(preferredColorScheme)
            .accentColor(accentColor)
            .tint(accentColor)
        }
    }
}

/// Shows a shuffled, incrementally loaded view of durable local content.
struct DiscoveryView: View {
    @EnvironmentObject private var sharedMediaStore: SharedMediaStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @StateObject private var imageCacheStore = ImageCacheStore.shared
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var showsActions = false
    @State private var showsQRCodeScanner = false
    @State private var pendingScannedContent: String?
    @State private var scannedGalleryResult: EHSearchResult?
    @State private var scannerAlert: DiscoveryScannerAlert?
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12),
        count: 2
    )

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            discoveryContent
            floatingActions
        }
        .navigationTitle(AppCopy.discoveryTitle)
        .navigationDestination(item: $scannedGalleryResult) { result in
            GalleryDetailView(result: result)
        }
        .sheet(isPresented: $showsQRCodeScanner, onDismiss: handleDismissedScanner) {
            QRCodeScannerSheet { content in
                pendingScannedContent = content
                showsQRCodeScanner = false
            }
        }
        .alert(item: $scannerAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(AppCopy.commonOK))
            )
        }
        .task {
            viewModel.update(items: sourceItems, resetOrder: true)
        }
        .onChange(of: imageCacheStore.gallerySummaries) { _, _ in
            viewModel.update(items: sourceItems)
        }
        .onChange(of: sharedMediaStore.galleries) { _, _ in
            viewModel.update(items: sourceItems)
        }
    }

    @ViewBuilder
    private var discoveryContent: some View {
        if viewModel.visibleItems.isEmpty {
            ScrollView {
                ContentUnavailableView(
                    AppCopy.discoveryEmptyTitle,
                    systemImage: "sparkles.rectangle.stack",
                    description: Text(AppCopy.discoveryEmptyMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 420)
                .padding(.horizontal)
            }
            .refreshable { await refreshDiscovery() }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(viewModel.visibleItems) { item in
                        discoveryLink(for: item)
                    }

                    if viewModel.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(columns.count)
                            .padding(.vertical, 18)
                            .onAppear { viewModel.loadMore() }
                    } else {
                        Text(AppCopy.discoveryExhausted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(columns.count)
                            .padding(.vertical, 18)
                    }
                }
                .padding(12)
                .padding(.bottom, 76)
            }
            .refreshable { await refreshDiscovery() }
        }
    }

    @ViewBuilder
    private func discoveryLink(for item: LocalDiscoveryItem) -> some View {
        switch item {
        case .cachedGallery(let summary):
            NavigationLink {
                CachedGalleryEntryView(summary: summary)
            } label: {
                DiscoveryCachedGalleryCard(summary: summary)
            }
            .buttonStyle(.plain)
        case .sharedGallery(let gallery):
            DiscoverySharedGalleryLink(gallery: gallery)
        }
    }

    private var floatingActions: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showsActions {
                Button {
                    showsQRCodeScanner = true
                } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel(AppCopy.searchScanQRCode)

                Button {
                    appNavigationStore.presentSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel(AppCopy.discoveryOpenSearch)

                NavigationLink {
                    ImageCacheManagementView()
                } label: {
                    Image(systemName: "externaldrive")
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .accessibilityLabel(AppCopy.discoveryOpenCache)
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    showsActions.toggle()
                }
            } label: {
                Image(systemName: showsActions ? "xmark" : "ellipsis")
                    .font(.headline)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 5, y: 2)
            }
            .accessibilityLabel(showsActions ? AppCopy.discoveryCloseActions : AppCopy.discoveryActions)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    private var sourceItems: [LocalDiscoveryItem] {
        imageCacheStore.gallerySummaries
            .filter { $0.storageState == .persistent }
            .map(LocalDiscoveryItem.cachedGallery)
            + sharedMediaStore.galleries.map(LocalDiscoveryItem.sharedGallery)
    }

    /// Rebuilds the shuffled snapshot after synchronizing Files-visible state.
    private func refreshDiscovery() async {
        await imageCacheStore.refreshIfNeededAsync(minimumInterval: 0)
        await sharedMediaStore.importIncomingAndRefresh()
        viewModel.update(items: sourceItems, resetOrder: true)
    }

    /// Processes a scanned value after the camera sheet finishes dismissing.
    private func handleDismissedScanner() {
        guard let content = pendingScannedContent else { return }
        pendingScannedContent = nil
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmedContent),
            let identifier = EHGalleryIdentifier(supportedGalleryURL: url)
        else {
            scannerAlert = DiscoveryScannerAlert(
                title: AppCopy.searchScannedContentTitle,
                message: trimmedContent.isEmpty ? AppCopy.searchScannedContentEmpty : trimmedContent
            )
            return
        }

        scannedGalleryResult = EHSearchResult(
            identifier: identifier,
            title: String(format: AppCopy.searchScannedGalleryTitleFormat, String(identifier.gid)),
            category: identifier.site.title,
            pageURL: identifier.url(),
            thumbnailURL: nil,
            uploader: nil,
            postedText: nil,
            pageCountText: nil,
            tags: []
        )
    }
}

/// Maintains one shuffled local-content snapshot and exposes it in fixed pages.
@MainActor
final class DiscoveryViewModel: ObservableObject {
    static let pageSize = 20
    @Published private(set) var visibleItems: [LocalDiscoveryItem] = []
    @Published private(set) var hasMore = false
    private var itemsByID: [String: LocalDiscoveryItem] = [:]
    private var orderedIDs: [String] = []
    private var visibleCount = 0
    private let randomize: ([String]) -> [String]

    /// Creates a discovery model with an injectable order for deterministic tests.
    init(randomize: @escaping ([String]) -> [String] = { $0.shuffled() }) {
        self.randomize = randomize
    }

    /// Synchronizes local resources, optionally beginning a completely new round.
    func update(items: [LocalDiscoveryItem], resetOrder: Bool = false) {
        let updatedItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let updatedIDs = Set(updatedItemsByID.keys)
        if resetOrder || orderedIDs.isEmpty {
            orderedIDs = randomize(Array(updatedIDs))
            visibleCount = min(Self.pageSize, orderedIDs.count)
        } else {
            orderedIDs = orderedIDs.filter { updatedIDs.contains($0) }
            let knownIDs = Set(orderedIDs)
            orderedIDs.append(contentsOf: randomize(Array(updatedIDs.subtracting(knownIDs))))
            visibleCount = min(max(visibleCount, min(Self.pageSize, orderedIDs.count)), orderedIDs.count)
        }
        itemsByID = updatedItemsByID
        publishVisibleItems()
    }

    /// Reveals the next fixed-size page when the bottom sentinel becomes visible.
    func loadMore() {
        guard visibleCount < orderedIDs.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, orderedIDs.count)
        publishVisibleItems()
    }

    /// Publishes current models after resolving the stable shuffled identifiers.
    private func publishVisibleItems() {
        visibleItems = orderedIDs.prefix(visibleCount).compactMap { itemsByID[$0] }
        hasMore = visibleCount < orderedIDs.count
    }
}

/// Represents one top-level durable resource shown on the discovery page.
enum LocalDiscoveryItem: Identifiable, Hashable {
    case cachedGallery(CachedGallerySummary)
    case sharedGallery(SharedMediaGalleryRecord)

    var id: String {
        switch self {
        case .cachedGallery(let summary): "cached-\(summary.id)"
        case .sharedGallery(let gallery): "shared-\(gallery.id.uuidString)"
        }
    }
}

/// Shows one permanently stored remote gallery in a stable discovery cell.
private struct DiscoveryCachedGalleryCard: View {
    let summary: CachedGallerySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                CachedRemoteImageView(
                    url: summary.thumbnailURL ?? summary.pageRecords.first?.thumbnailURL ?? summary.pageRecords.first?.imageURL,
                    contentMode: .fill,
                    animationMode: .staticPreview,
                    decodeMaxPixelSize: 420
                ) {
                    ProgressView()
                } failure: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(.secondary)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Label(summary.note ?? summary.title, systemImage: "externaldrive.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(summary.progressText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Routes one shared batch according to whether it contains one media item or a gallery.
private struct DiscoverySharedGalleryLink: View {
    @EnvironmentObject private var store: SharedMediaStore
    let gallery: SharedMediaGalleryRecord

    var body: some View {
        destinationLink {
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { proxy in
                    galleryCover
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .aspectRatio(1, contentMode: .fit)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Label(gallery.displayName, systemImage: itemSystemImage)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Text("\(records.count) \(AppCopy.sharedMediaGalleryItems)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var galleryCover: some View {
        if let coverRecord {
            SharedMediaThumbnail(record: coverRecord)
        } else {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func destinationLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        if records.count == 1, let record = records.first {
            if record.kind == .image {
                NavigationLink {
                    SharedImageReaderView(records: [record], initialRecordID: record.id)
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
        } else {
            NavigationLink {
                SharedMediaGalleryView(galleryID: gallery.id)
            } label: {
                label()
            }
        }
    }

    private var records: [SharedMediaRecord] { store.records(in: gallery) }
    private var coverRecord: SharedMediaRecord? { records.first { $0.id == gallery.coverMediaID } }
    private var itemSystemImage: String {
        guard records.count == 1, let record = records.first else { return "photo.on.rectangle.angled" }
        return record.kind == .image ? "photo" : "video"
    }
}

/// Stores one alert generated by discovery QR scanning.
private struct DiscoveryScannerAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Identifies top-level app tabs.
enum ContentTab: Hashable {
    case discovery
    case library
    case imageFavorites
    case sharedMedia
    case settings
}

/// Describes the currently active reader session.
struct ReaderRoute: Identifiable, Equatable {
    let id = UUID()
    let initialPageURL: URL
    let pageLinks: [EHGalleryPageLink]
    let totalPageCount: Int?
}

/// Describes a search that should be opened from another screen.
struct AppSearchRequest: Identifiable, Equatable {
    let id = UUID()
    let query: String
    let site: ContentSite
}

/// Coordinates top-level tab selection and reader sessions.
@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var selectedTab = ContentTab.discovery
    @Published private(set) var readerRoute: ReaderRoute?
    @Published private(set) var searchRequest: AppSearchRequest?
    @Published private(set) var searchNavigationID = UUID()
    @Published private(set) var isSearchPresented = false

    /// Returns whether the tab hierarchy should present the active reader.
    var isRootReaderPresented: Bool {
        readerRoute != nil && !isSearchPresented
    }

    /// Returns whether the global search layer should present the active reader.
    var isSearchReaderPresented: Bool {
        readerRoute != nil && isSearchPresented
    }

    /// Opens a full-screen reader with the requested image page.
    func openReader(initialPageURL: URL, pageLinks: [EHGalleryPageLink] = [], totalPageCount: Int? = nil) {
        readerRoute = ReaderRoute(initialPageURL: initialPageURL, pageLinks: pageLinks, totalPageCount: totalPageCount)
    }

    /// Closes the active reader session and returns to the previous tab.
    func closeReader() {
        readerRoute = nil
    }

    /// Presents an empty search page above the current tab.
    func presentSearch() {
        searchRequest = nil
        searchNavigationID = UUID()
        isSearchPresented = true
    }

    /// Presents or resets the global search page without changing the current tab.
    func openSearch(query: String, site: ContentSite) {
        searchRequest = AppSearchRequest(query: query, site: site)
        searchNavigationID = UUID()
        isSearchPresented = true
    }

    /// Dismisses search and returns to the tab that opened it.
    func closeSearch() {
        searchRequest = nil
        isSearchPresented = false
    }

    /// Clears a search request after the main search screen handles it.
    func consumeSearchRequest(id: UUID) {
        guard searchRequest?.id == id else { return }
        searchRequest = nil
    }
}

/// Stores and converts the user-selected app accent color.
enum AppAccentColor {
    static let storageKey = "App.accentColorHex"
    static let defaultHex = "#00A8FF"

    /// Converts a persisted hex string into a SwiftUI color.
    static func color(from hex: String) -> Color {
        guard let components = rgbComponents(from: hex) else {
            return Color(red: 0.0, green: 168.0 / 255.0, blue: 1.0)
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// Converts a SwiftUI color into a stable uppercase hex string.
    static func hex(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return defaultHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// Parses a six-digit RGB hex string.
    private static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        let trimmedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHex = trimmedHex.hasPrefix("#") ? String(trimmedHex.dropFirst()) : trimmedHex
        guard normalizedHex.count == 6, let value = Int(normalizedHex, radix: 16) else {
            return nil
        }
        return (
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

#Preview {
    ContentView()
}
