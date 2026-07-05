import SwiftUI

/// Hosts the root tab navigation for search, reading, and settings.
struct ContentView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label(AppCopy.searchTitle, systemImage: "magnifyingglass")
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
    }
}

#Preview {
    ContentView()
}
