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
    @State private var pendingImageSavePage: EHImagePage?
    @State private var showsImageSaveConfirmation = false
    @State private var imageSaveAlert: ReaderImageSaveAlert?
    @State private var isSavingImage = false
    @GestureState private var transientPinchScale: CGFloat = 1.0
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
                if !viewModel.sortedPageLinks.isEmpty {
                    Button {
                        showsPageGridSheet = true
                    } label: {
                        Label(AppCopy.readerPageGrid, systemImage: "square.grid.3x3")
                    }
                    .disabled(viewModel.isLoading)
                }

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

    private var activePinchScale: CGFloat {
        min(max(persistedPinchScale * transientPinchScale, 1.0), 4.0)
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
            ZStack {
                readerImageStage(for: imagePage, geometry: geometry)

                if showsReaderChrome {
                    readerChromeOverlay(for: imagePage)
                        .transition(.opacity)
                } else {
                    readerFloatingBackButton
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: showsReaderChrome)
        }
    }

    /// Shows the full-screen image surface with tap zones and pinch zoom.
    private func readerImageStage(for imagePage: EHImagePage, geometry: GeometryProxy) -> some View {
        ScrollView([.vertical, .horizontal], showsIndicators: showsReaderChrome) {
            HStack {
                Spacer(minLength: 0)

                CachedRemoteImageView(
                    url: imagePage.imageURL,
                    referer: imagePage.pageURL,
                    cacheContext: imageCacheContext(for: imagePage),
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
                .contentShape(Rectangle())
                .highPriorityGesture(readerImageSaveLongPress(for: imagePage))
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: zoomLevelRaw)
                .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: activePinchScale)

                Spacer(minLength: 0)
            }
            .padding(fitMode == .fitPage ? 16 : 0)
            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .center)
        }
        .background(readerBackgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(readerTapGesture(in: geometry.size))
        .simultaneousGesture(readerPinchGesture)
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
        CachedRemoteImageView(url: url, crop: crop, contentMode: .fill, animationMode: .staticPreview, decodeMaxPixelSize: 420) {
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
        if let knownLastPageNumber = viewModel.visibleLastPageNumber {
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
        return baseWidth * visibleZoomScale
    }

    private var visibleZoomScale: CGFloat {
        min(CGFloat(zoomLevel.rawValue) * activePinchScale, 4.0)
    }

    private var visibleZoomTitle: String {
        "\(Int((visibleZoomScale * 100).rounded()))%"
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

    /// Creates the pinch gesture used for temporary reader zoom.
    private var readerPinchGesture: some Gesture {
        MagnificationGesture()
            .updating($transientPinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                persistedPinchScale = min(max(persistedPinchScale * value, 1.0), 4.0)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
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
            .disabled(zoomLevel == .x1 && persistedPinchScale == 1.0)

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

        if let cachedFileURL = cacheStore.cachedDataFileURL(for: url),
           let cachedImage = await Self.image(at: cachedFileURL, crop: crop, animationMode: animationMode, maxPixelSize: decodeMaxPixelSize) {
            if context != nil,
               let byteCount = Self.fileSize(at: cachedFileURL) {
                cacheStore.recordExistingData(for: url, responseURL: url, byteCount: byteCount, context: context)
            }
            state = .success(cachedImage)
            lastLoadedKey = url.absoluteString
            return
        }

        guard lastLoadedKey != url.absoluteString || !state.isLoading else { return }
        lastLoadedKey = url.absoluteString
        state = .loading

        do {
            let response = try await client.data(url, referer: referer)
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
