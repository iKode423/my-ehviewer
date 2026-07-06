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
        VStack(spacing: 0) {
            Picker(AppCopy.libraryTitle, selection: $selection) {
                ForEach(LibrarySelection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
        }
        .navigationTitle(AppCopy.libraryTitle)
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
        if records.isEmpty {
            ContentUnavailableView(
                selection.emptyTitle,
                systemImage: selection.emptySystemImage,
                description: Text(selection.emptyMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(records) { record in
                LibraryRecordRow(record: record)
            }
            .listStyle(.plain)
        }
    }

    /// Displays the logged-in site's favorites endpoint.
    @ViewBuilder
    private var siteFavoritesContent: some View {
        if siteCookieStore.hasCookieHeader {
            SearchView(viewModel: siteFavoritesViewModel, embedsInNavigationStack: false, searchesOnAppear: true)
        } else {
            ContentUnavailableView(
                AppCopy.librarySiteFavoritesCookieTitle,
                systemImage: "key",
                description: Text(AppCopy.librarySiteFavoritesCookieMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    appNavigationStore.openReader(initialPageURL: lastReadPageURL)
                } label: {
                    Label(
                        String(format: AppCopy.libraryContinueReadingPage, String(lastReadPage)),
                        systemImage: "book"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
            .environmentObject(LibraryStore())
            .environmentObject(AppNavigationStore())
    }
}
