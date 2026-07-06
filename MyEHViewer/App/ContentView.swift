import SwiftUI

/// Hosts the root tab navigation for search, reading, and settings.
struct ContentView: View {
    @StateObject private var libraryStore = LibraryStore()
    @AppStorage(AppThemeMode.storageKey) private var themeModeRaw = AppThemeMode.system.rawValue

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
        .preferredColorScheme(preferredColorScheme)
        .tint(.appAccent)
    }

    private var themeMode: AppThemeMode {
        AppThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    /// Returns the shared app accent color required by the light theme.
    static let appAccent = Color(red: 0.0, green: 168.0 / 255.0, blue: 1.0)
}

#Preview {
    ContentView()
}
