import Foundation
import ImageIO
import Photos
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
    @State private var showsReaderChrome: Bool
    @State private var pageJumpText = ""
    @State private var persistedPinchScale: CGFloat = 1.0
    @State private var currentImageSize: CGSize?
    @State private var pendingImageSavePage: EHImagePage?
    @State private var showsImageSaveConfirmation = false
    @State private var imageSaveAlert: ReaderImageSaveAlert?
    @State private var isSavingImage = false
    private let onClose: (() -> Void)?

    /// Creates a reader view that can start from a parsed image page URL.
    init(initialPageURL: URL? = nil, pageLinks: [EHGalleryPageLink] = [], totalPageCount: Int? = nil, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        _showsReaderChrome = State(initialValue: onClose != nil)
        _viewModel = StateObject(wrappedValue: ReaderViewModel(initialPageURL: initialPageURL, pageLinks: pageLinks, totalPageCount: totalPageCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .overlay {
            if let imagePage = viewModel.imagePage, showsReaderChrome {
                readerChromeOverlay(for: imagePage)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: showsReaderChrome)
        .background(readerBackgroundColor.ignoresSafeArea())
        .navigationTitle(AppCopy.readerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(readerChromeVisibility, for: .navigationBar)
        .statusBarHidden(viewModel.imagePage != nil && !showsReaderChrome)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                readerBackButton
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                imageFavoriteButton
                displayMenu
            }
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .onChange(of: viewModel.imagePage) { _, imagePage in
            if let imagePage {
                libraryStore.updateProgress(imagePage: imagePage)
                resetTransientReaderState()
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
        .confirmationDialog(AppCopy.readerSaveImageTitle, isPresented: $showsImageSaveConfirmation, titleVisibility: .visible) {
            Button(AppCopy.readerSaveImageConfirm) {
                savePendingImageToPhotoLibrary()
            }
            .disabled(isSavingImage)

            Button(AppCopy.readerSaveImageCancel, role: .cancel) {
                pendingImageSavePage = nil
            }
        }
        .alert(item: $imageSaveAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: alert.message.map(Text.init),
                dismissButton: .default(Text(AppCopy.commonOK))
            )
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
        return !viewModel.isLoadingPageLinks && viewModel.canLoadPageNumber(pageJumpNumber)
    }

    private var readerChromeVisibility: Visibility {
        viewModel.imagePage == nil || showsReaderChrome ? .visible : .hidden
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

    /// Shows the explicit escape route when the reader is presented above another screen.
    @ViewBuilder
    private var readerBackButton: some View {
        if let onClose {
            Button {
                onClose()
            } label: {
                Label(AppCopy.readerBack, systemImage: "chevron.left")
            }
        }
    }

    /// Shows a compact always-available back target while the reader chrome is hidden.
    @ViewBuilder
    private var readerFloatingBackButton: some View {
        if let onClose {
            VStack {
                HStack {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppCopy.readerBack)
                    .foregroundStyle(readerForegroundStyle)
                    .background(.regularMaterial, in: Circle())

                    Spacer()
                }

                Spacer()
            }
            .padding(12)
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
        GeometryReader { geometry in
            readerImageStage(for: imagePage, geometry: geometry)
        }
        .ignoresSafeArea()
    }

    /// Shows the full-screen image surface with tap zones and pinch zoom.
    private func readerImageStage(for imagePage: EHImagePage, geometry: GeometryProxy) -> some View {
        let baseImageSize = ReaderViewportLayout.imageSize(
            imageSize: currentImageSize,
            mode: effectiveFitMode(viewportSize: geometry.size),
            viewportSize: geometry.size
        )

        return CenteredReaderZoomScrollView(
            contentSize: baseImageSize,
            zoomScale: readerZoomScaleBinding,
            minimumZoomScale: min(CGFloat(zoomLevel.rawValue), 4),
            maximumZoomScale: 4,
            showsIndicators: showsReaderChrome
        ) {
            CachedRemoteImageView(
                    url: imagePage.imageURL,
                    referer: imagePage.pageURL,
                    cacheContext: imageCacheContext(for: imagePage),
                    contentMode: .fit,
                    reloadToken: viewModel.imageReloadToken,
                    onImageSizeChange: updateCurrentImageSize
                ) {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 320)
                } failure: {
                    imageLoadFailureView
                }
            .id(
                viewModel.isCurrentImagePersistentlyStored
                    ? "persistent-reader-image"
                    : "reader-image-\(viewModel.imageReloadToken)"
            )
            .frame(width: baseImageSize.width, height: baseImageSize.height)
            .contentShape(Rectangle())
            .highPriorityGesture(readerImageSaveLongPress(for: imagePage))
        }
        .id(imagePage.imageURL)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .background(readerBackgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(readerTapGesture(in: geometry.size))
    }

    /// Shows the reader controls when the middle tap zone reveals chrome.
    private func readerChromeOverlay(for imagePage: EHImagePage) -> some View {
        VStack(spacing: 0) {
            readerStatusBar(for: imagePage)
                .background(.regularMaterial)

            Spacer()

            navigationControls
                .padding()
                .background(.regularMaterial)
        }
        .foregroundStyle(readerForegroundStyle)
    }

    /// Shows page status and loading feedback above the image.
    private func readerStatusBar(for imagePage: EHImagePage) -> some View {
        HStack {
            Text(pageStatusText(for: imagePage))
                .font(.subheadline.weight(.semibold))

            Spacer()

            if viewModel.isLoading {
                ProgressView()
            }

            Label(String(format: AppCopy.readerZoomFormat, visibleZoomTitle), systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(readerForegroundStyle.opacity(0.72))
        }
        .padding()
    }

    /// Toggles the current image in the local image favorites collection.
    @ViewBuilder
    private var imageFavoriteButton: some View {
        if let imagePage = viewModel.imagePage {
            let isFavorite = libraryStore.isImageFavorite(imagePage)
            Button {
                libraryStore.toggleImageFavorite(imagePage: imagePage)
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
            }
            .accessibilityLabel(isFavorite ? AppCopy.readerUnfavoriteImage : AppCopy.readerFavoriteImage)
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

    /// Builds cache metadata for the current reader image.
    private func imageCacheContext(for imagePage: EHImagePage) -> ImageCacheContext? {
        ImageCacheContext(
            galleryIdentifier: imagePage.galleryURL.flatMap(EHGalleryIdentifier.init(galleryURL:)),
            galleryTitle: imagePage.title,
            pageNumber: imagePage.pageNumber,
            pageURL: imagePage.pageURL,
            totalPageCount: viewModel.visibleLastPageNumber,
            thumbnailURL: nil
        )
    }

    /// Shows a stable thumbnail frame for a known reader page.
    private func pageThumbnail(url: URL?, crop: EHImageCrop? = nil) -> some View {
        GeometryReader { proxy in
            CachedRemoteImageView(url: url, crop: crop, contentMode: .fill, animationMode: .staticPreview, decodeMaxPixelSize: 420) {
                ProgressView()
            } failure: {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(ReaderPageGridLayout.thumbnailAspectRatio, contentMode: .fit)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipped()
    }

    /// Builds the visible page progress text from loaded reader state.
    private func pageStatusText(for imagePage: EHImagePage) -> String {
        if let knownLastPageNumber = viewModel.visibleLastPageNumber {
            return String(
                format: AppCopy.readerPageKnownFormat,
                String(imagePage.pageNumber),
                String(knownLastPageNumber)
            )
        }
        return String(format: AppCopy.readerPageFormat, String(imagePage.pageNumber))
    }

    /// Resolves the temporary landscape override without changing the saved preference.
    private func effectiveFitMode(viewportSize: CGSize) -> ReaderFitMode {
        ReaderViewportLayout.effectiveFitMode(savedMode: fitMode, viewportSize: viewportSize)
    }

    private var visibleZoomScale: CGFloat {
        min(CGFloat(zoomLevel.rawValue) * persistedPinchScale, 4.0)
    }

    private var visibleZoomTitle: String {
        "\(Int((visibleZoomScale * 100).rounded()))%"
    }

    /// Synchronizes native scroll zoom back into the persisted pinch multiplier.
    private var readerZoomScaleBinding: Binding<CGFloat> {
        Binding {
            visibleZoomScale
        } set: { scale in
            let baseScale = max(CGFloat(zoomLevel.rawValue), 1)
            persistedPinchScale = min(max(scale / baseScale, 1), 4 / baseScale)
        }
    }

    /// Stores decoded image dimensions so height-fit can calculate proportional width.
    private func updateCurrentImageSize(_ imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0, currentImageSize != imageSize else { return }
        currentImageSize = imageSize
    }

    /// Toggles between the default zoom and a readable close-up zoom.
    private func toggleReaderZoom() {
        zoomLevelRaw = zoomLevel.doubleTapTarget.rawValue
        persistedPinchScale = 1.0
    }

    /// Restores the reader zoom to the default size.
    private func resetReaderZoom() {
        zoomLevelRaw = ReaderZoomLevel.x1.rawValue
        persistedPinchScale = 1.0
    }

    /// Resets temporary reader UI whenever a new image page becomes active.
    private func resetTransientReaderState() {
        showsReaderChrome = false
        persistedPinchScale = 1.0
        currentImageSize = nil
    }

    /// Handles left, center, and right reading tap zones.
    private func handleReaderTap(location: CGPoint, size: CGSize) {
        if location.x < size.width * 0.3 {
            Task { await viewModel.loadPreviousPage() }
        } else if location.x > size.width * 0.7 {
            Task { await viewModel.loadNextPage() }
        } else {
            showsReaderChrome.toggle()
        }
    }

    /// Creates the reader tap gesture with location-aware zones.
    private func readerTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleReaderTap(location: value.location, size: size)
            }
    }

    /// Creates the long-press gesture that asks before saving the current image.
    private func readerImageSaveLongPress(for imagePage: EHImagePage) -> some Gesture {
        LongPressGesture(minimumDuration: 0.6)
            .onEnded { _ in
                guard !isSavingImage else { return }
                pendingImageSavePage = imagePage
                showsImageSaveConfirmation = true
            }
    }

    /// Saves the confirmed reader image to the user's photo library.
    private func savePendingImageToPhotoLibrary() {
        guard let imagePage = pendingImageSavePage else { return }
        pendingImageSavePage = nil
        Task {
            await saveImageToPhotoLibrary(imagePage)
        }
    }

    /// Loads cached image bytes when possible and writes them to Photos.
    private func saveImageToPhotoLibrary(_ imagePage: EHImagePage) async {
        isSavingImage = true
        defer { isSavingImage = false }

        do {
            let data = try await imageDataForSaving(imagePage)
            try await PhotoLibraryImageSaver.save(data)
            imageSaveAlert = ReaderImageSaveAlert(title: AppCopy.readerSaveImageSuccess)
        } catch {
            imageSaveAlert = ReaderImageSaveAlert(
                title: String(format: AppCopy.readerSaveImageFailed, error.localizedDescription)
            )
        }
    }

    /// Returns current image data from cache first, then falls back to one network fetch.
    private func imageDataForSaving(_ imagePage: EHImagePage) async throws -> Data {
        if let cachedData = ImageCacheStore.shared.data(for: imagePage.imageURL) {
            return cachedData
        }

        let response = try await URLSessionEHHTTPClient().data(imagePage.imageURL, referer: imagePage.pageURL)
        await ImageCacheStore.shared.saveAsync(response.data, for: imagePage.imageURL, responseURL: response.url, context: imageCacheContext(for: imagePage))
        return response.data
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
            .disabled(!viewModel.canPresentPageJump || viewModel.isLoading)

            if !viewModel.sortedPageLinks.isEmpty {
                Button {
                    showsPageGridSheet = true
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .frame(width: 28, height: 20)
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel(AppCopy.readerPageGrid)
            }

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
                    } else if viewModel.isLoadingPageLinks {
                        Label(AppCopy.readerJumpLoadingPages, systemImage: "hourglass")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if viewModel.sortedPageLinks.isEmpty {
                        Label(AppCopy.readerJumpUnavailable, systemImage: "exclamationmark.triangle")
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
                LazyVGrid(columns: ReaderPageGridLayout.columns, alignment: .leading, spacing: 10) {
                    ForEach(viewModel.sortedPageLinks) { pageLink in
                        Button {
                            loadPageFromGrid(pageLink)
                        } label: {
                            VStack(spacing: 6) {
                                let thumbnail = pageThumbnailSource(for: pageLink)
                                pageThumbnail(url: thumbnail.url, crop: thumbnail.crop)

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

    /// Picks cached page images first so downloaded galleries show real page previews.
    private func pageThumbnailSource(for pageLink: EHGalleryPageLink) -> (url: URL?, crop: EHImageCrop?) {
        if let cachedURL = viewModel.cachedPreviewImageURL(for: pageLink.pageNumber) {
            return (cachedURL, nil)
        }
        return (pageLink.thumbnailURL, pageLink.thumbnailCrop)
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
        Task {
            await viewModel.loadAllPageLinksIfNeeded()
        }
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
        ReaderDisplayMenu(
            fitModeRaw: $fitModeRaw,
            zoomLevelRaw: $zoomLevelRaw,
            backgroundModeRaw: $backgroundModeRaw,
            canResetZoom: zoomLevel != .x1 || persistedPinchScale != 1.0,
            resetZoom: resetReaderZoom
        )
    }

}

/// Defines the shared fixed geometry for gallery and shared-image page directories.
enum ReaderPageGridLayout {
    static let columns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
        count: 3
    )
    static let thumbnailAspectRatio = 0.72
}

/// Keeps reader images centered against the full screen while chrome changes safe areas.
enum ReaderViewportLayout {
    /// Uses height-fit in landscape while preserving the stored portrait preference.
    static func effectiveFitMode(savedMode: ReaderFitMode, viewportSize: CGSize) -> ReaderFitMode {
        viewportSize.width > viewportSize.height ? .fitHeight : savedMode
    }

    /// Returns the physical screen-length edge used as image height in either orientation.
    static func fitHeightExtent(viewportSize: CGSize) -> CGFloat {
        max(max(viewportSize.width, viewportSize.height), 44)
    }

    /// Calculates the unzoomed image frame for the selected fit mode.
    static func imageSize(imageSize: CGSize?, mode: ReaderFitMode, viewportSize: CGSize) -> CGSize {
        let validImageSize = imageSize.flatMap { size in
            size.width > 0 && size.height > 0 ? size : nil
        } ?? CGSize(width: 1, height: 1)
        let aspectRatio = validImageSize.width / validImageSize.height

        switch mode {
        case .fitHeight:
            let height = fitHeightExtent(viewportSize: viewportSize)
            return CGSize(width: height * aspectRatio, height: height)
        case .fitPage, .fitWidth:
            let horizontalPadding: CGFloat = mode == .fitPage ? 32 : 0
            let width = max(viewportSize.width - horizontalPadding, 44)
            return CGSize(width: width, height: width / aspectRatio)
        }
    }

    /// Returns the unscaled content point currently displayed at the viewport center.
    static func viewportCenterAnchor(
        contentOffset: CGPoint,
        viewportSize: CGSize,
        zoomScale: CGFloat
    ) -> CGPoint {
        let scale = max(zoomScale, 0.001)
        return CGPoint(
            x: (contentOffset.x + viewportSize.width / 2) / scale,
            y: (contentOffset.y + viewportSize.height / 2) / scale
        )
    }

    /// Returns the content offset required to keep one unscaled point at screen center.
    static func contentOffset(
        centeredOn anchor: CGPoint,
        viewportSize: CGSize,
        zoomScale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: anchor.x * zoomScale - viewportSize.width / 2,
            y: anchor.y * zoomScale - viewportSize.height / 2
        )
    }
}

/// Hosts reader content in a native zoom view with system pinch anchoring.
struct CenteredReaderZoomScrollView<Content: View>: UIViewRepresentable {
    let contentSize: CGSize
    @Binding var zoomScale: CGFloat
    let minimumZoomScale: CGFloat
    let maximumZoomScale: CGFloat
    let showsIndicators: Bool
    let content: Content

    /// Creates a centered zoom surface for one explicitly sized reader image.
    init(
        contentSize: CGSize,
        zoomScale: Binding<CGFloat>,
        minimumZoomScale: CGFloat,
        maximumZoomScale: CGFloat,
        showsIndicators: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.contentSize = contentSize
        _zoomScale = zoomScale
        self.minimumZoomScale = minimumZoomScale
        self.maximumZoomScale = maximumZoomScale
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    /// Creates the UIKit scroll view and embeds the SwiftUI image content.
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.delaysContentTouches = false
        scrollView.addSubview(context.coordinator.hostingController.view)
        context.coordinator.update(parent: self, scrollView: scrollView)
        return scrollView
    }

    /// Applies content, sizing, and zoom preference updates from SwiftUI.
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    /// Creates the native scroll coordinator retained for the lifetime of this view.
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Coordinates native zoom callbacks with SwiftUI reader state.
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: CenteredReaderZoomScrollView
        let hostingController: UIHostingController<Content>
        private var lastContentSize = CGSize.zero
        private var lastViewportSize = CGSize.zero

        /// Creates a coordinator and hosting controller for the current image content.
        init(parent: CenteredReaderZoomScrollView) {
            self.parent = parent
            hostingController = UIHostingController(rootView: parent.content)
            super.init()
            hostingController.view.backgroundColor = .clear
        }

        /// Returns the hosted image view as the native zoom target.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        /// Keeps smaller zoomed content centered without overriding the native pinch anchor.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContentInsets(in: scrollView)
        }

        /// Publishes the final native zoom scale after the gesture finishes.
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            parent.zoomScale = scale
        }

        /// Updates hosted content and preserves a centered viewport across layout changes.
        func update(parent: CenteredReaderZoomScrollView, scrollView: UIScrollView) {
            let contentSizeChanged = lastContentSize != parent.contentSize
            let viewportSizeChanged = lastViewportSize != scrollView.bounds.size
            let shouldResizeContent = contentSizeChanged && !scrollView.isZooming
            let shouldCenterViewport = viewportSizeChanged && !scrollView.isZooming
            self.parent = parent
            hostingController.rootView = parent.content

            if shouldResizeContent {
                resizeContent(to: parent.contentSize, in: scrollView)
            }

            scrollView.minimumZoomScale = min(parent.minimumZoomScale, parent.maximumZoomScale)
            scrollView.maximumZoomScale = max(parent.maximumZoomScale, scrollView.minimumZoomScale)
            scrollView.showsHorizontalScrollIndicator = parent.showsIndicators
            scrollView.showsVerticalScrollIndicator = parent.showsIndicators
            scrollView.layoutIfNeeded()

            let targetScale = min(
                max(parent.zoomScale, scrollView.minimumZoomScale),
                scrollView.maximumZoomScale
            )
            if shouldResizeContent {
                scrollView.setZoomScale(targetScale, animated: false)
                centerContentInsets(in: scrollView)
            } else if !scrollView.isZooming, abs(scrollView.zoomScale - targetScale) > 0.001 {
                let viewportCenterAnchor = viewportCenterAnchor(in: scrollView)
                scrollView.setZoomScale(targetScale, animated: false)
                centerContentInsets(in: scrollView)
                preserveProgrammaticZoomAnchor(viewportCenterAnchor, in: scrollView)
            } else {
                centerContentInsets(in: scrollView)
            }

            if shouldResizeContent || shouldCenterViewport {
                centerViewportOnContent(in: scrollView)
            }
            if shouldResizeContent {
                lastContentSize = parent.contentSize
            }
            if shouldCenterViewport {
                lastViewportSize = scrollView.bounds.size
            }
        }

        /// Rebuilds the unscaled zoom target only when its intrinsic image size changes.
        private func resizeContent(to size: CGSize, in scrollView: UIScrollView) {
            scrollView.minimumZoomScale = 1
            scrollView.setZoomScale(1, animated: false)
            hostingController.view.frame = CGRect(origin: .zero, size: size)
            scrollView.contentSize = size
        }

        /// Returns the unscaled image coordinate currently beneath the viewport center.
        private func viewportCenterAnchor(in scrollView: UIScrollView) -> CGPoint {
            ReaderViewportLayout.viewportCenterAnchor(
                contentOffset: scrollView.contentOffset,
                viewportSize: scrollView.bounds.size,
                zoomScale: scrollView.zoomScale
            )
        }

        /// Adjusts symmetric insets when scaled content is smaller than the viewport.
        private func centerContentInsets(in scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        /// Keeps programmatic zoom changes centered while pinch gestures use their native centroid.
        private func preserveProgrammaticZoomAnchor(_ anchor: CGPoint, in scrollView: UIScrollView) {
            let desiredOffset = ReaderViewportLayout.contentOffset(
                centeredOn: anchor,
                viewportSize: scrollView.bounds.size,
                zoomScale: scrollView.zoomScale
            )
            scrollView.contentOffset = clampedOffset(desiredOffset, in: scrollView)
        }

        /// Centers the complete image after rotation or intrinsic-size changes.
        private func centerViewportOnContent(in scrollView: UIScrollView) {
            let centeredOffset = CGPoint(
                x: scrollView.contentSize.width / 2 - scrollView.bounds.midX,
                y: scrollView.contentSize.height / 2 - scrollView.bounds.midY
            )
            scrollView.contentOffset = clampedOffset(centeredOffset, in: scrollView)
        }

        /// Restricts a requested content offset to the native scrollable bounds.
        private func clampedOffset(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let minimumX = -scrollView.contentInset.left
            let minimumY = -scrollView.contentInset.top
            let maximumX = max(
                minimumX,
                scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right
            )
            let maximumY = max(
                minimumY,
                scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
            )
            return CGPoint(
                x: min(max(offset.x, minimumX), maximumX),
                y: min(max(offset.y, minimumY), maximumY)
            )
        }
    }
}

/// Exposes the shared reader display preferences from a toolbar menu.
struct ReaderDisplayMenu: View {
    @Binding var fitModeRaw: String
    @Binding var zoomLevelRaw: Double
    @Binding var backgroundModeRaw: String
    let canResetZoom: Bool
    let resetZoom: () -> Void

    var body: some View {
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
                resetZoom()
            } label: {
                Label(AppCopy.readerZoomReset, systemImage: "arrow.counterclockwise")
            }
            .disabled(!canResetZoom)

            Button {
                ReaderOrientationController.toggleOrientation()
            } label: {
                Label(AppCopy.readerToggleOrientation, systemImage: "rotate.right")
            }

            Picker(AppCopy.readerBackgroundMode, selection: $backgroundModeRaw) {
                ForEach(ReaderBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        } label: {
            Label(AppCopy.readerDisplayMenu, systemImage: "textformat.size")
        }
    }
}

/// Carries one reader image save result alert.
private struct ReaderImageSaveAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String?

    /// Creates an alert with an optional explanatory message.
    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

/// Saves reader image data to the user's photo library.
enum PhotoLibraryImageSaver {
    /// Requests add-only Photos access and creates a photo asset from the original bytes.
    static func save(_ data: Data) async throws {
        let status = await authorizedAddOnlyStatus()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryImageSaveError.denied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryImageSaveError.failed)
                }
            }
        }
    }

    /// Returns an add-only Photos authorization status, prompting the user when needed.
    private static func authorizedAddOnlyStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// Describes reader image save failures that need localized messages.
enum PhotoLibraryImageSaveError: LocalizedError {
    case denied
    case failed

    var errorDescription: String? {
        switch self {
        case .denied:
            AppCopy.readerSaveImageDenied
        case .failed:
            "相册没有返回保存结果。"
        }
    }
}

/// Requests manual portrait or landscape orientation changes for the reader.
enum ReaderOrientationController {
    /// Toggles the active scene between portrait and landscape.
    @MainActor
    static func toggleOrientation() {
        guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        let targetOrientations: UIInterfaceOrientationMask = windowScene.interfaceOrientation.isLandscape ? .portrait : .landscapeRight
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetOrientations)) { _ in }
        windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
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
    let referer: URL?
    let crop: EHImageCrop?
    let cacheContext: ImageCacheContext?
    let contentMode: CachedRemoteImageContentMode
    let animationMode: CachedRemoteImageAnimationMode
    let reloadToken: Int
    let decodeMaxPixelSize: Int?
    let onImageSizeChange: ((CGSize) -> Void)?
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @StateObject private var loader = CachedRemoteImageLoader()

    /// Creates a cached remote image view with custom loading and failure states.
    init(
        url: URL?,
        referer: URL? = nil,
        crop: EHImageCrop? = nil,
        cacheContext: ImageCacheContext? = nil,
        contentMode: CachedRemoteImageContentMode = .fit,
        animationMode: CachedRemoteImageAnimationMode = .animated,
        reloadToken: Int = 0,
        decodeMaxPixelSize: Int? = nil,
        onImageSizeChange: ((CGSize) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.referer = referer
        self.crop = crop
        self.cacheContext = cacheContext
        self.contentMode = contentMode
        self.animationMode = animationMode
        self.reloadToken = reloadToken
        self.decodeMaxPixelSize = decodeMaxPixelSize
        self.onImageSizeChange = onImageSizeChange
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                placeholder()
            case .success(let image):
                AnimatedImageDataView(image: image, contentMode: contentMode.uiViewContentMode)
                    .onAppear { onImageSizeChange?(image.size) }
            case .failure:
                failure()
            }
        }
        .task(id: loadKey) {
            await loader.load(
                url: url,
                referer: referer,
                crop: crop,
                animationMode: animationMode,
                decodeMaxPixelSize: decodeMaxPixelSize,
                context: cacheContext
            )
        }
    }

    private var loadKey: String {
        "\(url?.absoluteString ?? "nil")-\(crop?.hashValue ?? 0)-\(decodeMaxPixelSize ?? 0)-\(reloadToken)"
    }
}

/// Selects whether GIF data should animate or render as a static preview.
enum CachedRemoteImageAnimationMode {
    case animated
    case staticPreview
}

/// Tracks one cached remote image loading operation.
@MainActor
final class CachedRemoteImageLoader: ObservableObject {
    @Published private(set) var state: CachedRemoteImageState = .idle

    private let cacheStore: ImageCacheStore
    private let client: URLSessionEHHTTPClient
    private var lastLoadedKey: String?
    private let retryDelaysNanoseconds: [UInt64] = [350_000_000, 900_000_000]

    /// Creates an image loader with injectable cache and network dependencies.
    init(
        cacheStore: ImageCacheStore = .shared,
        client: URLSessionEHHTTPClient = URLSessionEHHTTPClient()
    ) {
        self.cacheStore = cacheStore
        self.client = client
    }

    /// Loads image data from cache first, then decodes it away from the main actor.
    func load(
        url: URL?,
        referer: URL? = nil,
        crop: EHImageCrop? = nil,
        animationMode: CachedRemoteImageAnimationMode = .animated,
        decodeMaxPixelSize: Int? = nil,
        context: ImageCacheContext? = nil
    ) async {
        guard let url else {
            state = .failure
            lastLoadedKey = nil
            return
        }

        for cacheURL in HitomiImageURLMigration.equivalentURLs(for: url) {
            if let cachedFileURL = cacheStore.cachedDataFileURL(for: cacheURL),
               let cachedImage = await Self.image(at: cachedFileURL, crop: crop, animationMode: animationMode, maxPixelSize: decodeMaxPixelSize) {
                if context != nil,
                   let byteCount = Self.fileSize(at: cachedFileURL) {
                    let responseURL = HitomiImageURLMigration.currentURL(for: cacheURL)
                    cacheStore.recordExistingData(for: url, responseURL: responseURL, byteCount: byteCount, context: context)
                }
                state = .success(cachedImage)
                lastLoadedKey = url.absoluteString
                return
            }
        }

        guard lastLoadedKey != url.absoluteString || !state.isLoading else { return }
        lastLoadedKey = url.absoluteString
        state = .loading

        do {
            let response = try await loadRemoteData(from: url, referer: referer)
            await cacheStore.saveAsync(response.data, for: url, responseURL: response.url, context: context)
            guard let image = await Self.image(from: response.data, crop: crop, animationMode: animationMode, maxPixelSize: decodeMaxPixelSize) else {
                state = .failure
                return
            }
            state = .success(image)
        } catch {
            state = .failure
        }
    }

    /// Downloads image bytes with short retries for transient URLSession failures.
    private func loadRemoteData(from url: URL, referer: URL?) async throws -> EHDataResponse {
        var lastError: Error?
        for attempt in 0...retryDelaysNanoseconds.count {
            do {
                try Task.checkCancellation()
                return try await client.data(url, referer: referer)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard Self.canRetryImageLoad(after: error), attempt < retryDelaysNanoseconds.count else { break }
                try await Task.sleep(nanoseconds: retryDelaysNanoseconds[attempt])
            }
        }
        throw lastError ?? EHNetworkError.invalidResponse
    }

    /// Returns true for network errors that often recover after a short delay.
    nonisolated private static func canRetryImageLoad(after error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorSecureConnectionFailed
        }

        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .secureConnectionFailed,
             .notConnectedToInternet,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    /// Decodes a cached image file off the main actor.
    nonisolated private static func image(at fileURL: URL, crop: EHImageCrop?, animationMode: CachedRemoteImageAnimationMode, maxPixelSize: Int?) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return ImageDataRenderer.uiImage(from: data, allowsAnimation: animationMode == .animated, crop: crop, maxPixelSize: maxPixelSize)
        }.value
    }

    /// Decodes network image bytes off the main actor.
    nonisolated private static func image(from data: Data, crop: EHImageCrop?, animationMode: CachedRemoteImageAnimationMode, maxPixelSize: Int?) async -> UIImage? {
        await Task.detached(priority: .utility) {
            ImageDataRenderer.uiImage(from: data, allowsAnimation: animationMode == .animated, crop: crop, maxPixelSize: maxPixelSize)
        }.value
    }

    /// Reads the cached file size without loading image bytes into memory again.
    nonisolated private static func fileSize(at fileURL: URL) -> Int64? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return Int64(values.fileSize ?? 0)
    }
}

/// Describes the loading state for cached remote image data.
enum CachedRemoteImageState {
    case idle
    case loading
    case success(UIImage)
    case failure

    /// Returns true while the loader is waiting for cache or network work.
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

/// Bridges image data into UIImageView so animated GIF frames can play.
struct AnimatedImageDataView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

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
        if imageView.image !== image {
            imageView.image = image
        }
        if image.images?.isEmpty == false {
            imageView.startAnimating()
        }
    }

    /// Calculates a SwiftUI size that preserves image aspect ratio when width is known.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard image.size.width > 0 else { return nil }

        if let width = proposal.width, let height = proposal.height {
            return CGSize(width: width, height: height)
        }

        if let width = proposal.width {
            return CGSize(width: width, height: width * image.size.height / image.size.width)
        }

        if let height = proposal.height, image.size.height > 0 {
            return CGSize(width: height * image.size.width / image.size.height, height: height)
        }

        return image.size
    }
}

/// Converts static and animated image data into UIImage values.
enum ImageDataRenderer {
    /// Builds a display image, downsampling static previews when a target size is supplied.
    static func uiImage(from data: Data, allowsAnimation: Bool = true, crop: EHImageCrop? = nil, maxPixelSize: Int? = nil) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        if let maxPixelSize, maxPixelSize > 0, !allowsAnimation, crop == nil {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }

        guard allowsAnimation, crop == nil else {
            return staticImage(from: source, fallbackData: data, crop: crop)
        }

        guard frameCount > 1 else {
            return staticImage(from: source, fallbackData: data, crop: nil)
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


    /// Decodes one still frame through ImageIO before falling back to UIKit decoding.
    private static func staticImage(from source: CGImageSource, fallbackData data: Data, crop: EHImageCrop?) -> UIImage? {
        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            if let croppedImage = cropped(cgImage, to: crop) {
                return UIImage(cgImage: croppedImage)
            }
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
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

    /// Crops a CGImage to the sprite rectangle when one is available.
    private static func cropped(_ image: CGImage, to crop: EHImageCrop?) -> CGImage? {
        guard let crop else { return nil }
        let rect = CGRect(
            x: crop.x,
            y: crop.y,
            width: min(crop.width, Double(image.width) - crop.x),
            height: min(crop.height, Double(image.height) - crop.y)
        )
        guard rect.width > 0, rect.height > 0 else { return nil }
        return image.cropping(to: rect)
    }
}

#Preview {
    NavigationStack {
        ReaderView()
    }
    .environmentObject(LibraryStore())
}
