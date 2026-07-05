import SwiftUI

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var viewModel: ReaderViewModel

    /// Creates a reader view that can start from a parsed image page URL.
    init(initialPageURL: URL? = nil) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(initialPageURL: initialPageURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .navigationTitle(AppCopy.readerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let originalImageURL = viewModel.imagePage?.originalImageURL {
                Link(destination: originalImageURL) {
                    Label(AppCopy.readerOriginalImage, systemImage: "arrow.up.right.square")
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
                        image
                            .resizable()
                            .scaledToFit()
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
                .padding()
            }

            Divider()

            navigationControls
                .padding()
        }
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
                Task { await viewModel.loadNextPage() }
            } label: {
                Label(AppCopy.readerNextPage, systemImage: "chevron.right")
            }
            .disabled(!viewModel.canLoadNextPage || viewModel.isLoading)
        }
        .buttonStyle(.bordered)
    }
}

#Preview {
    NavigationStack {
        ReaderView()
    }
    .environmentObject(LibraryStore())
}
