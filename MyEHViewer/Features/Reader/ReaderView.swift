import SwiftUI

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
    let initialPageURL: URL?

    /// Creates a reader view that can start from a parsed image page URL.
    init(initialPageURL: URL? = nil) {
        self.initialPageURL = initialPageURL
    }

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                AppCopy.readerEmptyTitle,
                systemImage: "book.pages",
                description: Text(AppCopy.readerEmptyMessage)
            )
            .navigationTitle(AppCopy.readerTitle)
        }
    }
}

#Preview {
    ReaderView()
}
