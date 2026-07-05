import SwiftUI

/// Presents the gallery reader surface once a gallery is selected.
struct ReaderView: View {
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

