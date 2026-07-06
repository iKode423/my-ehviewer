import ImageIO
import SwiftUI
import UIKit

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderZoomLevel.storageKey) private var zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    @StateObject private var viewModel: ReaderViewModel
    @State private var showsPageGridSheet = false
    @State private var showsPageJumpSheet = false
    @State private var pageJumpText = ""

    /// Creates a reader view that can start from a parsed image page URL.
    init(initialPageURL: URL? = nil, pageLinks: [EHGalleryPageLink] = []) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(initialPageURL: initialPageURL, pageLinks: pageLinks))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(readerBackgroundColor.ignoresSafeArea())
        .navigationTitle(AppCopy.readerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !viewModel.sortedPageLinks.isEmpty {
                    Button {
                        showsPageGridSheet = true
                    } label: {
                        Label(AppCopy.readerPageGrid, systemImage: "square.grid.3x3")
                    }
                    .disabled(viewModel.isLoading)
                }

                displayMenu

                if let imagePage = viewModel.imagePage {
                    readerLinksMenu(for: imagePage)
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.imagePage) { _, imagePage in
            if let imagePage {
                libraryStore.updateProgress(imagePage: imagePage)
            }
        }
        .refreshable {
            await viewModel.reload()
        }
        .sheet(isPresented: $showsPageJumpSheet) {
            pageJumpSheet
        }
        .sheet(isPresented: $showsPageGridSheet) {
            pageGridSheet
        }
    }

    private var fitMode: ReaderFitMode {
        ReaderFitMode(rawValue: fitModeRaw) ?? .fitPage
    }

    private var zoomLevel: ReaderZoomLevel {
        ReaderZoomLevel.resolved(rawValue: zoomLevelRaw)
    }

    private var backgroundMode: ReaderBackgroundMode {
        ReaderBackgroundMode(rawValue: backgroundModeRaw) ?? .system
    }

    private var pageJumpNumber: Int? {
        Int(pageJumpText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSubmitPageJump: Bool {
        guard let pageJumpNumber else { return false }
        return viewModel.canLoadPageNumber(pageJumpNumber)
    }

    private var readerBackgroundColor: Color {
        switch backgroundMode {
        case .system: Color(.systemBackground)
        case .dark: Color.black
        case .paper: Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }

    private var readerForegroundStyle: Color {
        switch backgroundMode {
        case .dark: .white
        case .system, .paper: .primary
        }
    }

    /// Displays the empty, loading, error, or image-reading state.
    @ViewBuilder
    private var content: some View {
        if viewModel.initialPageURL == nil {
            ContentUnavailableView(
                AppCopy.readerEmptyTitle,
                systemImage: "book.pages",
                description: Text(AppCopy.readerEmptyMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoading && viewModel.imagePage == nil {
            ContentUnavailableView(AppCopy.readerLoadingTitle, systemImage: "hourglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.imagePage == nil {
            VStack(spacing: 16) {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")
                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label(AppCopy.readerRetry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let imagePage = viewModel.imagePage {
            readerContent(for: imagePage)
        }
    }

    /// Shows the current image and page navigation controls.
    private func readerContent(for imagePage: EHImagePage) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(pageStatusText(for: imagePage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerForegroundStyle)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                }

                Label(String(format: AppCopy.readerZoomFormat, zoomLevel.title), systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(readerForegroundStyle.opacity(0.72))
            }
            .padding()

            Divider()

            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    HStack {
                        Spacer(minLength: 0)

                        CachedRemoteImageView(
                            url: imagePage.imageURL,
                            contentMode: .fit,
                            reloadToken: viewModel.imageReloadToken
                        ) {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 320)
                        } failure: {
                            imageLoadFailureView
                        }
                        .id(viewModel.imageReloadToken)
                        .frame(width: readerImageWidth(availableWidth: geometry.size.width))
                        .onTapGesture(count: 2) {
                            toggleReaderZoom()
                        }
                        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: zoomLevelRaw)

                        Spacer(minLength: 0)
                    }
                    .padding(fitMode == .fitPage ? 16 : 0)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .top)
                }
            }
            .background(readerBackgroundColor)

            Divider()

            navigationControls
                .padding()
        }
    }

    /// Shows an inline retry action when the image resource fails to load.
    private var imageLoadFailureView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(readerForegroundStyle.opacity(0.72))
                .accessibilityHidden(true)

            Text(AppCopy.readerImageLoadFailed)
                .font(.headline)
                .foregroundStyle(readerForegroundStyle)

            Button {
                viewModel.reloadImage()
            } label: {
                Label(AppCopy.readerImageRetry, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    /// Shows a stable thumbnail frame for a known reader page.
    private func pageThumbnail(url: URL?) -> some View {
        CachedRemoteImageView(url: url, contentMode: .fill) {
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
    }

    /// Builds the visible page progress text from loaded reader state.
    private func pageStatusText(for imagePage: EHImagePage) -> String {
        if let knownLastPageNumber = viewModel.knownLastPageNumber {
            return String(
                format: AppCopy.readerPageKnownFormat,
                String(imagePage.pageNumber),
                String(knownLastPageNumber)
            )
        }
        return String(format: AppCopy.readerPageFormat, String(imagePage.pageNumber))
    }

    /// Calculates the rendered image width for the current fit and zoom preferences.
    private func readerImageWidth(availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = fitMode == .fitPage ? 32 : 0
        let baseWidth = max(availableWidth - horizontalPadding, 44)
        return baseWidth * CGFloat(zoomLevel.rawValue)
    }

    /// Toggles between the default zoom and a readable close-up zoom.
    private func toggleReaderZoom() {
        zoomLevelRaw = zoomLevel.doubleTapTarget.rawValue
    }

    /// Restores the reader zoom to the default size.
    private func resetReaderZoom() {
        zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    }

    /// Provides previous and next page actions.
    private var navigationControls: some View {
        HStack {
            Button {
                Task { await viewModel.loadPreviousPage() }
            } label: {
                Label(AppCopy.readerPreviousPage, systemImage: "chevron.left")
            }
            .disabled(!viewModel.canLoadPreviousPage || viewModel.isLoading)

            Spacer()

            Button {
                presentPageJump()
            } label: {
                Label(AppCopy.readerJumpPage, systemImage: "number.square")
            }
            .disabled(viewModel.sortedPageLinks.isEmpty || viewModel.isLoading)

            Spacer()

            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                Label(AppCopy.readerNextPage, systemImage: "chevron.right")
            }
            .disabled(!viewModel.canLoadNextPage || viewModel.isLoading)
        }
        .buttonStyle(.bordered)
    }

    /// Shows a page-number jump form for known gallery page links.
    private var pageJumpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.readerJumpPageField, text: $pageJumpText)
                        .keyboardType(.numberPad)

                    if let knownLastPageNumber = viewModel.knownLastPageNumber {
                        Text(String(format: AppCopy.readerJumpPageRangeFormat, String(knownLastPageNumber)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(AppCopy.readerJumpPageTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.readerJumpPageCancel) {
                        showsPageJumpSheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.readerJumpPageConfirm) {
                        submitPageJump()
                    }
                    .disabled(!canSubmitPageJump || viewModel.isLoading)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Shows known reader pages as selectable thumbnails.
    private var pageGridSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(viewModel.sortedPageLinks) { pageLink in
                        Button {
                            loadPageFromGrid(pageLink)
                        } label: {
                            VStack(spacing: 6) {
                                pageThumbnail(url: pageLink.thumbnailURL)

                                Text(String(format: AppCopy.galleryOpenPage, String(pageLink.pageNumber)))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(pageGridTileBackground(for: pageLink))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoading)
                    }
                }
                .padding()
            }
            .navigationTitle(AppCopy.readerPageGridTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.readerJumpPageCancel) {
                        showsPageGridSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Highlights the currently loaded reader page in the thumbnail grid.
    private func pageGridTileBackground(for pageLink: EHGalleryPageLink) -> Color {
        if pageLink.pageNumber == viewModel.imagePage?.pageNumber {
            return Color.accentColor.opacity(0.16)
        }
        return Color.secondary.opacity(0.08)
    }

    /// Opens page jump controls with the current reader page prefilled.
    private func presentPageJump() {
        pageJumpText = String(viewModel.imagePage?.pageNumber ?? viewModel.sortedPageLinks.first?.pageNumber ?? 1)
        showsPageJumpSheet = true
    }

    /// Loads the requested known page and dismisses the jump sheet.
    private func submitPageJump() {
        guard let pageJumpNumber else { return }
        showsPageJumpSheet = false
        Task {
            await viewModel.loadPageNumber(pageJumpNumber)
        }
    }

    /// Loads a selected thumbnail page and dismisses the grid sheet.
    private func loadPageFromGrid(_ pageLink: EHGalleryPageLink) {
        showsPageGridSheet = false
        Task {
            await viewModel.loadPage(pageLink)
        }
    }

    /// Exposes reader display preferences from the reader toolbar.
    private var displayMenu: some View {
        Menu {
            Picker(AppCopy.readerDisplayMode, selection: $fitModeRaw) {
                ForEach(ReaderFitMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Picker(AppCopy.readerZoomMode, selection: $zoomLevelRaw) {
                ForEach(ReaderZoomLevel.allCases) { level in
                    Text(level.title).tag(level.rawValue)
                }
            }

            Button {
                resetReaderZoom()
            } label: {
                Label(AppCopy.readerZoomReset, systemImage: "arrow.counterclockwise")
            }
            .disabled(zoomLevel == .x1)

            Picker(AppCopy.readerBackgroundMode, selection: $backgroundModeRaw) {
                ForEach(ReaderBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        } label: {
            Label(AppCopy.readerDisplayMenu, systemImage: "textformat.size")
        }
    }

    /// Exposes useful source links for the loaded reader page.
    private func readerLinksMenu(for imagePage: EHImagePage) -> some View {
        Menu {
            Link(destination: imagePage.pageURL) {
                Label(AppCopy.readerCurrentPage, systemImage: "doc")
            }

            if let galleryURL = imagePage.galleryURL {
                Link(destination: galleryURL) {
                    Label(AppCopy.readerGalleryPage, systemImage: "rectangle.stack")
                }
            }

            if let originalImageURL = imagePage.originalImageURL {
                Link(destination: originalImageURL) {
                    Label(AppCopy.readerOriginalImage, systemImage: "photo")
                }
            }
        } label: {
            Label(AppCopy.readerLinksMenu, systemImage: "link")
        }
    }
}

/// Selects how cached image data should be fitted into its view frame.
enum CachedRemoteImageContentMode {
    case fit
    case fill

    var uiViewContentMode: UIView.ContentMode {
        switch self {
        case .fit: .scaleAspectFit
        case .fill: .scaleAspectFill
        }
    }
}

/// Shows a remote image from disk cache or network while preserving GIF animation.
struct CachedRemoteImageView<Placeholder: View, Failure: View>: View {
    let url: URL?
    let contentMode: CachedRemoteImageContentMode
    let reloadToken: Int
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @StateObject private var loader = CachedRemoteImageLoader()

    /// Creates a cached remote image view with custom loading and failure states.
    init(
        url: URL?,
        contentMode: CachedRemoteImageContentMode = .fit,
        reloadToken: Int = 0,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.contentMode = contentMode
        self.reloadToken = reloadToken
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                placeholder()
            case .success(let data):
                AnimatedImageDataView(data: data, contentMode: contentMode.uiViewContentMode)
            case .failure:
                failure()
            }
        }
        .task(id: loadKey) {
            await loader.load(url: url)
        }
    }

    private var loadKey: String {
        "\(url?.absoluteString ?? "nil")-\(reloadToken)"
    }
}

/// Tracks one cached remote image loading operation.
@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var state: CachedRemoteImageState = .idle

    private let cacheStore: ImageCacheStore
    private let client: URLSessionEHHTTPClient
    private var lastLoadedKey: String?

    /// Creates an image loader with injectable cache and network dependencies.
    init(
        cacheStore: ImageCacheStore = .shared,
        client: URLSessionEHHTTPClient = URLSessionEHHTTPClient()
    ) {
        self.cacheStore = cacheStore
        self.client = client
    }

    /// Loads image data from cache first, then stores a network response on success.
    func load(url: URL?) async {
        guard let url else {
            state = .failure
            lastLoadedKey = nil
            return
        }

        if let cachedData = cacheStore.data(for: url) {
            state = .success(cachedData)
            lastLoadedKey = url.absoluteString
            return
        }

        guard lastLoadedKey != url.absoluteString || state != .loading else { return }
        lastLoadedKey = url.absoluteString
        state = .loading

        do {
            let response = try await client.data(url)
            cacheStore.save(response.data, for: url)
            if response.url != url {
                cacheStore.save(response.data, for: response.url)
            }
            state = .success(response.data)
        } catch {
            state = .failure
        }
    }
}

/// Describes the loading state for cached remote image data.
enum CachedRemoteImageState: Equatable {
    case idle
    case loading
    case success(Data)
    case failure
}

/// Bridges image data into UIImageView so animated GIF frames can play.
struct AnimatedImageDataView: UIViewRepresentable {
    let data: Data
    let contentMode: UIView.ContentMode

    /// Creates a coordinator that avoids reparsing unchanged image data.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Creates the underlying UIKit image view.
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    /// Updates the image view and starts GIF animation when multiple frames exist.
    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.contentMode = contentMode
        if context.coordinator.data != data {
            context.coordinator.data = data
            context.coordinator.image = ImageDataRenderer.uiImage(from: data)
        }
        imageView.image = context.coordinator.image
        if context.coordinator.image?.images?.isEmpty == false {
            imageView.startAnimating()
        }
    }

    /// Stores parsed image data between SwiftUI updates.
    final class Coordinator {
        var data: Data?
        var image: UIImage?
    }
}

/// Converts static and animated image data into UIImage values.
enum ImageDataRenderer {
    /// Parses GIF frames with ImageIO and falls back to UIImage for static data.
    static func uiImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(at: index, source: source)
        }

        guard !frames.isEmpty else {
            return UIImage(data: data)
        }

        let resolvedDuration = duration > 0 ? duration : Double(frames.count) * 0.1
        return UIImage.animatedImage(with: frames, duration: resolvedDuration) ?? UIImage(data: data)
    }

    /// Reads one GIF frame delay and clamps unreadably fast frames.
    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let delay = unclampedDelay ?? gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

#Preview {
    NavigationStack {
        ReaderView()
    }
    .environmentObject(LibraryStore())
}
