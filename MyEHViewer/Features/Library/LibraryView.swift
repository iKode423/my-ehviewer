import SwiftUI

/// Displays local favorites and reading history.
struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var selection = LibrarySelection.favorites

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
}

/// Selects the active local library section.
private enum LibrarySelection: String, CaseIterable, Identifiable {
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: AppCopy.libraryFavorites
        case .history: AppCopy.libraryHistory
        }
    }

    var emptyTitle: String {
        switch self {
        case .favorites: AppCopy.libraryEmptyFavoritesTitle
        case .history: AppCopy.libraryEmptyHistoryTitle
        }
    }

    var emptyMessage: String {
        switch self {
        case .favorites: AppCopy.libraryEmptyFavoritesMessage
        case .history: AppCopy.libraryEmptyHistoryMessage
        }
    }

    var emptySystemImage: String {
        switch self {
        case .favorites: "star"
        case .history: "clock"
        }
    }

    /// Returns records for the selected section.
    @MainActor
    func records(from store: LibraryStore) -> [LibraryGalleryRecord] {
        switch self {
        case .favorites: store.favorites
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
