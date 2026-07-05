import SwiftUI

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @AppStorage(ReaderFitMode.storageKey) private var fitModeRaw = ReaderFitMode.fitPage.rawValue
    @AppStorage(ReaderBackgroundMode.storageKey) private var backgroundModeRaw = ReaderBackgroundMode.system.rawValue
    @StateObject private var viewModel: ReaderViewModel

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
    }

    private var fitMode: ReaderFitMode {
        ReaderFitMode(rawValue: fitModeRaw) ?? .fitPage
    }

    private var backgroundMode: ReaderBackgroundMode {
        ReaderBackgroundMode(rawValue: backgroundModeRaw) ?? .system
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
                Text(String(format: AppCopy.readerPageFormat, String(imagePage.pageNumber)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerForegroundStyle)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .padding()

            Divider()

            ScrollView([.vertical, .horizontal]) {
                AsyncImage(url: imagePage.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        readerImage(image)
                    case .failure:
                        ContentUnavailableView(AppCopy.readerRetry, systemImage: "photo")
                            .frame(minHeight: 320)
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 320)
                    @unknown default:
                        ContentUnavailableView(AppCopy.readerRetry, systemImage: "photo")
                            .frame(minHeight: 320)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(fitMode == .fitPage ? 16 : 0)
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
            .frame(maxWidth: fitMode == .fitWidth ? .infinity : nil)
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

            jumpPageMenu

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

    /// Provides jump navigation for known gallery page links.
    private var jumpPageMenu: some View {
        Menu {
            ForEach(viewModel.sortedPageLinks) { pageLink in
                Button {
                    Task { await viewModel.loadPage(pageLink) }
                } label: {
                    Text(String(format: AppCopy.galleryOpenPage, String(pageLink.pageNumber)))
                }
            }
        } label: {
            Label(AppCopy.readerJumpPage, systemImage: "list.number")
        }
        .disabled(viewModel.sortedPageLinks.isEmpty || viewModel.isLoading)
    }

    /// Exposes reader display preferences from the reader toolbar.
    private var displayMenu: some View {
        Menu {
            Picker(AppCopy.readerDisplayMode, selection: $fitModeRaw) {
                ForEach(ReaderFitMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
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

#Preview {
    NavigationStack {
        ReaderView()
    }
    .environmentObject(LibraryStore())
}
