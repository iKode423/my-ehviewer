import SwiftUI

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderZoomLevel.storageKey) private var zoomLevelRaw = ReaderZoomLevel.x1.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    @StateObject private var viewModel: ReaderViewModel
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
                displayMenu

                if let originalImageURL = viewModel.imagePage?.originalImageURL {
                    Link(destination: originalImageURL) {
                        Label(AppCopy.readerOriginalImage, systemImage: "arrow.up.right.square")
                    }
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

                        AsyncImage(url: imagePage.imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                readerImage(image)
                                    .onTapGesture(count: 2) {
                                        toggleReaderZoom()
                                    }
                            case .failure:
                                imageLoadFailureView
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 320)
                            @unknown default:
                                imageLoadFailureView
                            }
                        }
                        .id(viewModel.imageReloadToken)
                        .frame(width: readerImageWidth(availableWidth: geometry.size.width))
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

    /// Applies the selected fit mode to a loaded reader image.
    private func readerImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
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
}

#Preview {
    NavigationStack {
        ReaderView()
    }
    .environmentObject(LibraryStore())
}
