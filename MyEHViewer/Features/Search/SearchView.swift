import SwiftUI

/// Displays the search entry point before the live site search is connected.
struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                searchBar

                ContentUnavailableView(
                    AppCopy.searchEmptyTitle,
                    systemImage: "magnifyingglass",
                    description: Text(AppCopy.searchEmptyMessage)
                )
            }
            .padding()
            .navigationTitle(AppCopy.searchTitle)
        }
    }

    /// Provides the first visible search control for the application shell.
    private var searchBar: some View {
        HStack(spacing: 12) {
            TextField(AppCopy.searchPlaceholder, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Button(AppCopy.searchButtonTitle) {}
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

#Preview {
    SearchView()
}

