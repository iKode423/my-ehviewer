import SwiftUI

/// Displays local favorites and reading history.
struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var siteCookieStore = SiteCookieStore.shared
    @StateObject private var siteFavoritesViewModel: SearchViewModel
    @State private var selection = LibrarySelection.localFavorites

    /// Creates a library view with a dedicated online favorites search model.
    init() {
        _siteFavoritesViewModel = StateObject(wrappedValue: SearchViewModel(initialSource: .favorites))
    }

    var body: some View {
        content
            .navigationTitle(AppCopy.libraryTitle)
            .navigationBarTitleDisplayMode(.large)
    }

    /// Shows library section and online favorite search controls at the top of the scroll content.
    private var libraryControls: some View {
        VStack(spacing: 10) {
            Picker(AppCopy.libraryTitle, selection: $selection) {
                ForEach(LibrarySelection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if selection == .siteFavorites, siteCookieStore.hasCookieHeader {
                siteFavoritesSearchBar
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    /// Displays the selected local collection.
    @ViewBuilder
    private var content: some View {
        switch selection {
        case .siteFavorites:
            siteFavoritesContent
        case .localFavorites, .history:
            localRecordsContent
        }
    }

    /// Displays local collection records.
    @ViewBuilder
    private var localRecordsContent: some View {
        let records = selection.records(from: libraryStore)
        libraryScrollContent {
            if records.isEmpty {
                ContentUnavailableView(
                    selection.emptyTitle,
                    systemImage: selection.emptySystemImage,
                    description: Text(selection.emptyMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                Group {
                    ForEach(records) { record in
                        LibraryRecordRow(record: record)
                            .padding(.horizontal)

                        Divider()
                            .padding(.leading, 100)
                    }
                }
            }
        }
    }

    /// Displays the logged-in site's favorites endpoint.
    @ViewBuilder
    private var siteFavoritesContent: some View {
        if siteCookieStore.hasCookieHeader {
            siteFavoritesResultList
        } else {
            libraryScrollContent {
                ContentUnavailableView(
                    AppCopy.librarySiteFavoritesCookieTitle,
                    systemImage: "key",
                    description: Text(AppCopy.librarySiteFavoritesCookieMessage)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    /// Provides keyword-only search for the online favorites collection.
    private var siteFavoritesSearchBar: some View {
        HStack(spacing: 12) {
            TextField(AppCopy.searchPlaceholder, text: $siteFavoritesViewModel.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    Task { await siteFavoritesViewModel.search() }
                }

            Button {
                Task { await siteFavoritesViewModel.search() }
            } label: {
                Label(AppCopy.searchButtonTitle, systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(siteFavoritesViewModel.isLoading)
        }
    }

    /// Shows online favorites pagination controls at the bottom of the result list.
    private var siteFavoritesPaginationControls: some View {
        HStack {
            Button {
                Task { await siteFavoritesViewModel.loadPreviousPage() }
            } label: {
                Label(AppCopy.searchPreviousPage, systemImage: "chevron.left")
            }
            .disabled(siteFavoritesViewModel.previousPageURL == nil || siteFavoritesViewModel.isLoading)

            Spacer()

            if siteFavoritesViewModel.isLoading {
                ProgressView()
            }

            Spacer()

            Button {
                Task { await siteFavoritesViewModel.loadNextPage() }
            } label: {
                Label(AppCopy.searchNextPage, systemImage: "chevron.right")
            }
            .disabled(siteFavoritesViewModel.nextPageURL == nil || siteFavoritesViewModel.isLoading)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Displays online favorite loading, error, empty, and result states.
    private var siteFavoritesResultList: some View {
        libraryScrollContent {
            siteFavoritesResultsContent
        }
        .refreshable {
            await siteFavoritesViewModel.refresh()
        }
        .task {
            await siteFavoritesViewModel.searchIfNeeded()
        }
    }

    /// Builds the main library scroller with controls flowing like regular content.
    private func libraryScrollContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                libraryControls

                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
    }

    /// Builds the online favorites list content without duplicating fixed controls.
    @ViewBuilder
    private var siteFavoritesResultsContent: some View {
        if siteFavoritesViewModel.isLoading && siteFavoritesViewModel.results.isEmpty {
            ContentUnavailableView(AppCopy.searchLoadingTitle, systemImage: "hourglass")
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if let errorMessage = siteFavoritesViewModel.errorMessage, siteFavoritesViewModel.results.isEmpty {
            VStack(spacing: 16) {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle")

                Button {
                    Task { await siteFavoritesViewModel.retry() }
                } label: {
                    Label(AppCopy.commonRetry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(siteFavoritesViewModel.isLoading)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if siteFavoritesViewModel.hasSearched && siteFavoritesViewModel.results.isEmpty {
            ContentUnavailableView(
                AppCopy.searchNoResultsTitle,
                systemImage: "magnifyingglass",
                description: Text(AppCopy.searchNoResultsMessage)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            if let errorMessage = siteFavoritesViewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.red.opacity(0.08))
            }

            ForEach(siteFavoritesViewModel.results) { result in
                NavigationLink {
                    GalleryDetailView(result: result)
                } label: {
                    SearchResultRow(result: result)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 100)
            }

            siteFavoritesPaginationControls
        }
    }
}

/// Selects the active local library section.
private enum LibrarySelection: String, CaseIterable, Identifiable {
    case localFavorites
    case siteFavorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localFavorites: AppCopy.libraryFavorites
        case .siteFavorites: AppCopy.librarySiteFavorites
        case .history: AppCopy.libraryHistory
        }
    }

    var emptyTitle: String {
        switch self {
        case .localFavorites: AppCopy.libraryEmptyFavoritesTitle
        case .siteFavorites: AppCopy.librarySiteFavoritesCookieTitle
        case .history: AppCopy.libraryEmptyHistoryTitle
        }
    }

    var emptyMessage: String {
        switch self {
        case .localFavorites: AppCopy.libraryEmptyFavoritesMessage
        case .siteFavorites: AppCopy.librarySiteFavoritesCookieMessage
        case .history: AppCopy.libraryEmptyHistoryMessage
        }
    }

    var emptySystemImage: String {
        switch self {
        case .localFavorites: "star"
        case .siteFavorites: "icloud"
        case .history: "clock"
        }
    }

    /// Returns records for the selected section.
    @MainActor
    func records(from store: LibraryStore) -> [LibraryGalleryRecord] {
        switch self {
        case .localFavorites: store.favorites
        case .siteFavorites: []
        case .history: store.history
        }
    }
}

/// Renders one locally saved gallery record.
private struct LibraryRecordRow: View {
    let record: LibraryGalleryRecord
    @EnvironmentObject private var appNavigationStore: AppNavigationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                GalleryDetailView(result: record.searchResult)
            } label: {
                SearchResultRow(result: record.searchResult)
            }

            if let lastReadPage = record.lastReadPage {
                Label(String(format: AppCopy.libraryLastReadPage, String(lastReadPage)), systemImage: "bookmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastReadPageURL = record.lastReadPageURL, let lastReadPage = record.lastReadPage {
                Button {
                    appNavigationStore.openReader(initialPageURL: lastReadPageURL, totalPageCount: record.pageCount)
                } label: {
                    Label(
                        String(format: AppCopy.libraryContinueReadingPage, String(lastReadPage)),
                        systemImage: "book"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(LibraryStore())
            .environmentObject(AppNavigationStore())
    }
}
