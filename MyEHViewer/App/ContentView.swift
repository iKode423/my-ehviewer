import SwiftUI

/// Hosts the root tab navigation for search, reading, and settings.
struct ContentView: View {
    @StateObject private var libraryStore = LibraryStore()

    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label(AppCopy.searchTitle, systemImage: "magnifyingglass")
                }

            NavigationStack {
                LibraryView()
            }
                .tabItem {
                    Label(AppCopy.libraryTitle, systemImage: "books.vertical")
                }

            NavigationStack {
                ReaderView()
            }
                .tabItem {
                    Label(AppCopy.readerTitle, systemImage: "book.pages")
                }

            SettingsView()
                .tabItem {
                    Label(AppCopy.settingsTitle, systemImage: "gearshape")
                }
        }
        .environmentObject(libraryStore)
    }
}

#Preview {
    ContentView()
}
